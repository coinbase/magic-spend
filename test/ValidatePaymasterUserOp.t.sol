// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21;

import "./PaymasterMagicSpendBase.sol";
import "./Validate.t.sol";

contract ValidatePaymasterUserOpTest is PaymasterMagicSpendBaseTest, ValidateTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(magic.entryPoint());
    }

    function test_revertsIfMaxCostMoreThanRequested() public {
        maxCost = amount + 1;
        vm.expectRevert(abi.encodeWithSelector(MagicSpend.RequestLessThanGasMaxCost.selector, amount, maxCost));
        magic.validatePaymasterUserOp(_getUserOp(), userOpHash, maxCost);
    }

    function test_revertsInsufficientAvailableBalance(
        uint256 initialBalance,
        uint256 firstWithdrawAmount,
        uint256 excessAmount
    ) public {
        initialBalance = bound(initialBalance, 0, type(uint128).max);
        excessAmount = bound(excessAmount, 1, type(uint128).max);

        firstWithdrawAmount = bound(firstWithdrawAmount, 0, initialBalance);
        uint256 availableBalance = initialBalance - firstWithdrawAmount;
        uint256 secondWithdrawAmount = availableBalance + excessAmount;

        vm.deal(address(magic), initialBalance);

        // 1st validation call to increase the `_pendingWithdrawals` traker.
        amount = firstWithdrawAmount;
        maxCost = amount;
        magic.validatePaymasterUserOp(_getUserOp(), userOpHash, maxCost);

        nonce += 1;
        amount = secondWithdrawAmount;
        maxCost = amount;

        // 2nd validation call is expected to revert as `secondWithdrawAmount` is above the MagicSpend `availableBalance`
        // by the fuzzed `excessAmount`.
        vm.expectRevert(
            abi.encodeWithSelector(MagicSpend.InsufficientAvailableBalance.selector, amount, availableBalance)
        );
        magic.validatePaymasterUserOp(_getUserOp(), userOpHash, maxCost);
    }

    function test_returnsCorrectly() public {
        (bytes memory context, uint256 validationData) =
            magic.validatePaymasterUserOp(_getUserOp(), userOpHash, maxCost);
        (uint256 withheld, address sender) = abi.decode(context, (uint256, address));
        assertEq(maxCost, withheld);
        assertEq(sender, withdrawer);
        assertEq(uint160(validationData), 0);
        assertEq(uint160(validationData >> 160), expiry);
        assertEq(uint160(validationData >> 160 + 48), 0);
    }

    function test_revertsIfWithdrawAssetNotZero() public {
        asset = address(1);
        vm.expectRevert(abi.encodeWithSelector(MagicSpend.UnsupportedPaymasterAsset.selector, asset));
        magic.validatePaymasterUserOp(_getUserOp(), userOpHash, maxCost);
    }

    function test_returns1sIfWrongSignature() public {
        ownerPrivateKey = ownerPrivateKey + 1;

        (, uint256 validationData) = magic.validatePaymasterUserOp(_getUserOp(), userOpHash, maxCost);
        assertEq(uint160(validationData), 1);
    }

    function test_emitsCorrectly(address, uint256 amount_, uint256 nonce_) public override {
        amount_ = bound(amount_, 0, type(uint256).max - 1);
        maxCost = amount_;
        super.test_emitsCorrectly(magic.entryPoint(), amount_, nonce_);
    }

    function _validateInvokingCall() internal override {
        magic.validatePaymasterUserOp(_getUserOp(), userOpHash, maxCost);
    }
}
