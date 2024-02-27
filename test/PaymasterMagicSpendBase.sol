// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21;

import {UserOperation} from "account-abstraction/interfaces/UserOperation.sol";

import "./MagicSpend.t.sol";

contract PaymasterMagicSpendBaseTest is MagicSpendTest {
    uint256 public maxCost = amount - 10;
    bytes32 public userOpHash = sha256("hi");

    function _getUserOp() internal view returns (UserOperation memory userOp) {
        userOp = UserOperation({
            sender: withdrawer,
            nonce: 0,
            initCode: "",
            callData: "",
            callGasLimit: 49152,
            verificationGasLimit: 378989,
            preVerificationGas: 273196043,
            maxFeePerGas: 1000304,
            maxPriorityFeePerGas: 1000000,
            paymasterAndData: abi.encodePacked(address(magic), abi.encode(_getRequest())),
            signature: ""
        });
    }
}
