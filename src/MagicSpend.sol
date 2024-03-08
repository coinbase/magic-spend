// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {UserOperation} from "account-abstraction/interfaces/UserOperation.sol";
import {IPaymaster} from "account-abstraction/interfaces/IPaymaster.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";

/// @title Magic Spend
///
/// @author Coinbase (https://github.com/coinbase/smart-wallet)
///
/// @notice ERC4337 Paymaster implementation compatible with Entrypoint v0.6.
///
/// @dev See https://eips.ethereum.org/EIPS/eip-4337#extension-paymasters.
contract MagicSpend is Ownable, IPaymaster {
    /// @notice Signed withdraw request allowing accounts to withdraw funds from this contract.
    struct WithdrawRequest {
        /// @dev The signature associated with this withdraw request.
        bytes signature;
        /// @dev The asset to withdraw. NOTE: Only ETH (associated with zero address) is supported for now.
        address asset;
        /// @dev The requested amount to withdraw.
        uint256 amount;
        /// @dev Unique nonce used to prevent replays.
        uint256 nonce;
        /// @dev The maximum expiry the withdraw request remains valid for.
        uint48 expiry;
    }

    /// @notice Track the funds available to be withdrawn per user.
    mapping(address user => uint256 amount) public withdrawableFunds;

    /// @dev Mappings keeping track of already used nonces per user to prevent replays of withdraw requests.
    mapping(uint256 nonce => mapping(address user => bool used)) internal _nonceUsed;

    /// @notice Emitted after validating a withdraw request and funds are about to be withdrawn.
    ///
    /// @param account The account address.
    /// @param asset The asset withdrawn.
    /// @param amount The amount withdrawn.
    /// @param nonce The request nonce.
    event MagicSpendWithdrawal(address indexed account, address indexed asset, uint256 amount, uint256 nonce);

    /// @notice Reverted when the withdraw request signature is invalid.
    ///
    /// @dev The withdraw request signature MUST be:
    ///         - an ECDSA signature following EIP-191 (version 0x45)
    ///         - performed over the content specified in `getHash()`
    ///         - signed by the current owner of this contract
    error InvalidSignature();

    /// @notice Reverted when trying to use a withdraw request after its expiry has been reched.
    error Expired();

    /// @notice Reverted when trying to replay a withdraw request with the same nonce.
    ///
    /// @param nonce The already used nonce.
    error InvalidNonce(uint256 nonce);

    /// @notice Reverted during validation in the context of ERC4337, when the withraw reques amount is insufficient
    ///         to sponsor the transaction gas.
    ///
    /// @param requested The withdraw request amount.
    /// @param maxCost The max gas cost required by the Entrypoint.
    error RequestLessThanGasMaxCost(uint256 requested, uint256 maxCost);

    /// @notice Reverted when the withdraw request asset is not ETH (zero address).
    ///
    /// @param asset The requested asset.
    error UnsupportedPaymasterAsset(address asset);

    /// @notice Reverted when trying to withdraw funds but nothing is available.
    error NoExcess();

    /// @dev Requires that the caller is the EntryPoint.
    modifier onlyEntryPoint() virtual {
        if (msg.sender != entryPoint()) revert Unauthorized();
        _;
    }

    /// @notice Deploy the contract and set its initial owner.
    ///
    /// @param _owner The initial owner of this contract.
    constructor(address _owner) {
        Ownable._initializeOwner(_owner);
    }

    /// @notice Receive function allowing ETH to be deposited in this contract.
    receive() external payable {}

    /// @inheritdoc IPaymaster
    function validatePaymasterUserOp(UserOperation calldata userOp, bytes32, uint256 maxCost)
        external
        onlyEntryPoint
        returns (bytes memory context, uint256 validationData)
    {
        WithdrawRequest memory withdrawRequest = abi.decode(userOp.paymasterAndData[20:], (WithdrawRequest));

        if (withdrawRequest.amount < maxCost) {
            revert RequestLessThanGasMaxCost({requested: withdrawRequest.amount, maxCost: maxCost});
        }

        if (withdrawRequest.asset != address(0)) {
            revert UnsupportedPaymasterAsset(withdrawRequest.asset);
        }

        _validateRequest({account: userOp.sender, withdrawRequest: withdrawRequest});

        bool sigFailed = !isValidWithdrawSignature({account: userOp.sender, withdrawRequest: withdrawRequest});
        validationData = (sigFailed ? 1 : 0) | (uint256(withdrawRequest.expiry) << 160);

        uint256 excess = withdrawRequest.amount - maxCost;
        withdrawableFunds[userOp.sender] += excess;

        context = abi.encode(maxCost, userOp.sender);
    }

    /// @inheritdoc IPaymaster
    function postOp(IPaymaster.PostOpMode mode, bytes calldata context, uint256 actualGasCost)
        external
        onlyEntryPoint
    {
        (uint256 withheld, address account) = abi.decode(context, (uint256, address));

        if (mode == IPaymaster.PostOpMode.postOpReverted) {
            // we failed to payout the excess, save it so the user can call withdrawGasExcess later
            withdrawableFunds[account] += (withheld - actualGasCost);
            return;
        }

        // credit user difference between actual and withheld
        // and unwithdrawn excess
        uint256 excess = withdrawableFunds[account] + (withheld - actualGasCost);
        delete withdrawableFunds[account];

        if (excess > 0) {
            _withdraw({asset: address(0), to: account, amount: excess});
        }
    }

    /// @notice Allows the sender to withdraw any available funds associated with him.
    ///
    /// @dev Can be called back during the `UserOperation` execution to sponsor funds for non-gas related
    ///      use cases (e.g., swap or mint).
    function withdrawGasExcess() external {
        uint256 amount = withdrawableFunds[msg.sender];
        // we could allow 0 value transfers, but prefer to be explicit
        if (amount == 0) {
            revert NoExcess();
        }

        delete withdrawableFunds[msg.sender];
        _withdraw({asset: address(0), to: msg.sender, amount: amount});
    }

    /// @notice Allows caller to withdraw funds by calling with a valid `withdrawRequest`
    ///
    /// @param withdrawRequest The withdraw request.
    function withdraw(WithdrawRequest memory withdrawRequest) external {
        _validateRequest({account: msg.sender, withdrawRequest: withdrawRequest});

        if (!isValidWithdrawSignature({account: msg.sender, withdrawRequest: withdrawRequest})) {
            revert InvalidSignature();
        }

        if (block.timestamp > withdrawRequest.expiry) {
            revert Expired();
        }

        // reserve funds for gas, will credit user with difference in post op
        _withdraw({asset: withdrawRequest.asset, to: msg.sender, amount: withdrawRequest.amount});
    }

    /// @notice Withdraws funds from this contract.
    ///
    /// @dev Reverts if not called by the owner of the contract.
    ///
    /// @param asset The asset to withdraw.
    /// @param to The beneficiary address.
    /// @param amount The amount to withdraw.
    function ownerWithdraw(address asset, address to, uint256 amount) external onlyOwner {
        _withdraw({asset: asset, to: to, amount: amount});
    }

    /// @notice Deposits ETH from this contract funds into the EntryPoint.
    ///
    /// @dev Reverts if not called by the owner of the contract.
    ///
    /// @param amount The amount to deposit on the the Entrypoint.
    function entryPointDeposit(uint256 amount) external payable onlyOwner {
        SafeTransferLib.safeTransferETH({to: entryPoint(), amount: amount});
    }

    /// @notice Withdraws ETH from the EntryPoint.
    ///
    /// @dev Reverts if not called by the owner of the contract.
    ///
    /// @param to The beneficiary address.
    /// @param amount The amount to withdraw from the Entrypoint.
    function entryPointWithdraw(address payable to, uint256 amount) external onlyOwner {
        IEntryPoint(entryPoint()).withdrawTo({withdrawAddress: to, withdrawAmount: amount});
    }

    /// @notice Adds stake to the EntryPoint.
    ///
    /// @dev Reverts if not called by the owner of the contract.
    ///
    /// @param amount The amount to stake in the Entrypoint.
    /// @param unstakeDelaySeconds XXX
    function entryPointAddStake(uint256 amount, uint32 unstakeDelaySeconds) external payable onlyOwner {
        IEntryPoint(entryPoint()).addStake{value: amount}(unstakeDelaySeconds);
    }

    /// @notice Unlocks stake in the EntryPoint.
    ///
    /// @dev Reverts if not called by the owner of the contract.
    function entryPointUnlockStake() external onlyOwner {
        IEntryPoint(entryPoint()).unlockStake();
    }

    /// @notice Withdraws stake from the EntryPoint.
    ///
    /// @dev Reverts if not called by the owner of the contract.
    ///
    /// @param to The beneficiary address.
    function entryPointWithdrawStake(address payable to) external onlyOwner {
        IEntryPoint(entryPoint()).withdrawStake(to);
    }

    /// @notice Returns whether the `withdrawRequest` signature is valid for the given `account`.
    ///
    /// @dev Does not validate nonce or expiry.
    ///
    /// @param account The account address.
    /// @param withdrawRequest The withdraw request.
    ///
    /// @return `true` if the signature is valid, else `false`.
    function isValidWithdrawSignature(address account, WithdrawRequest memory withdrawRequest)
        public
        view
        returns (bool)
    {
        return SignatureCheckerLib.isValidSignatureNow({
            signer: owner(),
            hash: getHash(account, withdrawRequest),
            signature: withdrawRequest.signature
        });
    }

    /// @notice Returns the hash to be signed for a given `account` and `withdrawRequest` pair.
    ///
    /// @dev Returns an EIP-191 compliant Ethereum Signed Message (version 0x45), see
    ///      https://eips.ethereum.org/EIPS/eip-191.
    ///
    /// @param account The account address.
    /// @param withdrawRequest The withdraw request.
    ///
    /// @return The hash to be signed for the given `account` and `withdrawRequest`.
    function getHash(address account, WithdrawRequest memory withdrawRequest) public view returns (bytes32) {
        return SignatureCheckerLib.toEthSignedMessageHash(
            abi.encode(
                address(this),
                account,
                block.chainid,
                withdrawRequest.asset,
                withdrawRequest.amount,
                withdrawRequest.nonce,
                withdrawRequest.expiry
            )
        );
    }

    /// @notice Returns whether the `nonce` has been used by the given `account`.
    ///
    /// @param account The account address.
    /// @param nonce The nonce to check.
    ///
    /// @return `true` if the nonce has already been used by the account, else `false`.
    function nonceUsed(address account, uint256 nonce) external view returns (bool) {
        return _nonceUsed[nonce][account];
    }

    /// @notice Returns the canonical ERC-4337 EntryPoint v0.6 contract.
    function entryPoint() public pure returns (address) {
        return 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
    }

    /// @notice Validate the `withdrawRequest` against the given `account`.
    ///
    /// @dev Runs all non-signature validation checks.
    /// @dev Reverts if the withdraw request nonce has already been used.
    ///
    /// @param account The account address.
    /// @param withdrawRequest The withdraw request to validate.
    function _validateRequest(address account, WithdrawRequest memory withdrawRequest) internal {
        if (_nonceUsed[withdrawRequest.nonce][account]) {
            revert InvalidNonce(withdrawRequest.nonce);
        }

        _nonceUsed[withdrawRequest.nonce][account] = true;

        // This is emitted ahead of fund transfer, but allows a consolidated code path
        emit MagicSpendWithdrawal({
            account: account,
            asset: withdrawRequest.asset,
            amount: withdrawRequest.amount,
            nonce: withdrawRequest.nonce
        });
    }

    /// @notice Withdraws funds from this contract.
    ///
    /// @dev Callers MUST validate that the withdraw is legitimate before calling this method as
    ///      no validation is performed here.
    ///
    /// @param asset The asset to withdraw.
    /// @param to The beneficiary address.
    /// @param amount The amount to withdraw.
    function _withdraw(address asset, address to, uint256 amount) internal {
        if (asset == address(0)) {
            SafeTransferLib.safeTransferETH({to: to, amount: amount});
        } else {
            SafeTransferLib.safeTransfer({token: asset, to: to, amount: amount});
        }
    }
}
