// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21;

import {MagicSpendTest} from "./MagicSpend.t.sol";
import {MagicSpend} from "../src/MagicSpend.sol";
import {MockERC20} from "solady/../test/utils/mocks/MockERC20.sol";
import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";

contract GetHashTest is MagicSpendTest {
    MockERC20 token = new MockERC20("test", "TEST", 18);

    function test_returnsValidHash() public {
        asset = address(token);
        MagicSpend.WithdrawRequest memory request = _getRequest();
        bytes32 expectedHash = SignatureCheckerLib.toEthSignedMessageHash(
            abi.encode(
                address(magic), withdrawer, block.chainid, address(token), request.amount, request.nonce, request.expiry
            )
        );
        bytes32 testHash = magic.getHash(withdrawer, request);
        assertEq(testHash, expectedHash);
    }
}
