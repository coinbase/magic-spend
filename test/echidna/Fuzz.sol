// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./FuzzSetup.sol";

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IPaymaster} from "account-abstraction/interfaces/IPaymaster.sol";

contract Fuzz is FuzzSetup {
    // TODO: better account management
    address withdrawer = address(0xb0b);

    constructor() payable FuzzSetup() {}

    function validatePaymasterUserOp(uint256 amount, uint256 maxGasCost) internal returns (bytes memory, uint256) {
        uint256 nonce = nonces[withdrawer]++;
        uint48 expiry = uint48(block.timestamp + 1 days);

        uint256 max = address(magic).balance * 10; // some arbitrary number thats larger than the balance
        amount = clampBetween(amount, 0, max);
        maxGasCost = clampBetween(maxGasCost, 0, amount);

        MagicSpend.WithdrawRequest memory request = _getWithdrawRequest(
            withdrawer,
            address(0x0), // use ETH
            amount,
            nonce,
            expiry
        );

        UserOperation memory userOp = _getUserOp(withdrawer, request);

        vm.prank(magic.entryPoint());
        try magic.validatePaymasterUserOp(
            userOp,
            sha256("ignored"), // userOp hash is ignored
            maxGasCost
        ) returns (bytes memory context, uint256 validationData) {
            log("validatePaymasterUserOp: success");

            return (context, validationData);
        } catch {
            log("validatePaymasterUserOp: failed");
            assert(false);
        }
    }

    function postOp(uint8 mode, uint256 maxGasCost, uint256 actualGasCost) internal {
        IPaymaster.PostOpMode mode = IPaymaster.PostOpMode(clampBetween(mode, 0, 2));
        uint256 max = address(magic).balance * 10; // some arbitrary number thats larger than the balance
        maxGasCost = clampBetween(maxGasCost, 0, max);
        actualGasCost = clampBetween(actualGasCost, 0, maxGasCost);

        vm.prank(magic.entryPoint());
        try magic.postOp(mode, abi.encode(maxGasCost, withdrawer), actualGasCost) {
            log("postOp: success");
        } catch (bytes memory returnData) {
            bytes4 errorSelector = bytes4(returnData);

            if (errorSelector == SafeTransferLib.ETHTransferFailed.selector) {
                // ignore eth transfer failed errors
            } else {
                log("postOp: failed");
                assert(false);
            }
        }
    }

    function withdrawGasExcess() public {
        _withdrawGasExcess(withdrawer, false);
    }

    function _withdrawGasExcess(address _withdrawer, bool failOnNoExcess) internal {
        vm.prank(_withdrawer);
        try magic.withdrawGasExcess() {
            log("withdrawGasExcess: success");
        } catch (bytes memory returnData) {
            bytes4 errorSelector = bytes4(returnData);

            if (errorSelector == MagicSpend.NoExcess.selector) {
                if (failOnNoExcess) {
                    log("withdrawGasExcess: failed (no excess)");
                    assert(false);
                }
            } else if (errorSelector == SafeTransferLib.ETHTransferFailed.selector) {
                // ignore eth transfer failed errors
            } else {
                log("withdrawGasExcess: failed");
                assert(false);
            }
        }
    }

    function simulateUserOp(uint256 amount, uint256 maxGasCost, uint256 actualGasCost, bool withdrawExcess) public {
        // todo: generic clamping helpers
        // warning: these clampings need to be identical to the ones in the validatePaymasterUserOp and postOp functions
        amount = clampBetween(amount, 0, address(magic).balance * 10);
        maxGasCost = clampBetween(maxGasCost, 0, amount);
        actualGasCost = clampBetween(actualGasCost, 0, maxGasCost);

        uint256 excess = amount - maxGasCost;

        uint256 paymasterBalBefore = address(magic).balance;
        uint256 userBalBefore = address(withdrawer).balance;

        (bytes memory context, uint256 validationData) = validatePaymasterUserOp(amount, maxGasCost);

        uint256 paymasterBalAfterValidation = address(magic).balance;
        uint256 userBalAfterValidation = address(withdrawer).balance;

        if (withdrawExcess) {
            _withdrawGasExcess(withdrawer, excess != 0);
        }

        uint256 paymasterBalAfterWithdraw = address(magic).balance;
        uint256 userBalAfterWithdraw = address(withdrawer).balance;

        // todo: fuzz modes
        postOp(0, maxGasCost, actualGasCost);

        uint256 paymasterBalAfterPostOp = address(magic).balance;
        uint256 userBalAfterPostOp = address(withdrawer).balance;

        log("paymasterBalBefore", paymasterBalBefore);
        log("paymasterBalAfterValidation", paymasterBalAfterValidation);
        log("paymasterBalAfterWithdraw", paymasterBalAfterWithdraw);
        log("paymasterBalAfterPostOp", paymasterBalAfterPostOp);
        log("userBalBefore", userBalBefore);
        log("userBalAfterValidation", userBalAfterValidation);
        log("userBalAfterWithdraw", userBalAfterWithdraw);
        log("userBalAfterPostOp", userBalAfterPostOp);

        assert(paymasterBalAfterValidation == paymasterBalBefore);
        if (withdrawExcess) {
            assert(paymasterBalAfterWithdraw == paymasterBalAfterValidation - excess);
        } else {
            assert(paymasterBalAfterWithdraw == paymasterBalAfterValidation);
        }
        assert(paymasterBalAfterPostOp == paymasterBalBefore - amount + actualGasCost);

        assert(userBalAfterValidation == userBalBefore);
        if (withdrawExcess) {
            assert(userBalAfterWithdraw == userBalBefore + excess);
        } else {
            assert(userBalAfterWithdraw == userBalBefore);
        }
        assert(userBalAfterPostOp == userBalBefore + amount - actualGasCost);

        totalWithdrawn += amount - actualGasCost;
    }

    function withdraw(uint256 amount, uint48 expiry) public {
        uint256 nonce = nonces[withdrawer]++;
        amount = clampBetween(amount, 0, address(magic).balance);
        expiry = uint48(clampBetween(expiry, uint48(block.timestamp), type(uint48).max));

        MagicSpend.WithdrawRequest memory request = _getWithdrawRequest(
            withdrawer,
            address(0x0), // use ETH
            amount,
            nonce,
            expiry
        );

        uint256 withdrawerBalanceBefore = withdrawer.balance;

        vm.prank(withdrawer);
        try magic.withdraw(request) {
            assert(withdrawer.balance == withdrawerBalanceBefore + amount);

            totalWithdrawn += amount;
        } catch {
            assert(false);
        }
    }

    function echinda_invariantTotalWithdrawn() public {
        uint256 paymasterBalance = address(magic).balance;

        log("paymasterBalance", paymasterBalance);
        log("totalWithdrawn", totalWithdrawn);

        assert(paymasterBalance == PAYMASTER_STARTING_BALANCE - totalWithdrawn);
    }
}
