// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "fuzzlib/FuzzBase.sol";
import "fuzzlib/IHevm.sol";

import {UserOperation} from "account-abstraction/interfaces/UserOperation.sol";
import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";

import {MagicSpend} from "../../src/MagicSpend.sol";

contract FuzzSetup is FuzzBase {
    IHevm internal vm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    uint256 internal constant PAYMASTER_STARTING_BALANCE = 1_000_000e18;
    uint256 internal constant OWNER_PK = 0xa11ce;
    address internal OWNER = vm.addr(OWNER_PK);

    MagicSpend internal magic;

    mapping(address => uint256) internal nonces;
    uint256 totalWithdrawn;

    constructor() payable {
        magic = new MagicSpend(OWNER, 1);
        address(magic).call{value: PAYMASTER_STARTING_BALANCE}("");
    }

    function _getUserOp(address withdrawer, MagicSpend.WithdrawRequest memory request)
        internal
        view
        returns (UserOperation memory userOp)
    {
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
            paymasterAndData: abi.encodePacked(address(magic), abi.encode(request)),
            signature: ""
        });
    }

    function _getWithdrawRequest(address withdrawer, address asset, uint256 amount, uint256 nonce, uint48 expiry)
        internal
        returns (MagicSpend.WithdrawRequest memory)
    {
        return MagicSpend.WithdrawRequest({
            asset: asset,
            amount: amount,
            nonce: nonce,
            expiry: expiry,
            signature: _getSignature(withdrawer, asset, amount, nonce, expiry)
        });
    }

    function _getSignature(address _withdrawer, address _asset, uint256 _amount, uint256 _nonce, uint48 _expiry)
        internal
        returns (bytes memory signature)
    {
        bytes memory message = abi.encode(address(magic), _withdrawer, block.chainid, _asset, _amount, _nonce, _expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PK, _toPrefixedMessageHash(message));
        signature = abi.encodePacked(r, s, v);
    }

    function _toPrefixedMessageHash(bytes memory message) internal pure returns (bytes32) {
        return SignatureCheckerLib.toEthSignedMessageHash(message);
    }
}
