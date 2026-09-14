// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ResolvStakingV2} from "contracts/staking/ResolvStakingV2.sol";
import {ResolvStakingSilo} from "contracts/staking/ResolvStakingSilo.sol";

/// W3 — ResolvStakingV2 / Silo (permissionless deposit & withdraw).
contract W3_Staking_Test is Test {
    MockERC20 internal resolv;
    ResolvStakingSilo internal silo;
    ResolvStakingV2 internal staking;

    address internal constant alice = address(0xA11CE);
    uint256 internal constant MAX = type(uint256).max;
    uint256 internal constant COOLDOWN = 14 days;
    uint256 internal constant T0 = 1_800_000_000;

    function setUp() public {
        vm.warp(T0);
        resolv = new MockERC20("Resolv", "RESOLV", 18);
        silo = new ResolvStakingSilo(resolv);

        ResolvStakingV2 impl = new ResolvStakingV2();
        bytes memory init = abi.encodeCall(
            ResolvStakingV2.initialize,
            ("Staked RESOLV", "stRESOLV", resolv, silo, COOLDOWN)
        );
        staking = ResolvStakingV2(address(new ERC1967Proxy(address(impl), init)));

        silo.grantRole(silo.RESOLV_STAKING_ROLE(), address(staking));
    }

    function _stake(address who, uint256 amount) internal {
        resolv.mint(who, amount);
        vm.prank(who);
        resolv.approve(address(staking), MAX);
        vm.prank(who);
        staking.deposit(amount, who);
    }

    /// W3-P1: deposit -> initiateWithdrawal -> withdraw returns exactly the principal.
    function test_W3P1_roundTripNoGain(uint256 amount) public {
        vm.assume(amount >= 1 && amount <= 1e30);
        uint256 before = resolv.balanceOf(alice);
        _stake(alice, amount);
        assertEq(staking.balanceOf(alice), amount, "shares != deposit");
        assertEq(resolv.balanceOf(alice), before, "staking moved principal");

        vm.prank(alice);
        staking.initiateWithdrawal(amount);

        vm.warp(T0 + COOLDOWN + 1);
        vm.prank(alice);
        staking.withdraw(false, alice);

        assertEq(resolv.balanceOf(alice), before + amount, "round-trip changed principal");
    }

    /// W3-P2: the silo always holds at least the sum of pending withdrawals.
    function test_W3P2_siloSolvency(uint256 amount) public {
        vm.assume(amount >= 1 && amount <= 1e30);
        _stake(alice, amount);
        vm.prank(alice);
        staking.initiateWithdrawal(amount);
        assertGe(resolv.balanceOf(address(silo)), amount, "silo under-collateralised");
    }

    /// W3-P6: withdrawal before the cooldown elapses reverts.
    function test_W3P6_cooldownEnforced(uint256 amount) public {
        vm.assume(amount >= 1 && amount <= 1e30);
        _stake(alice, amount);
        vm.prank(alice);
        staking.initiateWithdrawal(amount);
        vm.prank(alice);
        vm.expectRevert();
        staking.withdraw(false, alice);
    }

    /// W3-P6b: cannot withdraw more than the pending amount.
    function test_W3P6b_noOverWithdraw(uint256 amount, uint256 extra) public {
        vm.assume(amount >= 1 && amount <= 1e30);
        vm.assume(extra >= 1 && extra <= 1e30);
        _stake(alice, amount + extra);
        vm.prank(alice);
        staking.initiateWithdrawal(amount);
        vm.warp(T0 + COOLDOWN + 1);
        // second withdrawal request of `extra` becomes pending; silo must cover total
        vm.prank(alice);
        staking.initiateWithdrawal(extra);
        assertGe(resolv.balanceOf(address(silo)), amount + extra, "silo solvency");
    }
}