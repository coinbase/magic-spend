// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21;

import {MagicSpend} from "../../../src/MagicSpend.sol";

import {ActorLib} from "./ActorLib.sol";

import {Vm} from "forge-std/Vm.sol";

struct WithdrawRequestLibStruct {
    uint256 nonce;
}

library WithdrawRequestLib {
    // Cheat code address, 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D.
    address private constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm private constant vm = Vm(VM_ADDRESS);

    bytes32 private constant WITHDRAW_REQUEST_LIB_STORAGE_POSITION = keccak256("withdraw-request-lib.storage");

    function buildWithdrawRequest(uint256 amount, uint48 expiry) internal returns (MagicSpend.WithdrawRequest memory) {
        return MagicSpend.WithdrawRequest({
            asset: address(0),
            amount: amount,
            nonce: _s().nonce++,
            expiry: expiry,
            signature: ""
        });
    }

    function sign(MagicSpend.WithdrawRequest memory withdrawRequest, MagicSpend magicSpend, address account)
        internal
        view
        returns (MagicSpend.WithdrawRequest memory)
    {
        bytes32 hash = magicSpend.getHash(account, withdrawRequest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ActorLib.owner().key, hash);
        withdrawRequest.signature = abi.encodePacked(r, s, v);

        return withdrawRequest;
    }

    function _s() private pure returns (WithdrawRequestLibStruct storage storageStruct) {
        bytes32 position = WITHDRAW_REQUEST_LIB_STORAGE_POSITION;
        assembly {
            storageStruct.slot := position
        }
    }
}
