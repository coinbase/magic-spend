// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21;

import "./PaymasterMagicSpendBase.sol";

contract BitMapGasSavings is PaymasterMagicSpendBaseTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(magic.entryPoint());
    }

    function test_validate256UserOps() public {
        for (uint256 requestNonce; requestNonce < 256; requestNonce++) {
            nonce = requestNonce;
            magic.validatePaymasterUserOp(_getUserOp(), userOpHash, maxCost);
        }
    }
}
