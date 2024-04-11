// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21;

import {Vm} from "forge-std/Vm.sol";

import {MagicSpend} from "../../../src/MagicSpend.sol";

library EntryPointCheatLib {
    // Cheat code address, 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D.
    address private constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm private constant vm = Vm(VM_ADDRESS);

    function storePaymasterDeposit(address entryPoint, address paymaster, uint112 deposit) internal {
        bytes32 baseSlot = bytes32(uint256(0));
        bytes32 mappingSlot = keccak256(abi.encode(paymaster, baseSlot));

        uint256 slot0Value = uint256(vm.load(entryPoint, mappingSlot));
        slot0Value = (slot0Value >> 112 << 112) | deposit;

        vm.store(entryPoint, mappingSlot, bytes32(slot0Value));
    }
}
