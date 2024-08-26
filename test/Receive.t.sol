// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21;

import {MockERC20} from "solady/../test/utils/mocks/MockERC20.sol";

import "./MagicSpend.t.sol";

contract ValidateTest is MagicSpendTest {
    function test_receive() public {
        vm.deal(address(this), 1e18);
        (bool success,) = address(magic).call{value: 1e18}("");
        assertTrue(success);
    }
}
