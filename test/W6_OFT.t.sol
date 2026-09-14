// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SimpleOFTAdapter} from "contracts/layerzero/SimpleOFTAdapter.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IOFT, SendParam, OFTReceipt} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {MessagingParams, MessagingFee, MessagingReceipt, Origin} from
    "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

/// @dev Minimal LayerZero v2 endpoint stand-in (delegate no-op; send/quote succeed).
contract MockLZEndpoint {
    function setDelegate(address) external {}
    function eid() external pure returns (uint32) { return 1; }
    function quote(MessagingParams calldata, address) external pure returns (MessagingFee memory) {
        return MessagingFee(0, 0);
    }
    function send(MessagingParams calldata, address) external payable returns (MessagingReceipt memory) {
        return MessagingReceipt(bytes32(0), 0, MessagingFee(0, 0));
    }
}

/// W6 — LayerZero OFT adapter (permissionless `send`).
contract W6_OFT_Test is Test {
    MockERC20 internal token;
    MockLZEndpoint internal endpoint;
    SimpleOFTAdapter internal oft;

    address internal constant alice = address(0xA11CE);
    uint256 internal constant MAX = type(uint256).max;
    uint32 internal constant DST = 30111;
    uint256 internal constant DUST = 1e12; // 10^(18 - sharedDecimals 6)

    function setUp() public {
        token = new MockERC20("Resolv USD", "USR", 18);
        endpoint = new MockLZEndpoint();
        SimpleOFTAdapter impl = new SimpleOFTAdapter(address(token), address(endpoint));
        bytes memory init = abi.encodeCall(SimpleOFTAdapter.initialize, (address(this)));
        oft = SimpleOFTAdapter(address(new ERC1967Proxy(address(impl), init)));
        oft.setPeer(DST, bytes32(uint256(uint160(address(oft)))));
    }

    function _sp(uint256 amount) internal view returns (SendParam memory) {
        return SendParam({
            dstEid: DST,
            to: bytes32(uint256(uint160(alice))),
            amountLD: amount,
            minAmountLD: 0,
            extraOptions: hex"",
            composeMsg: hex"",
            oftCmd: hex""
        });
    }

    /// W6-P3: adapter exposes the locked token and requires approval.
    function test_W6P3_tokenAndApproval() public view {
        assertEq(oft.token(), address(token), "wrong token");
        assertTrue(oft.approvalRequired(), "approval not required");
    }

    /// W6-P2: only the owner can configure peers / delegates.
    function test_W6P2_setPeerOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        oft.setPeer(123, bytes32(uint256(1)));
        vm.prank(alice);
        vm.expectRevert();
        oft.setDelegate(alice);
    }

    /// W6-P1: a sender with no balance cannot move tokens.
    function test_W6P1_sendInsufficientBalanceReverts(uint256 amount) public {
        vm.assume(amount >= DUST && amount <= 1e30);
        MessagingFee memory fee = MessagingFee(0, 0);
        vm.prank(alice);
        vm.expectRevert();
        oft.send(_sp(amount), fee, alice);
    }

    /// W6-P1b: a sender with balance but no allowance cannot move tokens.
    function test_W6P1b_sendInsufficientAllowanceReverts(uint256 amount) public {
        vm.assume(amount >= DUST && amount <= 1e30);
        token.mint(alice, amount);
        MessagingFee memory fee = MessagingFee(0, 0);
        vm.prank(alice);
        vm.expectRevert();
        oft.send(_sp(amount), fee, alice);
    }

    /// W6-P1c: a successful send locks exactly `amountLD` (minus dust) in the adapter.
    function test_W6P1c_sendLocksExactAmount(uint256 amount) public {
        vm.assume(amount >= DUST && amount <= 1e30);
        uint256 sent = amount - (amount % DUST);
        token.mint(alice, amount);
        vm.prank(alice);
        token.approve(address(oft), MAX);

        MessagingFee memory fee = MessagingFee(0, 0);
        vm.prank(alice);
        (, OFTReceipt memory o) = oft.send(_sp(amount), fee, alice);

        assertEq(o.amountSentLD, sent, "wrong amountSent");
        assertEq(token.balanceOf(address(oft)), sent, "adapter did not lock amount");
        assertEq(token.balanceOf(alice), amount - sent, "sender not debited");
    }

    /// W6-P4: config setters are owner-only.
    function test_W6P4_configOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        oft.setMsgInspector(address(0x1234));
    }


    /// W6-P5: only the LayerZero endpoint can drive the receive path (no permissionless unlock).
    function test_W6P5_lzReceiveOnlyEndpoint() public {
        Origin memory origin = Origin({srcEid: 1, sender: bytes32(uint256(uint160(address(oft)))), nonce: 0});
        vm.prank(address(0xBAD));
        vm.expectRevert();
        oft.lzReceive(origin, bytes32(0), abi.encode(uint256(1e18)), address(0), hex"");
    }

    /// W6-P6: even the endpoint cannot credit from an unconfigured peer/origin.
    function test_W6P6_lzReceiveRejectsUnknownPeer() public {
        Origin memory origin = Origin({srcEid: 1, sender: bytes32(uint256(uint160(address(0xBAD)))), nonce: 0});
        vm.prank(address(endpoint));
        vm.expectRevert();
        oft.lzReceive(origin, bytes32(0), abi.encode(uint256(1e18)), address(0), hex"");
    }

    /// W6-P7: every send increases the adapter's locked balance by exactly amountSent (never decreases it).
    function test_W6P7_lockedBacking(uint256 amount) public {
        vm.assume(amount >= DUST && amount <= 1e30);
        uint256 sent = amount - (amount % DUST);
        token.mint(alice, amount);
        vm.prank(alice);
        token.approve(address(oft), MAX);
        MessagingFee memory fee = MessagingFee(0, 0);
        uint256 before = token.balanceOf(address(oft));
        vm.prank(alice);
        oft.send(_sp(amount), fee, alice);
        assertEq(token.balanceOf(address(oft)) - before, sent, "adapter lock mismatch");
    }

    /// W7-P5 (KNOWN VULN): the SimpleOFTAdapter constructor does NOT call
    /// `_disableInitializers()`, so any third party can initialize the bare
    /// implementation and become its owner. Asserts the vulnerability is present.
    function test_W7P5_implInitUnprotected_KNOWNVULN() public {
        SimpleOFTAdapter impl = new SimpleOFTAdapter(address(token), address(endpoint));
        impl.initialize(address(0xBAD));
        assertEq(impl.owner(), address(0xBAD), "impl owner not hijacked");
    }
}