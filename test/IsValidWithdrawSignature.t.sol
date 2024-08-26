// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21;

import "./MagicSpend.t.sol";
import {MockERC20} from "solady/../test/utils/mocks/MockERC20.sol";

contract IsValidWithdrawalSignature is MagicSpendTest {
    MockERC20 token = new MockERC20("test", "TEST", 18);

    function test_returnsTrueWithValidSignature() public {
        asset = address(token);
        MagicSpend.WithdrawRequest memory request = _getRequest();
        bool success = magic.isValidWithdrawSignature(withdrawer, request);
        assert(success);
    }

    function test_returnsFalseWithInvalidSignature() public {
        asset = address(token);
        address invalidSender = address(0xdead);
        MagicSpend.WithdrawRequest memory request = _getRequest();
        bool success = magic.isValidWithdrawSignature(invalidSender, request);
        assertFalse(success);
    }
}
