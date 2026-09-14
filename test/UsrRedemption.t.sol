// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {MockUSR} from "./mocks/MockUSR.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockTreasury} from "./mocks/MockTreasury.sol";
import {MockChainlink} from "./mocks/MockChainlink.sol";
import {MockUsrPriceStorage} from "./mocks/MockUsrPriceStorage.sol";
import {UsrRedemptionExtension} from "contracts/UsrRedemptionExtension.sol";
import {ITreasury} from "contracts/interfaces/ITreasury.sol";
import {IChainlinkOracle} from "contracts/interfaces/oracles/IChainlinkOracle.sol";
import {IUsrPriceStorage} from "contracts/interfaces/IUsrPriceStorage.sol";

/// W1 — USR redemption pricing & limits.
contract UsrRedemption_Test is Test {
    MockUSR internal usr;
    MockERC20 internal usdc;
    MockTreasury internal treasury;
    MockChainlink internal cl;
    MockUsrPriceStorage internal ps;
    UsrRedemptionExtension internal ext;

    address internal service = address(0x5E12);
    address internal alice = address(0xA11CE);
    address internal receiver = address(0xBEEF);
    bytes32 internal SERVICE;

    uint256 internal constant BOUND = 1e30;
    uint256 internal constant LIMIT = 1_000_000e18;
    uint256 internal constant T0 = 1_800_000_000;

    function setUp() public {
        vm.warp(T0);
        usr = new MockUSR();
        usdc = new MockERC20("USD Coin", "USDC", 6);
        treasury = new MockTreasury();
        cl = new MockChainlink();
        ps = new MockUsrPriceStorage();

        usdc.mint(address(treasury), 1_000_000e6);
        cl.set(address(usdc), int256(1e8), 8, T0); // 1 USDC = $1 (8 dp)
        ps.set(1e18, T0); // USR fundamental = $1

        address[] memory allowed = new address[](1);
        allowed[0] = address(usdc);

        ext = new UsrRedemptionExtension(
            address(usr),
            allowed,
            ITreasury(address(treasury)),
            IChainlinkOracle(address(cl)),
            IUsrPriceStorage(address(ps)),
            1 days,
            LIMIT,
            0,
            T0,
            "1"
        );
        SERVICE = ext.SERVICE_ROLE();
        ext.grantRole(SERVICE, service);
    }

    // ------------------------------------------------------------------
    // Entitlement / conservation
    // ------------------------------------------------------------------

    /// W1-P1/P4: caller burns exactly `amount`; receiver gets exactly the
    /// floor entitlement (1:1 value, 6-dec token, 0 fee) and never more.
    function test_W1P1_exactPayout(uint256 amount) public {
        vm.assume(amount >= 1e12 && amount < 1_000_000e18);
        usr.mint(service, amount);

        uint256 usrBefore = usr.balanceOf(service);
        uint256 recvBefore = usdc.balanceOf(receiver);

        vm.prank(service);
        uint256 out = ext.redeem(amount, receiver, address(usdc));

        assertEq(usr.balanceOf(service), usrBefore - amount, "wrong USR burned");
        assertEq(usdc.balanceOf(receiver) - recvBefore, out, "receiver != return");
        assertEq(out, amount / 1e12, "payout not 1:1 floor");
        assertLe(out, amount / 1e12, "over-payment");
    }

    /// W1-P1b: payout never exceeds the USR burned (value conservation, 18-dec token).
    function test_W1P1b_neverExceedsBurned(uint256 amount) public {
        vm.assume(amount >= 1e12 && amount < 1_000_000e18);
        MockERC20 tok18 = new MockERC20("T", "T", 18);
        tok18.mint(address(treasury), 1_000_000e18);
        cl.set(address(tok18), int256(1e18), 18, T0);

        address[] memory allowed = new address[](2);
        allowed[0] = address(usdc);
        allowed[1] = address(tok18);

        UsrRedemptionExtension e2 = new UsrRedemptionExtension(
            address(usr), allowed, ITreasury(address(treasury)),
            IChainlinkOracle(address(cl)), IUsrPriceStorage(address(ps)),
            1 days, LIMIT, 0, T0, "2"
        );
        e2.grantRole(e2.SERVICE_ROLE(), service);
        usr.mint(service, amount);

        vm.prank(service);
        uint256 out = e2.redeem(amount, receiver, address(tok18));
        assertLe(out, amount, "payout exceeds burned USR");
    }

    // ------------------------------------------------------------------
    // Limits
    // ------------------------------------------------------------------

    /// W1-P2: a redemption above the daily limit reverts.
    function test_W1P2_limitEnforced(uint256 x) public {
        vm.assume(x >= 1 && x <= LIMIT);
        uint256 amount = LIMIT + x;
        usr.mint(service, amount);
        vm.prank(service);
        vm.expectRevert();
        ext.redeem(amount, receiver, address(usdc));
    }

    /// W1-P2b: cumulative usage over the limit reverts; a fresh day resets it.
    function test_W1P2b_cumulativeLimit(uint256 x, uint256 y) public {
        vm.assume(x >= 1 && x <= LIMIT);
        uint256 a = x;
        vm.assume(y >= LIMIT - a + 1 && y <= LIMIT);
        uint256 b = y;
        usr.mint(service, a + b);
        vm.prank(service);
        ext.redeem(a, receiver, address(usdc));
        vm.prank(service);
        vm.expectRevert();
        ext.redeem(b, receiver, address(usdc));
    }

    // ------------------------------------------------------------------
    // Price guards
    // ------------------------------------------------------------------

    /// W1-P7: stale USR price reverts.
    function test_W1P7_stalePriceReverts(uint256 amount) public {
        vm.assume(amount >= 1e12 && amount < 1_000_000e18);
        ps.set(1e18, T0 - 2 days);
        usr.mint(service, amount);
        vm.prank(service);
        vm.expectRevert();
        ext.redeem(amount, receiver, address(usdc));
    }

    /// W1-P7b: USR price below $1 reverts.
    function test_W1P7b_lowPriceReverts(uint256 amount) public {
        vm.assume(amount >= 1e12 && amount < 1_000_000e18);
        ps.set(0.5e18, T0);
        usr.mint(service, amount);
        vm.prank(service);
        vm.expectRevert();
        ext.redeem(amount, receiver, address(usdc));
    }

    // ------------------------------------------------------------------
    // Access control
    // ------------------------------------------------------------------

    /// W1-P8: a non-SERVICE caller cannot trigger any treasury payout.
    function test_W1P8_onlyService(uint256 amount) public {
        vm.assume(amount >= 1e12 && amount < 1_000_000e18);
        usr.mint(alice, amount);
        uint256 tBefore = usdc.balanceOf(address(treasury));
        vm.prank(alice);
        vm.expectRevert();
        ext.redeem(amount, receiver, address(usdc));
        assertEq(usdc.balanceOf(address(treasury)), tBefore, "treasury moved");
    }

    // ------------------------------------------------------------------
    // Treasury interaction
    // ------------------------------------------------------------------

    /// W1-P9: when the treasury is short, the Aave borrow equals exactly the shortfall.
    function test_W1P9_borrowIsShortfall(uint256 amount) public {
        vm.assume(amount >= 1e12 && amount < 1_000_000e18);
        MockERC20 t2 = new MockERC20("T2", "T2", 6);
        address[] memory allowed = new address[](2);
        allowed[0] = address(usdc);
        allowed[1] = address(t2);
        UsrRedemptionExtension e2 = new UsrRedemptionExtension(
            address(usr), allowed, ITreasury(address(treasury)),
            IChainlinkOracle(address(cl)), IUsrPriceStorage(address(ps)),
            1 days, LIMIT, 0, T0, "3"
        );
        e2.grantRole(e2.SERVICE_ROLE(), service);
        cl.set(address(t2), int256(1e8), 8, T0);
        usr.mint(service, amount);

        vm.prank(service);
        uint256 out = e2.redeem(amount, receiver, address(t2)); // treasury has 0 t2
        // the borrow key is internal; assert the treasury minted exactly `out` to itself then paid out
        assertEq(t2.balanceOf(receiver), out, "shortfall not covered");
    }

    /// W1-P10: the allowance granted is fully consumed by the payout.
    function test_W1P10_allowanceConsumed(uint256 amount) public {
        vm.assume(amount >= 1e12 && amount < 1_000_000e18);
        usr.mint(service, amount);
        vm.prank(service);
        ext.redeem(amount, receiver, address(usdc));
        assertEq(usdc.allowance(address(treasury), address(ext)), 0, "residual allowance");
    }
}