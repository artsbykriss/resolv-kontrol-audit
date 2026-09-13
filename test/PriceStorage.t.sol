// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UsrPriceStorage} from "contracts/UsrPriceStorage.sol";

/// W8 — price storage bounds (gates W1).
contract PriceStorage_Test is Test {
    UsrPriceStorage internal ps;
    address internal service = address(0x5E12);
    bytes32 internal SERVICE;

    uint256 internal constant T0 = 1_800_000_000;

    function setUp() public {
        vm.warp(T0);
        UsrPriceStorage impl = new UsrPriceStorage();
        bytes memory init = abi.encodeCall(UsrPriceStorage.initialize, (1e16)); // 1% lower bound
        ps = UsrPriceStorage(address(new ERC1967Proxy(address(impl), init)));
        SERVICE = ps.SERVICE_ROLE();
        ps.grantRole(SERVICE, service);
    }

    function _set(bytes32 k, uint256 supply, uint256 reserves) internal {
        vm.prank(service);
        ps.setReserves(k, supply, reserves);
    }

    /// W8-P1: price formula — capped at 1e18, else reserves*1e18/supply.
    function test_W8P1_priceFormula(uint256 supply, uint256 reserves) public {
        supply = bound(supply, 1, 1e30);
        reserves = bound(reserves, 1, 1e30);
        _set(bytes32("k"), supply, reserves);
        uint256 expected = reserves >= supply ? 1e18 : (reserves * 1e18) / supply;
        (uint256 p,,,) = ps.prices(bytes32("k"));
        assertEq(p, expected, "wrong price");
        assertLe(p, 1e18, "price above $1");
    }

    /// W8-P1b: a drop below the configured lower bound reverts (no sudden depeg price).
    function test_W8P1b_lowerBoundEnforced() public {
        _set(bytes32("a"), 1_000e18, 1_000e18); // lastPrice = 1e18
        // 0.9e18 < 0.99e18 lower bound -> revert
        vm.prank(service);
        vm.expectRevert();
        ps.setReserves(bytes32("b"), 1_000e18, 900e18);
    }

    /// W8-P1c: a drop within the bound is accepted and becomes the new reference.
    function test_W8P1c_withinBoundAccepted() public {
        _set(bytes32("a"), 1_000e18, 1_000e18);
        _set(bytes32("b"), 1_000e18, 995e18); // 0.995 >= 0.99
        (uint256 p,,,) = ps.prices(bytes32("b"));
        assertEq(p, 995e15, "within-bound price wrong");
    }

    /// W8-P1d: a key can only be set once.
    function test_W8P1d_keyOneShot() public {
        _set(bytes32("a"), 1_000e18, 1_000e18);
        vm.prank(service);
        vm.expectRevert();
        ps.setReserves(bytes32("a"), 1_000e18, 1_000e18);
    }

    /// W8-P1e: only SERVICE_ROLE can set reserves.
    function test_W8P1e_onlyService() public {
        vm.prank(address(0xBAD));
        vm.expectRevert();
        ps.setReserves(bytes32("a"), 1_000e18, 1_000e18);
    }

    /// W8-P1f: lower-bound percentage is admin-only and bounded to (0, 1e18].
    function test_W8P1f_lowerBoundConfig() public {
        vm.prank(address(0xBAD));
        vm.expectRevert();
        ps.setLowerBoundPercentage(1e16);
        vm.expectRevert();
        ps.setLowerBoundPercentage(0);
        vm.expectRevert();
        ps.setLowerBoundPercentage(1e18 + 1);
    }
}