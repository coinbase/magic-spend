// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21;

import "./MagicSpend.t.sol";
import "./Validate.t.sol";
import {MockERC20} from "solady/../test/utils/mocks/MockERC20.sol";

contract WithdrawTest is MagicSpendTest, ValidateTest {
    MockERC20 token = new MockERC20("test", "TEST", 18);

    function setUp() public override {
        super.setUp();
        vm.startPrank(withdrawer);
        invoker = withdrawer;
    }

    function test_transfersETHSuccessfully(uint256 amount_) public {
        amount = amount_;
        vm.deal(address(magic), amount);
        assertEq(withdrawer.balance, 0);
        magic.withdraw(_getRequest());
        assertEq(withdrawer.balance, amount);
    }

    function test_transfersERC20Successfully(uint256 amount_) public {
        amount = amount_;
        token.mint(address(magic), amount);
        asset = address(token);
        assertEq(token.balanceOf(withdrawer), 0);
        vm.expectEmit(true, true, true, true);
        emit MagicSpend.MagicSpendWithdrawal(withdrawer, asset, amount, nonce);
        magic.withdraw(_getRequest());
        assertEq(token.balanceOf(withdrawer), amount);
    }

    function test_emitsCorrectlyERC20Withdraw(address withdrawer_, uint256 amount_, uint256 nonce_) public virtual {
        token.mint(address(magic), amount_);
        asset = address(token);
        withdrawer = withdrawer_;
        amount = amount_;
        nonce = nonce_;
        vm.expectEmit(true, true, true, true);
        emit MagicSpend.MagicSpendWithdrawal(withdrawer, address(token), amount, nonce);
        vm.stopPrank();
        vm.startPrank(withdrawer);
        _validateInvokingCall();
    }

    function test_revertsIfWrongSignature() public {
        ownerPrivateKey = ownerPrivateKey + 1;

        vm.expectRevert(MagicSpend.InvalidSignature.selector);
        magic.withdraw(_getRequest());
    }

    function test_revertsIfExpired(uint48 expiry_, uint256 timestamp) public {
        vm.warp(timestamp);
        vm.assume(expiry_ < timestamp);
        expiry = expiry_;
        vm.expectRevert(MagicSpend.Expired.selector);
        _validateInvokingCall();
    }

    function _validateInvokingCall() internal override {
        magic.withdraw(_getRequest());
    }
}
