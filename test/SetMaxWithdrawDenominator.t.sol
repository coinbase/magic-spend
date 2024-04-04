// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./MagicSpend.t.sol";
import {Ownable} from "./MagicSpend.t.sol";

contract SetMaxWithdrawDenominator is MagicSpendTest {
    function test_reverts_whenNotCalledByOwner() public {
        vm.prank(makeAddr("fake"));
        vm.expectRevert(Ownable.Unauthorized.selector);
        magic.setMaxWithdrawDenominator(20);
    }

    function test_setsMaxWithdrawPercent(uint256 newDenominator) public {
        vm.prank(owner);
        magic.setMaxWithdrawDenominator(newDenominator);
        assertEq(magic.maxWithdrawDenominator(), newDenominator);
    }

    function test_emitsCorrectly(uint256 newDenominator) public {
        vm.expectEmit(false, false, false, true);
        emit MagicSpend.MaxWithdrawDenominatorSet(newDenominator);
        vm.prank(owner);
        magic.setMaxWithdrawDenominator(newDenominator);
    }
}
