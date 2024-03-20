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
/// @author Coinbase (https://github.com/coinbase/magic-spend)
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

    /// @notice Track the ETH available to be withdrawn per user.
    mapping(address user => uint256 amount) internal _withdrawableETH;

    /// @dev Mappings keeping track of already used nonces per user to prevent replays of withdraw requests.
    mapping(uint256 nonce => mapping(address user => bool used)) internal _nonceUsed;

    /// @notice Emitted after validating a withdraw request and funds are about to be withdrawn.
    ///
    /// @param account The account address.
    /// @param asset   The asset withdrawn.
    /// @param amount  The amount withdrawn.
    /// @param nonce   The request nonce.
    event MagicSpendWithdrawal(address indexed account, address indexed asset, uint256 amount, uint256 nonce);

    /// @notice Thrown when the withdraw request signature is invalid.
    ///
    /// @dev The withdraw request signature MUST be:
    ///         - an ECDSA signature following EIP-191 (version 0x45)
    ///         - performed over the content specified in `getHash()`
    ///         - signed by the current owner of this contract
    error InvalidSignature();

    /// @notice Thrown when trying to use a withdraw request after its expiry has been reached.
    error Expired();

    /// @notice Thrown when trying to replay a withdraw request with the same nonce.
    ///
    /// @param nonce The already used nonce.
    error InvalidNonce(uint256 nonce);

    /// @notice Thrown during validation in the context of ERC4337, when the withdraw request amount is insufficient
    ///         to sponsor the transaction gas.
    ///
    /// @param requested The withdraw request amount.
    /// @param maxCost   The max gas cost required by the Entrypoint.
    error RequestLessThanGasMaxCost(uint256 requested, uint256 maxCost);

    /// @notice Thrown when the withdraw request asset is not ETH (zero address).
    ///
    /// @param asset The requested asset.
    error UnsupportedPaymasterAsset(address asset);

    /// @notice Thrown during `UserOperation` validation when the current balance is insufficient to cover the
    ///         requested amount (exluding the `maxGasCost` set by the Entrypoint).
    ///
    /// @param requestedAmount The requested amount excluding gas.
    /// @param balance         The current contract balance.
    error InsufficientBalance(uint256 requestedAmount, uint256 balance);

    /// @notice Thrown when trying to withdraw funds but nothing is available.
    error NoExcess();

    /// @notice Thrown in when `postOp()` is called a second time with `PostOpMode.postOpReverted`.
    ///
    /// @dev This should only really occur if for unknown reasons the transfer of the withdrawable
    ///      funds to the user account failed (i.e. this contract's ETH balance is insufficient or
    ///      the user account refused the funds or ran out of gas on receive).
    error UnexpectedPostOpRevertedMode();

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
        uint256 withdrawAmount = withdrawRequest.amount;

        if (withdrawAmount < maxCost) {
            revert RequestLessThanGasMaxCost(withdrawAmount, maxCost);
        }

        if (withdrawRequest.asset != address(0)) {
            revert UnsupportedPaymasterAsset(withdrawRequest.asset);
        }

        _validateRequest(userOp.sender, withdrawRequest);

        bool sigFailed = !isValidWithdrawSignature(userOp.sender, withdrawRequest);
        validationData = (sigFailed ? 1 : 0) | (uint256(withdrawRequest.expiry) << 160);

        // Ensure at validation that the contract has enough balance to cover the requested funds.
        // NOTE: This check is necessary to enforce that the contract will be able to transfer the remaining funds
        //       when `postOp()` is called back after the `UserOperation` has been executed.
        if (address(this).balance < withdrawAmount) {
            revert InsufficientBalance(withdrawAmount, address(this).balance);
        }

        // NOTE: Do not include the gas part in withdrawable funds as it will be handled in `postOp()`.
        _withdrawableETH[userOp.sender] += withdrawAmount - maxCost;
        context = abi.encode(maxCost, userOp.sender);
    }

    /// @inheritdoc IPaymaster
    function postOp(IPaymaster.PostOpMode mode, bytes calldata context, uint256 actualGasCost)
        external
        onlyEntryPoint
    {
        // `PostOpMode.postOpReverted` should be impossible.
        // Only possible cause would be if this contract does not own enough ETH to transfer
        // but this is checked at the validation step.
        assert(mode != PostOpMode.postOpReverted);

        (uint256 maxGasCost, address account) = abi.decode(context, (uint256, address));

        // Compute the total remaining funds available for the user accout.
        // NOTE: Take into account the user operation gas that was not consumed.
        uint256 withdrawable = _withdrawableETH[account] + (maxGasCost - actualGasCost);

        // Send the all remaining funds to the user accout.
        delete _withdrawableETH[account];
        if (withdrawable > 0) {
            SafeTransferLib.forceSafeTransferETH(account, withdrawable, SafeTransferLib.GAS_STIPEND_NO_STORAGE_WRITES);
        }
    }

    /// @notice Allows the sender to withdraw any available funds associated with him.
    ///
    /// @dev Can be called back during the `UserOperation` execution to sponsor funds for non-gas related
    ///      use cases (e.g., swap or mint).
    function withdrawGasExcess() external {
        uint256 amount = _withdrawableETH[msg.sender];
        // we could allow 0 value transfers, but prefer to be explicit
        if (amount == 0) revert NoExcess();

        delete _withdrawableETH[msg.sender];
        _withdraw(address(0), msg.sender, amount);
    }

    /// @notice Allows caller to withdraw funds by calling with a valid `withdrawRequest`
    ///
    /// @param withdrawRequest The withdraw request.
    function withdraw(WithdrawRequest memory withdrawRequest) external {
        _validateRequest(msg.sender, withdrawRequest);

        if (!isValidWithdrawSignature(msg.sender, withdrawRequest)) {
            revert InvalidSignature();
        }

        if (block.timestamp > withdrawRequest.expiry) {
            revert Expired();
        }

        // reserve funds for gas, will credit user with difference in post op
        _withdraw(withdrawRequest.asset, msg.sender, withdrawRequest.amount);
    }

    /// @notice Withdraws funds from this contract.
    ///
    /// @dev Reverts if not called by the owner of the contract.
    ///
    /// @param asset The asset to withdraw.
    /// @param to The beneficiary address.
    /// @param amount The amount to withdraw.
    function ownerWithdraw(address asset, address to, uint256 amount) external onlyOwner {
        _withdraw(asset, to, amount);
    }

    /// @notice Deposits ETH from this contract funds into the EntryPoint.
    ///
    /// @dev Reverts if not called by the owner of the contract.
    ///
    /// @param amount The amount to deposit on the the Entrypoint.
    function entryPointDeposit(uint256 amount) external payable onlyOwner {
        SafeTransferLib.safeTransferETH(entryPoint(), amount);
    }

    /// @notice Withdraws ETH from the EntryPoint.
    ///
    /// @dev Reverts if not called by the owner of the contract.
    ///
    /// @param to     The beneficiary address.
    /// @param amount The amount to withdraw from the Entrypoint.
    function entryPointWithdraw(address payable to, uint256 amount) external onlyOwner {
        IEntryPoint(entryPoint()).withdrawTo(to, amount);
    }

    /// @notice Adds stake to the EntryPoint.
    ///
    /// @dev Reverts if not called by the owner of the contract.
    ///
    /// @param amount              The amount to stake in the Entrypoint.
    /// @param unstakeDelaySeconds The duration for which the stake cannot be withdrawn.
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
    /// @param account         The account address.
    /// @param withdrawRequest The withdraw request.
    ///
    /// @return `true` if the signature is valid, else `false`.
    function isValidWithdrawSignature(address account, WithdrawRequest memory withdrawRequest)
        public
        view
        returns (bool)
    {
        return SignatureCheckerLib.isValidSignatureNow(
            owner(), getHash(account, withdrawRequest), withdrawRequest.signature
        );
    }

    /// @notice Returns the hash to be signed for a given `account` and `withdrawRequest` pair.
    ///
    /// @dev Returns an EIP-191 compliant Ethereum Signed Message (version 0x45), see
    ///      https://eips.ethereum.org/EIPS/eip-191.
    ///
    /// @param account         The account address.
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
    /// @param nonce   The nonce to check.
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
    /// @param account         The account address.
    /// @param withdrawRequest The withdraw request to validate.
    function _validateRequest(address account, WithdrawRequest memory withdrawRequest) internal {
        if (_nonceUsed[withdrawRequest.nonce][account]) {
            revert InvalidNonce(withdrawRequest.nonce);
        }

        _nonceUsed[withdrawRequest.nonce][account] = true;

        // This is emitted ahead of fund transfer, but allows a consolidated code path
        emit MagicSpendWithdrawal(account, withdrawRequest.asset, withdrawRequest.amount, withdrawRequest.nonce);
    }

    /// @notice Withdraws funds from this contract.
    ///
    /// @dev Callers MUST validate that the withdraw is legitimate before calling this method as
    ///      no validation is performed here.
    ///
    /// @param asset  The asset to withdraw.
    /// @param to     The beneficiary address.
    /// @param amount The amount to withdraw.
    function _withdraw(address asset, address to, uint256 amount) internal {
        if (asset == address(0)) {
            SafeTransferLib.safeTransferETH(to, amount);
        } else {
            SafeTransferLib.safeTransfer(asset, to, amount);
        }
    }
}
