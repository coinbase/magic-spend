// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21;

import {Vm} from "forge-std/Vm.sol";

import {MagicSpend} from "../../../src/MagicSpend.sol";

struct Account {
    address addr;
    uint256 key;
}

struct ActorLibStruct {
    Account magicSpendOwner;
    address[] actors;
    address bundler;
}

library ActorLib {
    // Cheat code address, 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D.
    address private constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm private constant vm = Vm(VM_ADDRESS);

    bytes32 private constant ACTOR_LIB_STORAGE_POSITION = keccak256("actor-lib.storage");

    function init() internal {
        _s().magicSpendOwner = _makeAccount("Owner");

        address[] memory actors = new address[](10);
        for (uint256 i; i < actors.length; i++) {
            actors[i] = _makeAddr(string.concat("Actor_", vm.toString(i)));
        }

        _s().actors = actors;

        _s().bundler = _makeAddr("Bundler");
    }

    function owner() internal view returns (Account memory) {
        return _s().magicSpendOwner;
    }

    function randomActor(uint256 actorIndex) internal view returns (address) {
        return _s().actors[actorIndex % _s().actors.length];
    }

    function bundler() internal view returns (address) {
        return _s().bundler;
    }

    function _makeAddrAndKey(string memory name) private returns (address addr, uint256 privateKey) {
        privateKey = uint256(keccak256(abi.encodePacked(name)));
        addr = vm.addr(privateKey);
        vm.label(addr, name);
    }

    function _makeAddr(string memory name) private returns (address addr) {
        (addr,) = _makeAddrAndKey(name);
    }

    function _makeAccount(string memory name) private returns (Account memory account) {
        (account.addr, account.key) = _makeAddrAndKey(name);
    }

    function _s() private pure returns (ActorLibStruct storage storageStruct) {
        bytes32 position = ACTOR_LIB_STORAGE_POSITION;
        assembly {
            storageStruct.slot := position
        }
    }
}
