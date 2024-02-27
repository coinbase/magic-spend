// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {CoinbaseSmartWalletFactory, CoinbaseSmartWallet} from "smart-wallet/src/CoinbaseSmartWalletFactory.sol";
import "./PaymasterMagicSpendBase.sol";
import "./Static.sol";

contract PostOpTest is PaymasterMagicSpendBaseTest {
    IEntryPoint entryPoint = IEntryPoint(0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789);
    CoinbaseSmartWalletFactory factory = new CoinbaseSmartWalletFactory(address(new CoinbaseSmartWallet()));
    uint256 accountOwnerPk = 0xa11ce2;
    address accountOwner = vm.addr(accountOwnerPk);
    uint256 preBalance = 1e18;

    function setUp() public override {
        super.setUp();
        vm.etch(address(entryPoint), Static.ENTRY_POINT_BYTES);
        vm.deal(address(magic), preBalance * 2);
        vm.prank(address(magic));
        (bool success,) = address(entryPoint).call{value: preBalance}("");
        assert(success);

        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(accountOwner);
        withdrawer = address(factory.createAccount(owners, 0));
    }

    function test_paymasterPaysForOp() public {
        UserOperation memory op = _getUserOp();
        bytes32 hash = entryPoint.getUserOpHash(op);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(accountOwnerPk, hash);
        bytes memory userOpSig =
            abi.encode(CoinbaseSmartWallet.SignatureWrapper({ownerIndex: 0, signatureData: abi.encodePacked(r, s, v)}));
        op.signature = userOpSig;
        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = op;

        assertEq(op.sender.balance, 0);
        entryPoint.handleOps(ops, payable(address(1)));
    }

    function test_entryPointDeposit(uint112 amount) public {
        vm.assume(amount < type(uint112).max - preBalance);
        vm.deal(address(magic), amount);
        vm.prank(owner);
        magic.entryPointDeposit(amount);
        assertEq(entryPoint.balanceOf(address(magic)), preBalance + amount);
    }

    function test_entryPointWithdraw(uint112 amount) public {
        address to = address(0x00e);
        vm.assume(amount < type(uint112).max - preBalance);
        vm.deal(address(magic), amount);
        vm.startPrank(owner);
        magic.entryPointDeposit(amount);
        magic.entryPointWithdraw(payable(to), amount);
        assertEq(to.balance, amount);
    }

    function test_entryPointAddStake(uint112 amount, uint32 duration) public {
        vm.assume(amount > 0);
        vm.assume(duration > 0);
        vm.deal(address(magic), amount);
        vm.startPrank(owner);
        magic.entryPointAddStake(amount, uint32(duration));
        assertEq(entryPoint.getDepositInfo(address(magic)).stake, amount);
    }

    function test_entryPointUnlockStake() public {
        uint256 amount = 118;
        uint32 duration = 1e6;
        vm.deal(address(magic), amount);
        vm.startPrank(owner);
        magic.entryPointAddStake(amount, uint32(duration));
        magic.entryPointUnlockStake();
    }

    function test_entryPointWithdrawStake() public {
        address to = payable(address(0x00e));
        uint256 amount = 118;
        uint32 duration = 1e6;
        vm.deal(address(magic), amount);
        vm.startPrank(owner);
        magic.entryPointAddStake(amount, uint32(duration));
        magic.entryPointUnlockStake();
        vm.warp(block.timestamp + duration);
        magic.entryPointWithdrawStake(payable(to));
        assertEq(to.balance, amount);
    }
}
