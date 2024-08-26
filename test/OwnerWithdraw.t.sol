// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21;

import {Ownable} from "./MagicSpend.t.sol";
import {MagicSpendTest} from "./MagicSpend.t.sol";
import {MockERC20} from "solady/../test/utils/mocks/MockERC20.sol";

contract OwnerWithdrawTest is MagicSpendTest {
    MockERC20 token = new MockERC20("test", "TEST", 18);

    function test_revertsIfNotOwner() public {
        vm.startPrank(withdrawer);
        vm.expectRevert(Ownable.Unauthorized.selector);
        magic.ownerWithdraw(address(token), withdrawer, 1);
    }

    function test_transfersERC20Successfully(uint256 amount_) public {
        vm.startPrank(owner);
        amount = amount_;
        token.mint(address(magic), amount);
        asset = address(token);
        assertEq(token.balanceOf(owner), 0);
        magic.ownerWithdraw(asset, owner, amount);
        assertEq(token.balanceOf(owner), amount);
    }

    function test_transfersETHSuccessfully(uint256 amount_) public {
        vm.deal(address(magic), amount_);
        vm.startPrank(owner);
        amount = amount_;
        asset = address(0);
        assertEq(owner.balance, 0);
        magic.ownerWithdraw(asset, owner, amount);
        assertEq(owner.balance, amount);
    }
}
