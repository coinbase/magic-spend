// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21;

import {Test, console} from "forge-std/Test.sol";

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {IAccount} from "account-abstraction/interfaces/IAccount.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";
import {UserOperation} from "account-abstraction/interfaces/UserOperation.sol";

import {MagicSpend} from "../../src/MagicSpend.sol";

import {ActorLib} from "./libs/ActorLib.sol";
import {WithdrawRequestLib} from "./libs/WithdrawRequestLib.sol";
import {UserOpLib} from "./libs/UserOpLib.sol";
import {EntryPointCheatLib} from "./libs/EntryPointCheatLib.sol";
import {MagisSpendCheatLib} from "./libs/MagisSpendCheatLib.sol";

contract Handler is Test {
    using WithdrawRequestLib for MagicSpend.WithdrawRequest;
    using UserOpLib for UserOperation;

    MagicSpend public immutable ms;
    EntryPoint public immutable ep;

    uint256 public depositedAmount;
    uint256 public withdrawnAmount;

    constructor() {
        ActorLib.init();

        ms = new MagicSpend({owner_: ActorLib.owner().addr, maxWithdrawDenominator_: 20});
        bytes memory code = vm.getDeployedCode("EntryPoint.sol");

        address epAddr = ms.entryPoint();
        vm.etch(epAddr, code);
        ep = EntryPoint(payable(epAddr));
    }

    /// @dev Wrapper arround the MagicSpend `receive()` method.
    /// @dev Ghost variables:
    ///         - `depositedAmount` is increased `value`
    function receive_(uint256 value, uint256 actorIndex) public {
        // Setup test context.
        address actor;
        {
            // value = [0; min(type(uint64).max, min(depositLimit, balanceLimit))]
            uint256 depositLimit = type(uint256).max - depositedAmount;
            uint256 balanceLimit = type(uint256).max - address(ms).balance;
            uint256 limit = balanceLimit < depositLimit ? balanceLimit : depositLimit;
            limit = limit < type(uint64).max ? limit : type(uint64).max;

            value = uint64(bound(value, 0, limit));

            actor = ActorLib.randomActor(actorIndex);
            vm.deal(actor, value);
        }

        // Trigger and assert.
        vm.prank(actor);
        (bool success,) = address(ms).call{value: value}("");
        assertTrue(success);

        // Update ghost variables.
        depositedAmount += value;
    }

    /// @dev Wrapper arround the MagicSpend `withdrawGasExcess()` method.
    /// @dev Ghost variables:
    ///         - `withdrawnAmount` is increased by the withdrawn amount
    function withdrawGasExcess(uint256 actorIndex) public {
        // Setup test context.
        address actor;
        {
            actor = ActorLib.randomActor(actorIndex);
        }

        uint256 withdrawableETHBefore =
            MagisSpendCheatLib.loadWithdrawableETH({magicSpend: address(ms), account: actor});

        // Trigger and assert.
        if (withdrawableETHBefore == 0) {
            vm.expectRevert(MagicSpend.NoExcess.selector);
        }

        vm.prank(actor);
        ms.withdrawGasExcess();

        uint256 withdrawableETHAfter = MagisSpendCheatLib.loadWithdrawableETH({magicSpend: address(ms), account: actor});
        assertEq(withdrawableETHAfter, 0);

        // Update ghost variables.
        withdrawnAmount += withdrawableETHBefore;
    }

    /// @dev Wrapper arround the MagicSpend `withdraw()` method.
    /// @dev Ghost variables:
    ///         - `withdrawnAmount` is increased by `amount`
    function withdraw(uint256 amount, uint256 expiry, uint256 actorIndex) public {
        // Setup test context.
        address actor;
        {
            uint256 maxWithdrawAmount = address(ms).balance / ms.maxWithdrawDenominator();
            amount = bound(amount, 0, maxWithdrawAmount);
            expiry = bound(expiry, block.timestamp + 1, block.timestamp + 1 days);
            actor = ActorLib.randomActor(actorIndex);
        }

        MagicSpend.WithdrawRequest memory withdrawRequest = WithdrawRequestLib.buildWithdrawRequest({
            amount: amount,
            expiry: uint48(expiry)
        }).sign({magicSpend: ms, account: actor});

        // Trigger and assert.
        vm.prank(actor);
        ms.withdraw(withdrawRequest);

        // Update ghost variables.
        withdrawnAmount += amount;
    }

    /// @dev Wrapper arround the MagicSpend `ownerWithdraw()` method.
    /// @dev Ghost variables:
    ///         - `withdrawnAmount` is increased by `amount`
    function ownerWithdraw(uint256 amount) public {
        // Setup test context.
        address owner;
        {
            amount = bound(amount, 0, address(ms).balance);
            owner = ActorLib.owner().addr;
        }

        uint256 ownerBalanceBefore = owner.balance;

        // Trigger and assert.
        vm.prank(owner);
        ms.ownerWithdraw({asset: address(0), to: owner, amount: amount});

        uint256 ownerBalanceAfter = owner.balance;
        assertEq(ownerBalanceAfter, ownerBalanceBefore + amount);

        // Update ghost variables.
        withdrawnAmount += amount;
    }

    /// @dev Wrapper arround the Entrypoint `handleOps()` method.
    function handleOps(uint256 actorIndex, uint256 amount, uint256 expiry) public {
        // Setup test context.
        address bundler;
        address account;
        {
            bundler = ActorLib.bundler();
            account = ActorLib.randomActor(actorIndex);
            expiry = bound(expiry, block.timestamp + 1, block.timestamp + 1 days);
            amount = bound(amount, 0, address(ms).balance / ms.maxWithdrawDenominator());

            vm.mockCall(account, abi.encodeWithSelector(IAccount.validateUserOp.selector), abi.encode(0));
            EntryPointCheatLib.storePaymasterDeposit({
                entryPoint: address(ep),
                paymaster: address(ms),
                deposit: type(uint112).max
            });
        }

        MagicSpend.WithdrawRequest memory withdrawRequest = WithdrawRequestLib.buildWithdrawRequest({
            amount: amount,
            expiry: uint48(expiry)
        }).sign({magicSpend: ms, account: account});

        UserOperation[] memory userOps = new UserOperation[](1);
        UserOperation memory userOp =
            UserOpLib.defaultUserOp(account).withPaymaster({paymaster: address(ms), data: abi.encode(withdrawRequest)});
        userOps[0] = userOp;

        // TODO: Handle revert possibilities or control inputs so that revert is not possible here.
        //       i.e `FailedOp` due to MagicSpend reverting with `RequestLessThanGasMaxCost`.

        // Trigger and assert.
        vm.prank(bundler);
        ep.handleOps({ops: userOps, beneficiary: payable(bundler)});
    }
}

contract MagicSpendInvariant is Test {
    Handler private _handler;

    function setUp() public {
        _handler = new Handler();

        uint256 i;
        bytes4[] memory msSelectors = new bytes4[](5);
        msSelectors[i++] = Handler.receive_.selector;
        msSelectors[i++] = Handler.withdrawGasExcess.selector;
        msSelectors[i++] = Handler.withdraw.selector;
        msSelectors[i++] = Handler.ownerWithdraw.selector;
        msSelectors[i++] = Handler.handleOps.selector;

        targetContract(address(_handler));
        targetSelector(FuzzSelector({addr: address(_handler), selectors: msSelectors}));
    }

    /// forge-config: default.invariant.runs = 100
    /// forge-config: default.invariant.depth = 100
    function invariant_BalanceIsDepositsMinusWithdrawals() public {
        uint256 withdrawnAmount = _handler.withdrawnAmount();
        uint256 depositedAmount = _handler.depositedAmount();
        uint256 balance = address(_handler.ms()).balance;

        assertEq(balance, depositedAmount - withdrawnAmount);
    }
}
