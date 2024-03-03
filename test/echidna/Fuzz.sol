// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IPaymaster} from "account-abstraction/interfaces/IPaymaster.sol";

import {MagicSpend} from "../../src/MagicSpend.sol";
import {FuzzHelper} from "./FuzzHelper.sol";

contract Fuzz is FuzzHelper {
    constructor() payable FuzzHelper() {}

    /// @dev Deposit some eth amount on the `sut` contract.
    /// @dev Inputs control:
    ///         - 0 <= amount <= (PAYMASTER_MAX_BALANCE - sut.balance)
    /// @dev Assertions:
    ///         - ETH transfer MUST NOT fail
    /// @dev Ghost variables:
    ///         - `totalDeposited` is increased by the deposited amount
    function depositPaymasterBalance(uint256 amount) public {
        amount = clampBetween(amount, 0, PAYMASTER_MAX_BALANCE - address(sut).balance);

        (bool success,) = address(sut).call{value: amount}("");
        assert(success);

        totalDeposited += amount;
    }

    /// @dev Wrapper around a `_withdrawGasExcess()` with {withdrawer: WITHDRAWER, failOnNoExcess: false} as param.
    /// @dev Assertions:
    ///      - see `_withdrawGasExcess()` assertions.
    function withdrawGasExcess() public {
        _withdrawGasExcess({withdrawer: WITHDRAWER, failOnNoExcess: false});
    }

    /// @dev Wrapper around `sut.withdraw()` to assert upon its correct behavior.
    /// @dev Inputs control:
    ///         - 0 <= amount <= PAYMASTER_MAX_BALANCE
    ///         - block.timestamp <= expiry <= type(uint48).max
    /// @dev Assertions:
    ///         - [on success]:
    ///             - `withdrawer` balance after withdraw MUST have increased by withdrawn amount
    ///         - [on revert]:
    ///             - revert case MUST be `SafeTransferLib.ETHTransferFailed`
    /// @dev Ghost variables:
    ///         - `totalWithdrawn` is increased by the withdrawn amount
    function withdraw(uint256 amount, uint48 expiry) public {
        amount = clampBetween(amount, 0, PAYMASTER_MAX_BALANCE);
        expiry = uint48(clampBetween(expiry, uint48(block.timestamp), type(uint48).max));

        uint256 nonce = nonces[WITHDRAWER]++;

        MagicSpend.WithdrawRequest memory request = _getWithdrawRequest({
            withdrawer: WITHDRAWER,
            asset: address(0x0), // use ETH
            amount: amount,
            nonce: nonce,
            expiry: expiry
        });

        uint256 withdrawerBalanceBefore = WITHDRAWER.balance;

        vm.prank(WITHDRAWER);
        try sut.withdraw(request) {
            // Assert the `withdrawer` balance after withdraw has increased by withdrawn amount.
            assert(WITHDRAWER.balance == withdrawerBalanceBefore + amount);

            totalWithdrawn += amount;
        } catch (bytes memory returnData) {
            bytes4 errorSelector = bytes4(returnData);

            // Assert that the only accepted revert case is `SafeTransferLib.ETHTransferFailed`.
            assert(errorSelector == SafeTransferLib.ETHTransferFailed.selector);
        }
    }

    /// @dev Simulate the Entrypoint executing a `UserOperation` by:
    ///         - calling `_validatePaymasterUserOp()` on the `sut`
    ///         - [OPTIONAL] calling `_withdrawGasExcess()` to simulate the userOp using the `sut` funds not only for gas
    ///         - calling `_postOp()` on the `sut`
    ///         - [OPTIONAL] re-calling `_postOp()` on the `sut`
    /// @dev Assertions:
    ///         - see `_validatePaymasterUserOp()` assertions
    ///         - `sut` and user account balances MUST NOT change in between the `_validatePaymasterUserOp()` call
    ///         - see `_withdrawGasExcess()` assertions
    ///         - `sut` (resp. user account) balance MUST decrease (resp. increase) by the excess withdrawn amount (if any)
    ///         - see `_postOp()` assertions
    ///         - `_postOp()` MUST NOT revert twice in a row
    ///         - [on second `_postOp()`] the user account gas excess balance MUST have been incremented by the unused gas
    ///         - Overall the `sut` balance MUST have been correctly decreased
    ///         - Overall the user account balance MUST have been correctly increased
    /// @dev Ghost variables:
    ///         - `totalWithdrawn` is increased by the computed withdrawn amount
    function simulateUserOp(uint256 amount, uint256 maxGasCost, uint256 actualGasCost, bool withdrawExcess) public {
        (amount, maxGasCost, actualGasCost) =
            _genericClampings({amount: amount, maxGasCost: maxGasCost, actualGasCost: actualGasCost});

        uint256 excess = amount - maxGasCost;
        uint256 paymasterBalBefore = address(sut).balance;
        uint256 userBalBefore = address(WITHDRAWER).balance;

        // User op validation phase.
        (bytes memory context,) = _validatePaymasterUserOp({amount: amount, maxGasCost: maxGasCost});
        // Assert calling `_validatePaymasterUserOp()` has no effect on the `sut` and user account balances.
        uint256 paymasterBalAfterValidation = address(sut).balance;
        uint256 userBalAfterValidation = address(WITHDRAWER).balance;

        assert(paymasterBalAfterValidation == paymasterBalBefore);
        assert(userBalAfterValidation == userBalBefore);

        // User op execution phase.
        if (withdrawExcess) {
            _withdrawGasExcess({withdrawer: WITHDRAWER, failOnNoExcess: excess != 0});
        }

        uint256 paymasterBalAfterWithdraw = address(sut).balance;
        uint256 userBalAfterWithdraw = address(WITHDRAWER).balance;

        // Assert the `sut` (resp. user account) balance has been decreased (resp. increased) by the withdrawn amount (if any).
        // NOTE: New block to avoid stack too deep error.
        {
            uint256 withdrawExesss = withdrawExcess ? excess : 0;
            assert(paymasterBalAfterWithdraw == paymasterBalAfterValidation - withdrawExesss);
            assert(userBalAfterWithdraw == userBalBefore + withdrawExesss);
        }

        // Post user op execution phase.
        {
            uint256 gasExcessBalanceBefore = sut.gasExcessBalance(WITHDRAWER);

            bool success = _postOp({
                mode: IPaymaster.PostOpMode.opSucceeded,
                maxGasCost: maxGasCost,
                actualGasCost: actualGasCost,
                context: context
            });

            if (!success) {
                success = _postOp({
                    mode: IPaymaster.PostOpMode.postOpReverted,
                    maxGasCost: maxGasCost,
                    actualGasCost: actualGasCost,
                    context: context
                });

                // Assert `_postOp()` MUST NOT revert twice in a row.
                assert(success);

                // Assert the `sut` gas excess balance associated with the user account has been incremented by the unused gas.
                (uint256 withheld,) = abi.decode(context, (uint256, address));
                assert(sut.gasExcessBalance(WITHDRAWER) == gasExcessBalanceBefore + withheld - actualGasCost);
            }
        }

        uint256 paymasterBalAfterPostOp = address(sut).balance;
        uint256 userBalAfterPostOp = address(WITHDRAWER).balance;

        // NOTE: The balance decrease on the `sut` (Paymaster) is not simply `amount` as the `actualGasCost`
        //       is already deposited on the Entrypoint (thus the subscration).
        // NOTE: If the userOp call succeeds the `postOp()` callback automatically returns the remaining gas
        //       excess (maxCost - actualGasCost) to the user account.
        uint256 withdrawFromPaymaster = amount - actualGasCost;

        // Assert overall the `sut` balance has been decreased as excpected.
        assert(paymasterBalAfterPostOp == paymasterBalBefore - withdrawFromPaymaster);

        // Assert overall the user account balance has been increased as excpected.
        assert(userBalAfterPostOp == userBalBefore + withdrawFromPaymaster);

        totalWithdrawn += withdrawFromPaymaster;
    }

    /// @dev Ensure the `sut` balance always macthes with the `totalDeposited` and `totalWithdrawn` trackers.
    /// @dev Assertions:
    ///         - `sut` balance must always be equal to `totalDeposited - totalWithdrawn`
    function accountingInvariant() public view {
        assert(address(sut).balance == totalDeposited - totalWithdrawn);
    }
}
