// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {MockUSR} from "./mocks/MockUSR.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {TheCounter} from "contracts/TheCounter.sol";
import {UsrExternalRequestsManager} from "contracts/UsrExternalRequestsManager.sol";

contract MockWhitelist {
    mapping(address => bool) public ok;
    function set(address a, bool v) external { ok[a] = v; }
    function isAllowedAccount(address a) external view returns (bool) { return ok[a]; }
}

contract MockRedemptionExt {
    function redeem(uint256, address, address) external pure returns (uint256) { return 0; }
    function redeem(uint256, address) external pure {}
    function getRedeemPrice(address) external pure returns (uint80, int256, uint256, uint256, uint80) {
        return (0, 0, 0, 0, 0);
    }
}

/// W4 — request managers / counter: the arbitrary-mint class (the 2026-03 bug) and request lifecycle.
contract W4_Requests_Test is Test {
    MockUSR internal usr;
    MockERC20 internal usdc;
    MockERC20 internal treasury;

    address internal provider;
    address internal service = address(0x5E12);
    uint256 internal constant MAX = type(uint256).max;

    function setUp() public {
        provider = address(0xF00D);
        usr = new MockUSR();
        usdc = new MockERC20("USD Coin", "USDC", 6);
        treasury = new MockERC20("Treasury", "TRSY", 18);
        vm.warp(1_800_000_000);
    }

    // ==================================================================
    // TheCounter
    // ==================================================================

    function _counter() internal returns (TheCounter c) {
        address[] memory allowed = new address[](1);
        allowed[0] = address(usdc);
        uint256[] memory mins = new uint256[](1);
        mins[0] = 1;
        c = new TheCounter(address(usr), allowed, mins, 1000, address(treasury));
        c.grantRole(c.SERVICE_ROLE(), service);
    }

    /// W4-P6 (P): a user can always cancel a pending swap and recover the deposit.
    function test_W4P6_requestCancelRecoversDeposit(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000e6);
        TheCounter c = _counter();
        usdc.mint(provider, amount);
        vm.prank(provider);
        usdc.approve(address(c), MAX);

        uint256 before = usdc.balanceOf(provider);
        vm.prank(provider);
        c.requestSwap(address(usdc), amount, 0);
        assertEq(usdc.balanceOf(provider), before - amount, "deposit not taken");

        vm.prank(provider);
        c.cancelSwap(0);
        assertEq(usdc.balanceOf(provider), before, "deposit not recovered");
    }

    /// W4-P5: KNOWN VULNERABILITY — `completeSwap` has no bound tying the minted
    /// amount to the deposited amount. A compromised SERVICE_ROLE (the 2026-03
    /// exploit) mints arbitrary USR. This test asserts the bug is present.
    function test_W4P5_completeSwap_missingBound_KNOWNVULN(uint256 amount, uint256 minted) public {
        amount = bound(amount, 1, 1_000_000e6);
        minted = bound(minted, 1_000e18, 1_000_000_000e18);
        TheCounter c = _counter();
        usdc.mint(provider, amount);
        vm.prank(provider);
        usdc.approve(address(c), MAX);
        vm.prank(provider);
        c.requestSwap(address(usdc), amount, 0);

        vm.prank(service);
        c.completeSwap(keccak256("k"), 0, minted);

        // deposit is worth `amount` USDC (~$amount/1e6). The counter minted `minted` USR
        // (minus fee) to the provider with no proportionality check.
        uint256 payout = usr.balanceOf(provider);
        assertGe(payout, minted - minted / 1000, "expected arbitrary mint");
        assertGt(payout, amount * 1000, "mint disproportionate to deposit (VULN)");
    }

    /// W4-P5b (control): completion respects the request's own minExpectedAmount floor.
    function test_W4P5b_minExpectedEnforced(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000e6);
        TheCounter c = _counter();
        usdc.mint(provider, amount);
        vm.prank(provider);
        usdc.approve(address(c), MAX);
        vm.prank(provider);
        c.requestSwap(address(usdc), amount, 1_000e18);

        vm.prank(service);
        vm.expectRevert();
        c.completeSwap(keccak256("k"), 0, 1e18); // below minExpectedAmount
    }

    // ==================================================================
    // UsrExternalRequestsManager
    // ==================================================================

    function _manager() internal returns (UsrExternalRequestsManager m, MockWhitelist wl) {
        wl = new MockWhitelist();
        wl.set(provider, true);
        MockRedemptionExt ext = new MockRedemptionExt();
        address[] memory allowed = new address[](1);
        allowed[0] = address(usdc);
        m = new UsrExternalRequestsManager(
            address(usr), address(treasury), address(wl), address(ext), allowed
        );
        m.grantRole(m.SERVICE_ROLE(), service);
    }

    /// W4-P3: a mint request can be completed at most once.
    function test_W4P3_noDoubleComplete(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000e6);
        (UsrExternalRequestsManager m,) = _manager();
        usdc.mint(provider, amount);
        vm.prank(provider);
        usdc.approve(address(m), MAX);
        vm.prank(provider);
        m.requestMint(address(usdc), amount, 0);

        vm.prank(service);
        m.completeMint(keccak256("k1"), 0, 1_000e18);
        vm.prank(service);
        vm.expectRevert();
        m.completeMint(keccak256("k2"), 0, 1_000e18);
    }

    /// W4-P1: KNOWN VULNERABILITY — `completeMint` mints an arbitrary `_mintAmount`
    /// (only floored by the attacker-chosen `minMintAmount`), no ratio to deposit.
    function test_W4P1_completeMint_missingBound_KNOWNVULN(uint256 amount, uint256 minted) public {
        amount = bound(amount, 1, 1_000_000e6);
        minted = bound(minted, 1_000e18, 1_000_000_000e18);
        (UsrExternalRequestsManager m,) = _manager();
        usdc.mint(provider, amount);
        vm.prank(provider);
        usdc.approve(address(m), MAX);
        vm.prank(provider);
        m.requestMint(address(usdc), amount, 0);

        vm.prank(service);
        m.completeMint(keccak256("k"), 0, minted);
        assertEq(usr.balanceOf(provider), minted, "expected arbitrary mint (VULN)");
        assertGt(minted, amount * 1000, "mint disproportionate to deposit (VULN)");
    }

    /// W4-P2: KNOWN VULNERABILITY — `completeBurn` pays an arbitrary `_withdrawalAmount`
    /// out of the treasury for a burned USR request.
    function test_W4P2_completeBurn_overWithdraw_KNOWNVULN(uint256 burnAmt, uint256 withdraw) public {
        burnAmt = bound(burnAmt, 1, 1_000_000e18);
        withdraw = bound(withdraw, 1_000e6, 1_000_000_000e6);
        (UsrExternalRequestsManager m,) = _manager();
        usdc.mint(address(treasury), 1_000_000_000e6);
        vm.prank(address(treasury));
        usdc.approve(address(m), MAX);

        usr.mint(provider, burnAmt);
        vm.prank(provider);
        usr.approve(address(m), MAX);
        vm.prank(provider);
        m.requestBurn(burnAmt, address(usdc), 0);

        vm.prank(service);
        m.completeBurn(keccak256("k"), 0, withdraw);
        assertEq(usdc.balanceOf(provider), withdraw, "expected arbitrary withdrawal (VULN)");
    }

    /// W4-P4: `emergencyWithdraw` is admin-only.
    function test_W4P4_emergencyWithdrawOnlyAdmin() public {
        (UsrExternalRequestsManager m,) = _manager();
        usdc.mint(address(m), 1_000e6);
        vm.prank(provider);
        vm.expectRevert();
        m.emergencyWithdraw(usdc);
    }

    /// W4-P4b (P): a non-whitelisted provider cannot create a mint request.
    function test_W4P4b_whitelistGate(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000e6);
        (UsrExternalRequestsManager m,) = _manager();
        usdc.mint(address(0xDEAD), amount);
        vm.prank(address(0xDEAD));
        usdc.approve(address(m), MAX);
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        m.requestMint(address(usdc), amount, 0);
    }
}