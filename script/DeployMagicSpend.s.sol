// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {MagicSpend} from "../src/MagicSpend.sol";

contract MagicSpendDeployScript is Script {
    function setUp() public {}

    function run() public {
        address signerAddress = 0x3E0cd4Dc43811888efa242Ab17118FcE0035EFF7;
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        MagicSpend c = new MagicSpend{salt: "0x1"}(vm.addr(deployerPrivateKey), 20);
        console2.log(address(c));
        c.entryPointDeposit{value: 0.01 ether}(0.01 ether);
        c.entryPointAddStake{value: 0x16345785d8a0000}(0x16345785d8a0000, 0x15180);
        c.transferOwnership(signerAddress);
    }
}
