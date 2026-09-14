// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {MockUSR} from "./mocks/MockUSR.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UsrExternalRequestsManager} from "contracts/UsrExternalRequestsManager.sol";
import {ExternalRequestsCoordinator} from "contracts/ExternalRequestsCoordinator.sol";

/// @dev Treasury stand-in: an ERC20 that also exposes the `increaseAllowance`
///      entry point the coordinator uses (spender-whitelist path).
contract W5Treasury is MockERC20 {
    constructor() MockERC20("Treasury", "TRSY", 18) {}
    function increaseAllowance(bytes32, IERC20 token, address spender, uint256 amount) external {
        token.approve(spender, amount);
    }
}

contract W5Whitelist {
    mapping(address => bool) public ok;
    function set(address a, bool v) external { ok[a] = v; }
    function isAllowedAccount(address a) external view returns (bool) { return ok[a]; }
}

contract W5Ext {
    function redeem(uint256, address, address) external pure returns (uint256) { return 0; }
    function redeem(uint256, address) external pure {}
    function getRedeemPrice(address) external pure returns (uint80, int256, uint256, uint256, uint80) {
        return (0, 0, 0, 0, 0);
    }
}

/// W5 — ExternalRequestsCoordinator / Treasury composition (SERVICE-gated).
/// Uses the real managers + coordinator so the allowance path is faithfully exercised.
contract W5_Coordinator_Test is Test {
    MockUSR internal usr;
    MockUSR internal rlp;
    W5Treasury internal treasury;
    W5Whitelist internal wl;
    UsrExternalRequestsManager internal usrMgr;
    UsrExternalRequestsManager internal rlpMgr;
    ExternalRequestsCoordinator internal coord;

    address internal provider;
    address internal service = address(0x5E12);
    uint256 internal constant MAX = type(uint256).max;

    function setUp() public {
        provider = address(0xF00D);
        vm.warp(1_800_000_000);
        usr = new MockUSR();
        rlp = new MockUSR();
        treasury = new W5Treasury();
        wl = new W5Whitelist();
        wl.set(provider, true);
        W5Ext ext = new W5Ext();

        address[] memory allowedU = new address[](2);
        allowedU[0] = address(treasury);
        allowedU[1] = address(usr);
        usrMgr = new UsrExternalRequestsManager(address(usr), address(treasury), address(wl), address(ext), allowedU);

        address[] memory allowedR = new address[](1);
        allowedR[0] = address(treasury);
        rlpMgr = new UsrExternalRequestsManager(address(rlp), address(treasury), address(wl), address(ext), allowedR);

        coord = new ExternalRequestsCoordinator(
            address(usr), address(rlp), address(usrMgr), address(rlpMgr), address(this)
        );
        usrMgr.grantRole(usrMgr.SERVICE_ROLE(), address(coord));
        rlpMgr.grantRole(rlpMgr.SERVICE_ROLE(), address(coord));
        coord.grantRole(coord.SERVICE_ROLE(), service);
    }

    function _usrRequest(uint256 amount, uint256 minOut) internal returns (uint256 id) {
        usr.mint(provider, amount);
        vm.prank(provider);
        usr.approve(address(usrMgr), MAX);
        vm.prank(provider);
        usrMgr.requestMint(address(usr), amount, minOut);
        id = usrMgr.mintRequestsCounter() - 1;
    }

    /// W5-P4: only SERVICE_ROLE can drive the coordinator.
    function test_W5P4_onlyService(uint256 amount) public {
        vm.assume(amount >= 1 && amount <= 1e27);
        uint256 id = _usrRequest(amount, 0);
        vm.prank(address(0xBAD));
        vm.expectRevert();
        coord.completeMint(keccak256("k"), id, address(usr), amount);
    }

    /// W5-P3: when the deposit is a protocol token, the coordinator burns exactly
    /// the deposited amount from the treasury (offsetting the mint).
    function test_W5P3_protocolDepositBurnedFromTreasury(uint256 amount) public {
        vm.assume(amount >= 1 && amount <= 1e27);
        uint256 id = _usrRequest(amount, 0);

        // treasury starts with no USR; manager will forward the deposit to it
        uint256 supplyBefore = usr.totalSupply();

        vm.prank(service);
        coord.completeMint(keccak256("k"), id, address(usr), amount);

        // provider got `amount` minted; treasury received `amount` then it was burned:
        // net supply delta == minted - burned == 0 when mintAmount == depositAmount
        assertEq(usr.totalSupply(), supplyBefore, "protocol-token mint/burn not balanced");
        assertEq(usr.balanceOf(address(treasury)), 0, "treasury retained protocol token");
        assertEq(usr.balanceOf(provider), amount, "provider mint wrong");
    }

    /// W5-P1: the payout always goes to the request provider, never a chosen recipient.
    function test_W5P1_recipientIsProvider(uint256 amount) public {
        vm.assume(amount >= 1 && amount <= 1e27);
        uint256 id = _usrRequest(amount, 0);
        vm.prank(service);
        coord.completeMint(keccak256("k"), id, address(usr), amount);
        assertEq(usr.balanceOf(provider), amount, "recipient != provider");
    }

    /// W5-P2: the burn path grants the manager an allowance that is fully consumed.
    function test_W5P2_burnAllowanceConsumed(uint256 amount) public {
        vm.assume(amount >= 1 && amount <= 1e27);
        // provider burns USR and withdraws USR (protocol token) from treasury
        usr.mint(provider, amount);
        vm.prank(provider);
        usr.approve(address(usrMgr), MAX);
        vm.prank(provider);
        usrMgr.requestBurn(amount, address(usr), 0);
        uint256 id = usrMgr.burnRequestsCounter() - 1;

        vm.prank(service);
        coord.completeBurn(keccak256("k"), id, address(usr), amount);

        assertEq(usr.allowance(address(treasury), address(usrMgr)), 0, "residual allowance");
        assertEq(usr.balanceOf(provider), amount, "provider not paid");
    }

    /// W5-P5: a non-protocol deposit does not mint/burn any protocol token.
    function test_W5P5_nonProtocolDepositNoBurn(uint256 amount) public {
        vm.assume(amount >= 1 && amount <= 1e27);
        MockERC20 other = new MockERC20("Other", "OTH", 18);
        usrMgr.addAllowedToken(address(other));
        other.mint(provider, amount);
        vm.prank(provider);
        other.approve(address(usrMgr), MAX);
        vm.prank(provider);
        usrMgr.requestMint(address(other), amount, 0);
        uint256 id = usrMgr.mintRequestsCounter() - 1;

        uint256 usrSupplyBefore = usr.totalSupply();
        vm.prank(service);
        coord.completeMint(keccak256("k"), id, address(usr), amount);
        assertEq(usr.totalSupply(), usrSupplyBefore + amount, "unexpected burn path");
    }
}