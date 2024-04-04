// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./MagicSpend.t.sol";
import {Ownable} from "./MagicSpend.t.sol";

contract SetMaxWithdrawPercent is MagicSpendTest {
    function test_reverts_whenNotCalledByOwner() public {
        vm.prank(makeAddr("fake"));
        vm.expectRevert(Ownable.Unauthorized.selector);
        magic.setMaxWithdrawPercent(20);
    }

    function test_setsMaxWithdrawPercent(uint256 newPercent) public {
        vm.prank(owner);
        magic.setMaxWithdrawPercent(newPercent);
        assertEq(magic.maxWithdrawPercent(), newPercent);
    }

    function test_emitsCorrectly(uint256 newPercent) public {
        vm.expectEmit(false, false, false, true);
        emit MagicSpend.MaxWithdrawPercentSet(newPercent);
        vm.prank(owner);
        magic.setMaxWithdrawPercent(newPercent);
    }
}
