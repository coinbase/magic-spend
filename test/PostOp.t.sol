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
        vm.deal(address(magic), amount);
        (bytes memory context,) = magic.validatePaymasterUserOp(_getUserOp(), userOpHash, maxCost_);
        uint256 expectedBalance = amount - actualCost;
        magic.postOp(IPaymaster.PostOpMode(mode), context, actualCost);
        assertEq(withdrawer.balance, expectedBalance);
    }

    function test_RevertsIfPostOpFailed(uint256 amount_, uint256 maxCost_, uint256 actualCost) public {
        maxCost_ = bound(maxCost_, 0, amount_);
        actualCost = bound(actualCost, 0, maxCost_);
        amount = amount_;

        assertEq(withdrawer.balance, 0);
        vm.deal(address(magic), amount);
        (bytes memory context,) = magic.validatePaymasterUserOp(_getUserOp(), userOpHash, maxCost_);
        uint256 expectedBalance = 0;
        vm.expectRevert();
        magic.postOp(IPaymaster.PostOpMode.postOpReverted, context, actualCost);
        assertEq(withdrawer.balance, expectedBalance);
    }
}
