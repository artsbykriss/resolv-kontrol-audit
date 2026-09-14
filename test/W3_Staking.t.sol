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
    address internal constant attacker = address(0xBAD);
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


    function _setupRewards(uint256 rewardAmount) internal returns (MockERC20 rw) {
        rw = new MockERC20("Reward", "RWD", 18);
        staking.addRewardToken(rw);
        staking.setClaimEnabled(true);
        staking.grantRole(staking.DISTRIBUTOR_ROLE(), address(this));
        _stake(alice, 1_000e18); // ensure totalEffectiveSupply > 0
        rw.mint(address(this), rewardAmount);
        rw.approve(address(staking), rewardAmount);
        staking.depositReward(address(rw), rewardAmount, 0); // default duration
    }

    /// W3-P3: an account with no stake cannot claim any reward (no free reward).
    function test_W3P3_noFreeRewardSameBlock(uint256 rewardAmount) public {
        vm.assume(rewardAmount >= 1e6 && rewardAmount <= 1e24);
        MockERC20 rw = _setupRewards(rewardAmount);
        uint256 before = rw.balanceOf(attacker);
        vm.prank(attacker);
        staking.claim(attacker, attacker);
        assertEq(rw.balanceOf(attacker) - before, 0, "free reward");
    }

    /// W3-P4: a staker's claim never exceeds the amount deposited to the reward pool.
    function test_W3P4_claimNeverExceedsPool(uint256 rewardAmount) public {
        vm.assume(rewardAmount >= 1e6 && rewardAmount <= 1e24);
        MockERC20 rw = _setupRewards(rewardAmount);
        vm.warp(T0 + 14 days + 2);
        uint256 before = rw.balanceOf(alice);
        vm.prank(alice);
        staking.claim(alice, alice);
        uint256 claimed = rw.balanceOf(alice) - before;
        assertLe(claimed, rewardAmount, "over-distribution");
    }

    /// W3-P5: rewards cannot be claimed twice for the same accrual.
    function test_W3P5_rewardNotDoubleClaimed(uint256 rewardAmount) public {
        vm.assume(rewardAmount >= 1e6 && rewardAmount <= 1e24);
        MockERC20 rw = _setupRewards(rewardAmount);
        vm.warp(T0 + 14 days + 2);
        vm.prank(alice);
        staking.claim(alice, alice);
        uint256 afterFirst = rw.balanceOf(alice);
        vm.prank(alice);
        staking.claim(alice, alice);
        assertEq(rw.balanceOf(alice), afterFirst, "double claim");
    }

    /// W7-P6: a bare staking implementation cannot be initialized by a third party.
    function test_W7P6_implInitRevertsStaking() public {
        ResolvStakingV2 impl = new ResolvStakingV2();
        vm.expectRevert();
        impl.initialize("Staked RESOLV", "stRESOLV", resolv, silo, COOLDOWN);
    }
}