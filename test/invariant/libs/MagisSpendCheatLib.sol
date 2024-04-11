// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21;

import {Vm} from "forge-std/Vm.sol";

import {MagicSpend} from "../../../src/MagicSpend.sol";

library MagisSpendCheatLib {
    // Cheat code address, 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D.
    address private constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm private constant vm = Vm(VM_ADDRESS);

    function loadWithdrawableETH(address magicSpend, address account) internal view returns (uint256) {
        bytes32 baseSlot = bytes32(uint256(1));
        bytes32 mappingSlot = keccak256(abi.encode(account, baseSlot));

        return uint256(vm.load(magicSpend, mappingSlot));
    }
}
