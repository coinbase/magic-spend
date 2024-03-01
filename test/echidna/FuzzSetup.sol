// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FuzzBase} from "fuzzlib/FuzzBase.sol";
import {IHevm} from "fuzzlib/IHevm.sol";

import {MagicSpend} from "../../src/MagicSpend.sol";

contract FuzzSetup is FuzzBase {
    IHevm internal vm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    /// @dev Owner private key of the `MagicSpend` (sut) contract.
    uint256 internal constant OWNER_SK = 0xa11ce;

    /// @dev Owner address of the `MagicSpend` (sut) contract.
    address internal OWNER = vm.addr(OWNER_SK);

    /// @dev Withdrawer address issuing the withdraw requests.
    address internal constant WITHDRAWER = address(0xb0b);

    /// @dev Constant used to clamp the withdraw request amounts.
    uint256 internal constant PAYMASTER_MAX_BALANCE = 1_000_000e18;

    /// @dev System under test.
    MagicSpend internal sut;

    /// @dev Tracks the nonce value per withdrawer address.
    mapping(address withdrawer => uint256 nonce) internal nonces;

    /// @dev Tracks the total ETH amount deposited on the `MagicSpend` (sut) contract.
    /// @dev Is incremented at each deposit (see `Fuzz.depositPaymasterBalance()`)
    uint256 internal totalDeposited;

    /// @dev Tracks the total ETH amount withdrawn from the `MagicSpend` (sut) contract.
    /// @dev Is incremented at each withdrawal (see `Fuzz.withdraw()`)
    uint256 internal totalWithdrawn;

    constructor() payable {
        sut = new MagicSpend(OWNER);
    }
}
