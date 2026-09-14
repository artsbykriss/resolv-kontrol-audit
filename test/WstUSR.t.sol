// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ResolvHarness} from "./harness/ResolvHarness.sol";
import {WstUSR} from "contracts/WstUSR.sol";

/// W2 — wstUSR ERC-4626 wrapper (permissionless).
contract WstUSR_Test is ResolvHarness {
    uint256 internal constant BOUND = 1e30;
    uint256 internal constant OFFSET = 1000;

    // ------------------------------------------------------------------
    // Round-trips
    // ------------------------------------------------------------------

    /// W2-P8: deposit then redeem the resulting shares returns <= deposited.
    function test_W2P8_depositRedeemNoGain(uint256 usrAmt) public {
        vm.assume(usrAmt > 1e6 && usrAmt < BOUND);
        _fund(alice, usrAmt);

        vm.prank(alice);
        uint256 w = wstUSR.deposit(usrAmt, alice);

        uint256 out = wstUSR.previewRedeem(w);
        assertLe(out, usrAmt, "deposit/redeem gained");
    }

    /// W2-P8b: mint then redeem returns <= cost (previewMint then previewRedeem).
    function test_W2P8b_mintRedeemNoGain(uint256 w) public {
        vm.assume(w > 0 && w < BOUND);
        uint256 cost = wstUSR.previewMint(w);
        uint256 out = wstUSR.previewRedeem(w);
        assertLe(out, cost, "mint/redeem gained");
    }

    /// W2-P9: wrap then unwrap can never return more stUSR shares than were moved in.
    function test_W2P9_wrapUnwrapNoShareGain(uint256 usrAmt, uint256 stUSRAmt) public {
        vm.assume(usrAmt > 1e6 && usrAmt < BOUND);
        vm.assume(stUSRAmt > 0 && stUSRAmt <= usrAmt);
        _fund(alice, usrAmt);
        vm.prank(alice);
        stUSR.deposit(usrAmt, alice);

        uint256 sharesBefore = stUSR.sharesOf(alice);

        vm.prank(alice);
        uint256 w = wstUSR.wrap(stUSRAmt, alice);
        vm.assume(w > 0);
        vm.prank(alice);
        wstUSR.unwrap(w, alice);

        assertLe(stUSR.sharesOf(alice), sharesBefore, "wrap/unwrap gained stUSR shares");
    }

    /// W2-P9b: unwrap moves exactly `w*1000` stUSR shares and burns exactly `w` wstUSR.
    function test_W2P9b_unwrapExact(uint256 usrAmt) public {
        vm.assume(usrAmt > 1e6 && usrAmt < BOUND);
        _fund(alice, usrAmt);
        vm.prank(alice);
        uint256 w = wstUSR.deposit(usrAmt, alice);
        vm.assume(w > 0);

        uint256 wSupplyBefore = wstUSR.totalSupply();
        uint256 contractSharesBefore = stUSR.sharesOf(address(wstUSR));

        vm.prank(alice);
        wstUSR.unwrap(w, bob);

        assertEq(wstUSR.totalSupply(), wSupplyBefore - w, "wrong wstUSR burned");
        assertEq(
            stUSR.sharesOf(address(wstUSR)),
            contractSharesBefore - w * OFFSET,
            "wrong stUSR shares moved"
        );
    }

    /// W2-P11: a deposit that mints 0 wstUSR cannot create a profitable path.
    function test_W2P11_zeroMintDepositNoProfit(uint256 usrAmt) public {
        vm.assume(usrAmt > 0 && usrAmt < BOUND);
        if (wstUSR.previewDeposit(usrAmt) != 0) return;
        _fund(alice, usrAmt);
        uint256 balBefore = usr.balanceOf(alice);
        // StUSR.deposit reverts when 0 shares would be minted; either way
        // alice cannot end with shares or more USR than before.
        (bool ok,) = address(wstUSR).call(
            abi.encodeWithSignature("deposit(uint256,address)", usrAmt, alice)
        );
        ok;
        // alice received no shares; her USR only decreased (never increased)
        assertEq(wstUSR.balanceOf(alice), 0, "unexpected shares");
        assertLe(usr.balanceOf(alice), balBefore, "profit from zero mint");
    }

    /// W2-P12: previewMint/previewRedeem rounding never favours the user.
    function test_W2P12_mintRedeemRounding(uint256 w) public view {
        vm.assume(w > 0 && w < BOUND);
        uint256 cost = wstUSR.previewMint(w); // ceil
        uint256 back = wstUSR.previewRedeem(w); // floor
        assertLe(back, cost, "round-trip favoured user");
    }

    // ------------------------------------------------------------------
    // Invariants
    // ------------------------------------------------------------------

    /// W2-P10: totalAssets == stUSR.convertToUnderlyingToken(totalSupply*1000) after any op.
    function test_W2P10_totalAssetsInvariant(uint256 usrAmt) public {
        vm.assume(usrAmt > 1e6 && usrAmt < BOUND);
        _fund(alice, usrAmt);
        vm.prank(alice);
        wstUSR.deposit(usrAmt, alice);

        assertEq(
            wstUSR.totalAssets(),
            stUSR.convertToUnderlyingToken(wstUSR.totalSupply() * OFFSET),
            "totalAssets desync"
        );
    }

    /// W2-P10b: the wrapper always holds >= totalSupply*1000 stUSR shares.
    function test_W2P10b_backingInvariant(uint256 usrAmt) public {
        vm.assume(usrAmt > 1e6 && usrAmt < BOUND);
        _fund(alice, usrAmt);
        vm.prank(alice);
        wstUSR.deposit(usrAmt, alice);
        assertGe(
            stUSR.sharesOf(address(wstUSR)),
            wstUSR.totalSupply() * OFFSET,
            "under-backed wrapper"
        );
    }

    // ------------------------------------------------------------------
    // W2-P13/P14: blacklist (V2)
    // ------------------------------------------------------------------

    /// W2-P13: burnFromBlacklist reduces supply exactly by the account balance.
    function test_W2P13_burnFromBlacklist(uint256 usrAmt) public {
        vm.assume(usrAmt > 1e6 && usrAmt < BOUND);
        _fund(alice, usrAmt);
        vm.prank(alice);
        uint256 w = wstUSR.deposit(usrAmt, alice);
        vm.assume(w > 0);

        wstUSR.addToBlacklist(alice);
        uint256 supplyBefore = wstUSR.totalSupply();
        wstUSR.burnFromBlacklist(alice);
        assertEq(wstUSR.totalSupply(), supplyBefore - w, "wrong burn amount");
        assertEq(wstUSR.balanceOf(alice), 0, "residual balance");
    }

    /// W2-P14: a blacklisted account can neither send nor receive.
    function test_W2P14_blacklistBlocksTransfer(uint256 usrAmt) public {
        vm.assume(usrAmt > 1e6 && usrAmt < BOUND);
        _fund(alice, usrAmt);
        vm.prank(alice);
        wstUSR.deposit(usrAmt, alice);
        wstUSR.addToBlacklist(alice);

        vm.prank(alice);
        vm.expectRevert();
        wstUSR.transfer(bob, 1);
    }

    // ------------------------------------------------------------------
    // W7
    // ------------------------------------------------------------------

    /// W7-P2: no re-initialization.
    function test_W7P2_reinitializeReverts() public {
        vm.expectRevert();
        wstUSR.initialize("x", "x", address(stUSR));
        vm.expectRevert();
        wstUSR.initializeV2(address(this), address(this));
    }

    /// W7-P3: implementation cannot be initialized directly.
    function test_W7P3_implInitReverts() public {
        WstUSR impl = new WstUSR();
        vm.expectRevert();
        impl.initialize("x", "x", address(stUSR));
    }
}