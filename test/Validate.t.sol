// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21;

import {Test, console2} from "forge-std/Test.sol";

import "./MagicSpend.t.sol";

abstract contract ValidateTest is MagicSpendTest {
    function test_recordsNonceUsed(uint256 nonce_) public {
        nonce = nonce_;
        assertFalse(magic.nonceUsed(withdrawer, nonce));
        _validateInvokingCall();
        assertTrue(magic.nonceUsed(withdrawer, nonce));
    }

    function test_emitsCorrectly(address withdrawer_, uint256 amount_, uint256 nonce_) public virtual {
        vm.assume(withdrawer_.code.length == 0);
        // avoid precompiles
        vm.assume(withdrawer_ > address(0x10000));
        vm.assume(withdrawer_ != address(vm));
        asset = address(0);
        withdrawer = withdrawer_;
        amount = amount_;
        nonce = nonce_;
        vm.deal(address(magic), amount);
        vm.expectEmit(true, true, true, true);
        emit MagicSpend.MagicSpendWithdrawal(withdrawer, asset, amount, nonce);
        vm.stopPrank();
        vm.startPrank(withdrawer);
        _validateInvokingCall();
    }

    function test_revertsIfNonceUsed() public {
        _validateInvokingCall();
        vm.expectRevert(abi.encodeWithSelector(MagicSpend.InvalidNonce.selector, nonce));
        _validateInvokingCall();
    }

    function _validateInvokingCall() internal virtual;
}
