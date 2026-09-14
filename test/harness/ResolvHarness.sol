// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {StUSR} from "contracts/StUSR.sol";
import {WstUSR} from "contracts/WstUSR.sol";

/// @dev Shared deployment harness for the permissionless token surfaces.
///      Contracts are upgradeable implementations, so they are deployed behind
///      an ERC1967 proxy exactly as on mainnet. USR is a plain 18-decimal ERC20
///      (the real USR `SimpleToken` adds only role-gated mint/burn, irrelevant
///      to share math).
contract ResolvHarness is Test {
    MockERC20 internal usr;
    StUSR internal stUSR;
    WstUSR internal wstUSR;

    address internal constant alice = address(0xA11CE);
    address internal constant bob = address(0xB0B);
    address internal constant attacker = address(0xBAD);

    uint256 internal constant MAX = type(uint256).max;

    function setUp() public virtual {
        usr = new MockERC20("Resolv USD", "USR", 18);

        stUSR = _newStUSR();

        wstUSR = _newWstUSR(address(stUSR));
        wstUSR.initializeV2(address(this), address(this));

        _seed(1_000_000e18);
    }

    function _newStUSR() internal returns (StUSR) {
        StUSR impl = new StUSR();
        bytes memory init = abi.encodeCall(StUSR.initialize, ("Staked USR", "stUSR", address(usr)));
        return StUSR(address(new ERC1967Proxy(address(impl), init)));
    }

    function _newWstUSR(address stUSRAddr) internal returns (WstUSR) {
        WstUSR impl = new WstUSR();
        bytes memory init = abi.encodeCall(WstUSR.initialize, ("Wrapped stUSR", "wstUSR", stUSRAddr));
        return WstUSR(address(new ERC1967Proxy(address(impl), init)));
    }

    /// @dev Seed a realistic non-empty pool so exchange-rate math is nontrivial.
    function _seed(uint256 amt) internal {
        address seedAcct = address(0x5EED);
        _fund(seedAcct, amt);
        vm.prank(seedAcct);
        stUSR.deposit(amt, seedAcct);
    }

    function _fund(address who, uint256 amt) internal {
        usr.mint(who, amt);
        vm.prank(who);
        usr.approve(address(stUSR), MAX);
        vm.prank(who);
        usr.approve(address(wstUSR), MAX);
        vm.prank(who);
        stUSR.approve(address(wstUSR), MAX);
    }
}