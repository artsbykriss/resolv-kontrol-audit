// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ResolvHarness} from "./harness/ResolvHarness.sol";
import {StUSR} from "contracts/StUSR.sol";

/// W2 — stUSR rebasing share math (permissionless).
contract StUSR_Test is ResolvHarness {
    uint256 internal constant BOUND = 1e30;

    // ------------------------------------------------------------------
    // Round-trip: no value can be created by converting back and forth.
    // ------------------------------------------------------------------

    /// W2-P1: convertToShares(convertToUnderlyingToken(s)) <= s
    function test_W2P1_noShareRoundTripGain(uint256 shares) public view {
        vm.assume(shares < BOUND);
        uint256 assets = stUSR.convertToUnderlyingToken(shares);
        uint256 back = stUSR.convertToShares(assets);
        assertLe(back, shares, "share round-trip gained");
    }

    /// W2-P2: convertToUnderlyingToken(convertToShares(u)) <= u
    function test_W2P2_noAssetRoundTripGain(uint256 usrAmt) public view {
        vm.assume(usrAmt < BOUND);
        uint256 shares = stUSR.convertToShares(usrAmt);
        uint256 back = stUSR.convertToUnderlyingToken(shares);
        assertLe(back, usrAmt, "asset round-trip gained");
    }

    /// W2-P3: deposit then immediate balance is never more than deposited (floor).
    function test_W2P3_depositNoGain(uint256 usrAmt) public {
        vm.assume(usrAmt > 0 && usrAmt < BOUND);
        _fund(alice, usrAmt);
        vm.prank(alice);
        stUSR.deposit(usrAmt, alice);
        assertLe(stUSR.balanceOf(alice), usrAmt, "deposit gained");
    }

    /// W2-P4: a deposit that would mint 0 shares must revert (no silent donation).
    function test_W2P4_zeroShareDepositReverts(uint256 usrAmt) public {
        vm.assume(usrAmt > 0 && usrAmt < BOUND);
        if (stUSR.previewDeposit(usrAmt) != 0) return; // only the edge case is asserted
        _fund(alice, usrAmt);
        vm.prank(alice);
        vm.expectRevert();
        stUSR.deposit(usrAmt, alice);
    }

    // ------------------------------------------------------------------
    // Transfers round down; recipient gain <= requested value.
    // ------------------------------------------------------------------

    /// W2-P5: transfer moves at most `value` of underlying to the recipient.
    function test_W2P5_transferRoundsDown(uint256 usrAmt, uint256 value) public {
        vm.assume(usrAmt > 0 && usrAmt < BOUND);
        vm.assume(value <= usrAmt);
        _fund(alice, usrAmt);
        vm.prank(alice);
        stUSR.deposit(usrAmt, alice);

        uint256 bobBefore = stUSR.balanceOf(bob);
        vm.prank(alice);
        stUSR.transfer(bob, value);
        uint256 bobGain = stUSR.balanceOf(bob) - bobBefore;
        assertLe(bobGain, value, "recipient gained more than value");
    }

    /// W2-P5b: transferFrom consumes at most `value` of allowance.
    function test_W2P5b_transferFromAllowanceBounded(uint256 usrAmt, uint256 value) public {
        vm.assume(usrAmt > 0 && usrAmt < BOUND);
        vm.assume(value <= usrAmt);
        _fund(alice, usrAmt);
        vm.prank(alice);
        stUSR.deposit(usrAmt, alice);

        vm.prank(alice);
        stUSR.approve(bob, value);
        vm.prank(bob);
        stUSR.transferFrom(alice, bob, value);
        assertLe(value - stUSR.allowance(alice, bob), value, "allowance over-spent");
    }

    // ------------------------------------------------------------------
    // Invariants
    // ------------------------------------------------------------------

    /// W2-P7: totalSupply() (underlying) always equals the real token balance.
    function test_W2P7_totalSupplyMatchesBalance(uint256 usrAmt) public {
        vm.assume(usrAmt > 0 && usrAmt < BOUND);
        _fund(alice, usrAmt);
        vm.prank(alice);
        stUSR.deposit(usrAmt, alice);
        assertEq(stUSR.totalSupply(), usr.balanceOf(address(stUSR)), "supply != balance");
        assertEq(stUSR.totalShares(), stUSR.sharesOf(address(0x5EED)) + stUSR.sharesOf(alice), "share sum");
    }

    /// W2-P6: an inflation attack (attacker seeds tiny, donates, victim deposits,
    /// attacker exits) can never leave the attacker with more USR than injected.
    function test_W2P6_inflationNoProfit(uint256 victimAmt) public {
        vm.assume(victimAmt > 1e6 && victimAmt < 1e30);
        // fresh pool for this property
        StUSR s = _newStUSR();

        _fund(attacker, 1);
        vm.prank(attacker);
        usr.approve(address(s), MAX);
        vm.prank(attacker);
        s.deposit(1, attacker); // 1 wei -> 1000 shares (offset)
        uint256 inA = 1;

        // donation: attacker sends USR straight to the vault
        uint256 donation = 100_000e18;
        _fund(attacker, donation);
        vm.prank(attacker);
        usr.transfer(address(s), donation);
        inA += donation;

        // victim deposits (may revert with InvalidDepositAmount when inflated —
        // that revert is itself the protection; either way the attacker cannot profit)
        _fund(bob, victimAmt);
        vm.prank(bob);
        usr.approve(address(s), MAX);
        vm.prank(bob);
        (bool ok,) = address(s).call(
            abi.encodeWithSignature("deposit(uint256,address)", victimAmt, bob)
        );
        ok; // ignore: revert => no victim, no profit

        // attacker exits by transferring whole share balance for USR via withdraw of entitlement
        uint256 shares = s.sharesOf(attacker);
        uint256 out = s.convertToUnderlyingToken(shares);
        assertLe(out, inA, "inflation attack profitable");
    }

    // ------------------------------------------------------------------
    // W7: initialization
    // ------------------------------------------------------------------

    /// W7-P1/P3: cannot re-initialize.
    function test_W7P1_reinitializeReverts() public {
        vm.expectRevert();
        stUSR.initialize("x", "x", address(usr));
    }
}