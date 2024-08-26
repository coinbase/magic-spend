// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21;

import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";
import {Test, console2} from "forge-std/Test.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import "../src/MagicSpend.sol";

contract MagicSpendTest is Test {
    address withdrawer = address(0xb0b);
    uint256 ownerPrivateKey = 0xa11ce;
    address owner = vm.addr(ownerPrivateKey);
    MagicSpend magic = new MagicSpend(owner, 1);

    // signature params
    address asset;
    uint256 amount = 1e18;
    uint256 nonce;
    uint48 expiry = uint48(block.timestamp + 1);

    function setUp() public virtual {
        vm.deal(address(magic), 1e30);
    }

    function _getRequest() internal view returns (MagicSpend.WithdrawRequest memory request) {
        return MagicSpend.WithdrawRequest({
            asset: asset,
            amount: amount,
            nonce: nonce,
            expiry: expiry,
            signature: _getSignature()
        });
    }

    function _getSignature() internal view returns (bytes memory signature) {
        bytes memory message = abi.encode(address(magic), withdrawer, block.chainid, asset, amount, nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, _toPrefixedMessageHash(message));
        signature = abi.encodePacked(r, s, v);
    }

    function _toPrefixedMessageHash(bytes memory message) internal pure returns (bytes32) {
        return SignatureCheckerLib.toEthSignedMessageHash(message);
    }
}
