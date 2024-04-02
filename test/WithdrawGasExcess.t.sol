// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21;

import "./PaymasterMagicSpendBase.sol";

contract WithdrawGasExcess is PaymasterMagicSpendBaseTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(magic.entryPoint());
    }

    function test_transferExcess(uint256 amount_, uint256 maxCost_, uint256 actual) public {
        maxCost_ = bound(maxCost_, 0, type(uint256).max - 2);
        actual = bound(actual, 0, maxCost_);
        amount_ = bound(amount_, maxCost_ + 1, type(uint256).max - 1);

        amount = amount_;

        vm.deal(address(magic), amount);
        magic.validatePaymasterUserOp(_getUserOp(), userOpHash, maxCost_);

        vm.stopPrank();
        vm.prank(withdrawer);
        magic.withdrawGasExcess();

        assertEq(withdrawer.balance, (amount - maxCost_));
    }

    function test_RevertsIfNoExcess(uint256 maxCost_) public {
        maxCost_ = bound(maxCost_, 0, type(uint256).max - 1);
        amount = maxCost_;

        vm.deal(address(magic), amount);
        magic.validatePaymasterUserOp(_getUserOp(), userOpHash, maxCost_);

        vm.stopPrank();
        vm.prank(withdrawer);
        vm.expectRevert(MagicSpend.NoExcess.selector);
        magic.withdrawGasExcess();
    }
}
