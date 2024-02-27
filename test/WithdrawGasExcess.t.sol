// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21;

import "./PaymasterMagicSpendBase.sol";

contract WithdrawGasExcess is PaymasterMagicSpendBaseTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(magic.entryPoint());
    }

    function test_transferExcess(uint256 amount_, uint256 maxCost_, uint256 actual) public {
        vm.assume(maxCost_ < amount_);
        vm.assume(actual <= maxCost_);
        amount = amount_;
        vm.deal(address(magic), amount);
        magic.validatePaymasterUserOp(_getUserOp(), userOpHash, maxCost_);

        vm.stopPrank();
        vm.prank(withdrawer);
        magic.withdrawGasExcess();

        assertEq(withdrawer.balance, (amount - maxCost_));
    }

    function test_RevertsIfNoExcess(uint256 maxCost_) public {
        amount = maxCost_;
        vm.deal(address(magic), amount);
        magic.validatePaymasterUserOp(_getUserOp(), userOpHash, maxCost_);

        vm.stopPrank();
        vm.prank(withdrawer);
        vm.expectRevert(MagicSpend.NoExcess.selector);
        magic.withdrawGasExcess();
    }
}
