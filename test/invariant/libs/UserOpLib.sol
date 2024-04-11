// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21;

import {UserOperation} from "account-abstraction/interfaces/UserOperation.sol";

import {MagicSpend} from "../../../src/MagicSpend.sol";

import {ActorLib} from "./ActorLib.sol";

import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

library UserOpLib {
    // Cheat code address, 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D.
    address private constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm private constant vm = Vm(VM_ADDRESS);

    function defaultUserOp(address sender) internal pure returns (UserOperation memory) {
        return UserOperation({
            sender: sender,
            nonce: 0,
            initCode: "",
            callData: "",
            callGasLimit: 1_000_000,
            verificationGasLimit: 1_000_000,
            preVerificationGas: 1_000_000,
            maxFeePerGas: 1_000_000,
            maxPriorityFeePerGas: 1_000_000,
            paymasterAndData: "",
            signature: ""
        });
    }

    function withCallData(UserOperation memory userOp, bytes memory callData)
        internal
        pure
        returns (UserOperation memory)
    {
        userOp.callData = callData;
        return userOp;
    }

    function withPaymaster(UserOperation memory userOp, address paymaster, bytes memory data)
        internal
        pure
        returns (UserOperation memory)
    {
        userOp.paymasterAndData = abi.encodePacked(uint160(paymaster), data);
        return userOp;
    }

    function requiredPrefund(UserOperation memory userOp) internal pure returns (uint256) {
        uint256 mul = userOp.paymasterAndData.length == 0 ? 1 : 3;
        uint256 requiredGas = userOp.callGasLimit + userOp.verificationGasLimit * mul + userOp.preVerificationGas;

        return requiredGas * userOp.maxFeePerGas;
    }

    function _encodePaymasterAndData(address paymaster, bytes memory data)
        private
        returns (bytes memory paymasterAndData)
    {}
}
