// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {UserOperation} from "account-abstraction/interfaces/UserOperation.sol";
import {IPaymaster} from "account-abstraction/interfaces/IPaymaster.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";

contract MagicSpend is Ownable, IPaymaster {
    struct WithdrawRequest {
        bytes signature;
        address asset;
        uint256 amount;
        uint256 nonce;
        uint48 expiry;
    }

    mapping(address => uint256) public gasExcessBalance;
    mapping(uint256 => mapping(address => bool)) internal _nonceUsed;

    event MagicSpendWithdrawal(address indexed account, address indexed asset, uint256 amount, uint256 nonce);

    error InvalidSignature();
    error Expired();
    error InvalidNonce(uint256 nonce);
    error RequestLessThanGasMaxCost(uint256 requested, uint256 maxCost);
    error UnsupportedPaymasterAsset(address asset);
    error NoPrevalidatedWithdrawForAccount();
    error NoExcess();

    /// @dev Requires that the caller is the EntryPoint.
    modifier onlyEntryPoint() virtual {
        if (msg.sender != entryPoint()) revert Unauthorized();
        _;
    }

    constructor(address _owner) {
        Ownable._initializeOwner(_owner);
    }

    receive() external payable {}

    /// @inheritdoc IPaymaster
    function validatePaymasterUserOp(UserOperation calldata userOp, bytes32, uint256 maxCost)
        external
        onlyEntryPoint
        returns (bytes memory context, uint256 validationData)
    {
        WithdrawRequest memory withdrawRequest = abi.decode(userOp.paymasterAndData[20:], (WithdrawRequest));

        if (withdrawRequest.amount < maxCost) {
            revert RequestLessThanGasMaxCost(withdrawRequest.amount, maxCost);
        }

        if (withdrawRequest.asset != address(0)) {
            revert UnsupportedPaymasterAsset(withdrawRequest.asset);
        }

        _validateRequest(userOp.sender, withdrawRequest);

        bool sigFailed = !isValidWithdrawSignature(userOp.sender, withdrawRequest);
        validationData = (sigFailed ? 1 : 0) | (uint256(withdrawRequest.expiry) << 160);

        uint256 excess = withdrawRequest.amount - maxCost;
        gasExcessBalance[userOp.sender] += excess;

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
            gasExcessBalance[account] += (withheld - actualGasCost);
            return;
        }

        // credit user difference between actual and withheld
        // and unwithdrawn excess
        uint256 excess = gasExcessBalance[account] + (withheld - actualGasCost);
        delete gasExcessBalance[account];

        if (excess > 0) {
            _withdraw(address(0), account, excess);
        }
    }

    /// @dev allows an account, during execution, to withdraw
    /// withdrawRequest.amount minus maxCost held for gas
    /// allows account to get funding for gas + other purposes with one withdrawRequest
    function withdrawGasExcess() external {
        uint256 amount = gasExcessBalance[msg.sender];
        // we could allow 0 value transfers, but prefer to be explicit
        if (amount == 0) revert NoExcess();

        delete gasExcessBalance[msg.sender];
        _withdraw(address(0), msg.sender, amount);
    }

    /// @notice Allows caller to withdraw funds by calling with a valid `withdrawRequest`
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

    /// @notice allows owner to withdraw funds
    function ownerWithdraw(address asset, address to, uint256 amount) external onlyOwner {
        _withdraw(asset, to, amount);
    }

    /// @notice Deposits ETH from this contract funds to EntryPoint
    function entryPointDeposit(uint256 amount) external payable onlyOwner {
        SafeTransferLib.safeTransferETH(entryPoint(), amount);
    }

    /// @notice Withdraws ETH from EntryPoint to `to`
    function entryPointWithdraw(address payable to, uint256 amount) external onlyOwner {
        IEntryPoint(entryPoint()).withdrawTo(to, amount);
    }

    /// @notice Adds stake to EntryPoint
    function entryPointAddStake(uint256 amount, uint32 unstakeDelaySeconds) external payable onlyOwner {
        IEntryPoint(entryPoint()).addStake{value: amount}(unstakeDelaySeconds);
    }

    /// @notice Unlocks stake in EntryPoint
    function entryPointUnlockStake() external onlyOwner {
        IEntryPoint(entryPoint()).unlockStake();
    }

    /// @notice Withdraws stake from EntryPoint to `to`
    function entryPointWithdrawStake(address payable to) external onlyOwner {
        IEntryPoint(entryPoint()).withdrawStake(to);
    }

    /// @notice Returns whether the withdrawRequest signature is valid for the given account
    /// @dev Does not validate nonce or expiry
    function isValidWithdrawSignature(address account, WithdrawRequest memory withdrawRequest)
        public
        view
        returns (bool)
    {
        return SignatureCheckerLib.isValidSignatureNow(
            owner(), getHash(account, withdrawRequest), withdrawRequest.signature
        );
    }

    /// @notice Returns the hash to be signed for a given withdrawRequest
    function getHash(address account, WithdrawRequest memory withdrawRequest) public view returns (bytes32) {
        return _toPrefixedMessageHash(
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

    /// @notice Returns whether the nonce has been used for the given account
    function nonceUsed(address account, uint256 nonce) external view returns (bool) {
        return _nonceUsed[nonce][account];
    }

    /// @dev Returns the canonical ERC4337 EntryPoint contract.
    function entryPoint() public pure returns (address) {
        return 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
    }

    function _toPrefixedMessageHash(bytes memory message) internal pure returns (bytes32) {
        return SignatureCheckerLib.toEthSignedMessageHash(message);
    }

    /// @dev runs all non-signature validation checks
    /// signature validation done separately so we can not revert in validatePaymasterUserOp
    function _validateRequest(address account, WithdrawRequest memory withdrawRequest) internal {
        if (_nonceUsed[withdrawRequest.nonce][account]) {
            revert InvalidNonce(withdrawRequest.nonce);
        }

        _nonceUsed[withdrawRequest.nonce][account] = true;

        // This is emitted ahead of fund transfer, but allows a consolidated code path
        emit MagicSpendWithdrawal(account, withdrawRequest.asset, withdrawRequest.amount, withdrawRequest.nonce);
    }

    function _withdraw(address asset, address to, uint256 amount) internal {
        if (asset == address(0)) {
            SafeTransferLib.safeTransferETH(to, amount);
        } else {
            SafeTransferLib.safeTransfer(asset, to, amount);
        }
    }
}
