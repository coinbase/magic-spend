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
        amount_ = bound(amount_, 0, type(uint256).max - 1);
        maxCost_ = bound(maxCost_, 0, amount_);
        actualCost = bound(actualCost, 0, maxCost_);

        maxCost = maxCost_;
        amount = amount_;

        assertEq(withdrawer.balance, 0);
        vm.deal(address(magic), amount);
        (bytes memory context,) = magic.validatePaymasterUserOp(_getUserOp(), userOpHash, maxCost_);

        magic.postOp(IPaymaster.PostOpMode(mode), context, actualCost);

        uint256 expectedBalance = amount - actualCost;
        assertEq(withdrawer.balance, expectedBalance);
    }

    function test_RevertsIfPostOpFailed(uint256 amount_, uint256 maxCost_, uint256 actualCost) public {
        amount_ = bound(amount_, 0, type(uint256).max - 1);
        maxCost_ = bound(maxCost_, 0, amount_);
        actualCost = bound(actualCost, 0, maxCost_);

        amount = amount_;

        assertEq(withdrawer.balance, 0);
        vm.deal(address(magic), amount);

        (bytes memory context,) = magic.validatePaymasterUserOp(_getUserOp(), userOpHash, maxCost_);

        vm.expectRevert(MagicSpend.UnexpectedPostOpRevertedMode.selector);
        magic.postOp(IPaymaster.PostOpMode.postOpReverted, context, actualCost);

        uint256 expectedBalance = 0;
        assertEq(withdrawer.balance, expectedBalance);
    }
}
