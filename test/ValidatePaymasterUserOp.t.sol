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
        uint256 pendingWithdrawals,
        uint256 withdrawAmount
    ) public {
        initialBalance = bound(initialBalance, 0, type(uint128).max - 2);
        pendingWithdrawals = bound(pendingWithdrawals, 0, initialBalance);
        uint256 availableBalance = initialBalance - pendingWithdrawals;
        withdrawAmount = bound(withdrawAmount, availableBalance + 1, type(uint128).max - 1);

        maxCost = withdrawAmount;
        amount = withdrawAmount;

        vm.deal(address(magic), initialBalance);
        vm.store(address(magic), bytes32(uint256(0)), bytes32(pendingWithdrawals + 1));

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
