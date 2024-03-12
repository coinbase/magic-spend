// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21;

import "./PaymasterMagicSpendBase.sol";

contract PostOpTest is PaymasterMagicSpendBaseTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(magic.entryPoint());
    }

    function test_transfersExcess(uint256 mode, uint256 amount_, uint256 maxCost_, uint256 actualCost) public {
        mode = bound(mode, 0, 1);
        maxCost_ = bound(maxCost_, 0, amount_);
        actualCost = bound(actualCost, 0, maxCost_);
        amount = amount_;
        assertEq(withdrawer.balance, 0);
        (bytes memory context,) = magic.validatePaymasterUserOp(_getUserOp(), userOpHash, maxCost_);
        uint256 expectedBalance = amount - actualCost;
        vm.deal(address(magic), expectedBalance);
        magic.postOp(IPaymaster.PostOpMode(mode), context, actualCost);
        assertEq(withdrawer.balance, expectedBalance);
    }

    function testRevert_PostOp_WhenCalledWithPostOpRevertedMode(uint256 amount_, uint256 maxCost_, uint256 actualCost)
        public
    {
        vm.assume(maxCost_ <= amount_);
        vm.assume(actualCost <= maxCost_);
        amount = amount_;
        assertEq(withdrawer.balance, 0);
        (bytes memory context,) = magic.validatePaymasterUserOp(_getUserOp(), userOpHash, maxCost_);
        uint256 expectedBalance = 0;

        vm.expectRevert(MagicSpend.UnexpectedPostOpRevertedMode.selector);
        magic.postOp(IPaymaster.PostOpMode.postOpReverted, context, actualCost);

        assertEq(withdrawer.balance, expectedBalance);
    }
}
