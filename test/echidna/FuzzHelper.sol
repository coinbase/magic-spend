// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IPaymaster} from "account-abstraction/interfaces/IPaymaster.sol";
import {UserOperation} from "account-abstraction/interfaces/UserOperation.sol";

import {MagicSpend} from "../../src/MagicSpend.sol";
import {FuzzSetup} from "./FuzzSetup.sol";

contract FuzzHelper is FuzzSetup {
    /// @dev Wrapper around `sut.validatePaymasterUserOp()` to assert upon its correct behavior.
    /// @dev Prank `Entrypoint`.
    /// @dev Inputs control:
    ///         - 0 <= amount <= PAYMASTER_MAX_BALANCE
    ///         - 0 <= maxGasCost <= amount
    /// @dev Assertions:
    ///         - `sut.validatePaymasterUserOp()` MUST NOT revert
    function _validatePaymasterUserOp(uint256 amount, uint256 maxGasCost)
        internal
        returns (bytes memory context, uint256 validationData)
    {
        (amount, maxGasCost) = _genericClampings({amount: amount, gas: maxGasCost});

        uint256 nonce = nonces[WITHDRAWER]++;
        uint48 expiry = uint48(block.timestamp + 1 days);

        MagicSpend.WithdrawRequest memory request = _getWithdrawRequest({
            withdrawer: WITHDRAWER,
            asset: address(0x0), // use ETH
            amount: amount,
            nonce: nonce,
            expiry: expiry
        });

        UserOperation memory userOp = _getUserOp({withdrawer: WITHDRAWER, request: request});

        vm.prank(sut.entryPoint());
        try sut.validatePaymasterUserOp(
            userOp,
            sha256("ignored"), // userOp hash is ignored
            maxGasCost
        ) returns (bytes memory context_, uint256 validationData_) {
            return (context_, validationData_);
        } catch {
            assert(false);
        }
    }

    /// @dev Wrapper around `sut.postOp()` to assert upon its correct behavior.
    /// @dev Prank `Entrypoint`.
    /// @dev Inputs control:
    ///         - 0 <= maxGasCost <= PAYMASTER_MAX_BALANCE
    ///         - 0 <= actualGasCost <= maxGasCost
    /// @dev Assertions:
    ///         - [on success && on userOp success]
    ///             - user account balance MUST have been incremented by its associated remaining gas excess
    ///             - `sut` gas excess balance for user account MUST have been reset to 0
    ///         - [on revert]:
    ///             - revert case MUST be `SafeTransferLib.ETHTransferFailed`
    function _postOp(IPaymaster.PostOpMode mode, uint256 maxGasCost, uint256 actualGasCost, bytes memory context)
        internal
        returns (bool success)
    {
        (maxGasCost, actualGasCost) = _genericClampings({amount: maxGasCost, gas: actualGasCost});

        (uint256 withheld, address account) = abi.decode(context, (uint256, address));
        assert(account == WITHDRAWER); // sanity check

        uint256 balanceBefore = address(WITHDRAWER).balance;
        uint256 gasExcessBalanceBefore = sut.gasExcessBalance(WITHDRAWER);

        vm.prank(sut.entryPoint());
        try sut.postOp({mode: mode, context: abi.encode(maxGasCost, WITHDRAWER), actualGasCost: actualGasCost}) {
            success = true;

            if (mode == IPaymaster.PostOpMode.opSucceeded) {
                // Assert the user account balance has been incremented by its associated remaining gas excess.
                assert(
                    address(WITHDRAWER).balance == balanceBefore + gasExcessBalanceBefore + (withheld - actualGasCost)
                );

                // Assert the `sut` `sut` gas excess balance for user account has been reset to 0
                assert(sut.gasExcessBalance(WITHDRAWER) == 0);
            }
        } catch (bytes memory returnData) {
            bytes4 errorSelector = bytes4(returnData);

            // Assert that the only accepted revert case is `SafeTransferLib.ETHTransferFailed`.
            assert(errorSelector == SafeTransferLib.ETHTransferFailed.selector);
            success = false;
        }
    }

    /// @dev Wrapper around `sut.withdrawGasExcess()` to assert upon its correct behavior.
    /// @dev Prank `withdrawer`.
    /// @dev Assertions:
    ///         - [on success]:
    ///             - `withdrawer` balance after withdraw MUST have increased by withdrawn amount
    ///             - `sut` gas excess balance for `withdrawer` MUST have been reset to 0
    ///         - [on revert]:
    ///             - [if failOnNoExcess] revert case  MUST NOT be `MagicSpend.NoExcess`
    ///             - [else] revert case MUST be `SafeTransferLib.ETHTransferFailed`
    function _withdrawGasExcess(address withdrawer, bool failOnNoExcess) internal {
        uint256 balanceBefore = address(withdrawer).balance;
        uint256 gasExcessBalanceBefore = sut.gasExcessBalance(withdrawer);

        vm.prank(withdrawer);
        try sut.withdrawGasExcess() {
            // Assert the `withdrawer` balance after withdraw has increased by the withdrawn amount.
            assert(address(withdrawer).balance == balanceBefore + gasExcessBalanceBefore);

            // Assert `sut` gas excess balance for `withdrawer` has been reset to 0.
            assert(sut.gasExcessBalance(withdrawer) == 0);
        } catch (bytes memory returnData) {
            bytes4 errorSelector = bytes4(returnData);

            // Assert revert case is not `MagicSpend.NoExcess` unless accepted.
            if (errorSelector == MagicSpend.NoExcess.selector) {
                assert(failOnNoExcess == false);
            } else {
                // Assert that the only accepted revert case is `SafeTransferLib.ETHTransferFailed`.
                assert(errorSelector == SafeTransferLib.ETHTransferFailed.selector);
            }
        }
    }

    /// @dev Build a `UserOperation` that targets the `MagicSpend` paymaster contract with the given `request`.
    /// @dev Does NOT sign the user operation (i.e., `signature` is left empty).
    function _getUserOp(address withdrawer, MagicSpend.WithdrawRequest memory request)
        internal
        view
        returns (UserOperation memory userOp)
    {
        userOp = UserOperation({
            sender: withdrawer,
            nonce: 0,
            initCode: "",
            callData: "",
            callGasLimit: 49152,
            verificationGasLimit: 378989,
            preVerificationGas: 273196043,
            maxFeePerGas: 1000304,
            maxPriorityFeePerGas: 1000000,
            paymasterAndData: abi.encodePacked(address(sut), abi.encode(request)),
            signature: ""
        });
    }

    /// @dev Build and sign a `MagicSpend.WithdrawRequest`.
    function _getWithdrawRequest(address withdrawer, address asset, uint256 amount, uint256 nonce, uint48 expiry)
        internal
        returns (MagicSpend.WithdrawRequest memory)
    {
        return MagicSpend.WithdrawRequest({
            asset: asset,
            amount: amount,
            nonce: nonce,
            expiry: expiry,
            signature: _getSignature(withdrawer, asset, amount, nonce, expiry)
        });
    }

    /// @dev Sign the given withdraw request using the `OWNER_SK` private key.
    function _getSignature(address withdrawer, address asset, uint256 amount, uint256 nonce, uint48 expiry)
        internal
        returns (bytes memory signature)
    {
        bytes memory message = abi.encode(address(sut), withdrawer, block.chainid, asset, amount, nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_SK, _toPrefixedMessageHash(message));
        signature = abi.encodePacked(r, s, v);
    }

    /// @dev Return an Ethereum Signed Message (EIP-191), created from the given `message`.
    function _toPrefixedMessageHash(bytes memory message) internal pure returns (bytes32) {
        return SignatureCheckerLib.toEthSignedMessageHash(message);
    }

    /// @dev Camp 0 <= actualGasCost <= maxGasCost <= amount <= PAYMASTER_MAX_BALANCE
    function _genericClampings(uint256 amount, uint256 maxGasCost, uint256 actualGasCost)
        internal
        returns (uint256 amount_, uint256 maxGasCost_, uint256 actualGasCost_)
    {
        (amount_, maxGasCost_) = _genericClampings({amount: amount, gas: maxGasCost});
        actualGasCost_ = _clampABelowB({a: actualGasCost, b: maxGasCost_});
    }

    /// @dev Clamp 0 <= gas <= amount <= PAYMASTER_MAX_BALANCE
    function _genericClampings(uint256 amount, uint256 gas) internal returns (uint256 amount_, uint256 gas_) {
        amount_ = _clampAmount(amount);
        gas_ = _clampABelowB({a: gas, b: amount_});
    }

    /// @dev Clamp 0 <= amount <= PAYMASTER_MAX_BALANCE.
    function _clampAmount(uint256 amount) private returns (uint256 amount_) {
        amount_ = clampBetween(amount, 0, PAYMASTER_MAX_BALANCE);
    }

    /// @dev Clamp 0 <= a <= b.
    function _clampABelowB(uint256 a, uint256 b) private returns (uint256 a_) {
        a_ = clampBetween(a, 0, b);
    }
}
