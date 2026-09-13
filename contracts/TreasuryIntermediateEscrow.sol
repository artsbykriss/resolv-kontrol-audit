// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ITreasuryIntermediateEscrow} from "./interfaces/ITreasuryIntermediateEscrow.sol";
import {AccessControlDefaultAdminRules} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITreasury} from "./interfaces/ITreasury.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

contract TreasuryIntermediateEscrow is ITreasuryIntermediateEscrow, AccessControlDefaultAdminRules {

    using Address for address payable;
    using SafeERC20 for IERC20;

    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    bytes32 public constant LOCKER_ROLE = keccak256("LOCKER_ROLE");
    bytes32 public constant RELEASER_ROLE = keccak256("RELEASER_ROLE");
    bytes32 public constant EXTERNAL_RELEASER_ROLE = keccak256("EXTERNAL_RELEASER_ROLE");
    bytes32 public constant FORCE_RELEASER_ROLE = keccak256("FORCE_RELEASER_ROLE");

    ITreasury public treasury;
    mapping(bytes32 id => EscrowEntry entry) public escrows;
    mapping(address token => uint256 locked) public lockedBalances;

    modifier escrowExists(bytes32 _escrowId) {
        require(
            escrows[_escrowId].payoutAmount == 0 && escrows[_escrowId].depositedAmount > 0,
            EscrowNotExistsOrAlreadyReleased(_escrowId)
        );
        _;
    }

    constructor(ITreasury _treasury) AccessControlDefaultAdminRules(1 days, msg.sender) {
        setTreasury(_treasury);
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function lock(
        bytes32 _id,
        uint256 _depositAmount,
        uint256 _minPayoutAmount,
        address _recipientAddress,
        address _depositTokenAddress,
        address _payoutTokenAddress
    ) external onlyRole(LOCKER_ROLE) {
        require(escrows[_id].depositedAmount == 0, EscrowIdAlreadyExists(_id));
        require(_depositAmount > 0, InvalidAmount(_depositAmount));
        require(_minPayoutAmount > 0, InvalidAmount(_minPayoutAmount));
        require(_recipientAddress != address(0), ZeroAddress());
        require(_depositTokenAddress != address(0), ZeroAddress());
        require(_payoutTokenAddress != address(0), ZeroAddress());

        escrows[_id] = EscrowEntry({
            depositedAmount: _depositAmount,
            minPayoutAmount: _minPayoutAmount,
            payoutAmount: 0,
            recipientAddress: _recipientAddress,
            depositedTokenAddress: _depositTokenAddress,
            payoutTokenAddress: _payoutTokenAddress
        });
        lockedBalances[_depositTokenAddress] += _depositAmount;

        if (_depositTokenAddress == ETH) {
            treasury.transferETH(_id, payable(_recipientAddress), _depositAmount);
        } else {
            treasury.transferERC20(_id, IERC20(_depositTokenAddress), _recipientAddress, _depositAmount);
        }

        emit Locked(_id, _depositAmount, _minPayoutAmount, _recipientAddress, _depositTokenAddress, _payoutTokenAddress);
    }

    function release(
        bytes32 _escrowId,
        uint256 _payoutAmount
    ) external onlyRole(RELEASER_ROLE) escrowExists(_escrowId) {
        EscrowEntry storage escrow = escrows[_escrowId];
        require(escrow.minPayoutAmount <= _payoutAmount, InsufficientPayoutAmount(escrow.minPayoutAmount, _payoutAmount));

        escrow.payoutAmount = _payoutAmount;
        lockedBalances[escrow.depositedTokenAddress] -= escrow.depositedAmount;

        sendPayout(escrow.payoutTokenAddress, _payoutAmount);

        emit Released(_escrowId, _payoutAmount);
    }

    function externalReleaseETH(
        bytes32 _escrowId,
        uint256 _payoutAmount
    ) external payable onlyRole(EXTERNAL_RELEASER_ROLE) escrowExists(_escrowId) {
        EscrowEntry storage escrow = escrows[_escrowId];
        require(escrow.minPayoutAmount <= _payoutAmount, InsufficientPayoutAmount(escrow.minPayoutAmount, _payoutAmount));
        require(escrow.payoutTokenAddress == ETH, PayoutTokenNotSupported(escrow.payoutTokenAddress));
        require(msg.value == _payoutAmount, InvalidAmount(_payoutAmount));

        escrow.payoutAmount = _payoutAmount;
        lockedBalances[escrow.depositedTokenAddress] -= escrow.depositedAmount;

        payable(address(treasury)).sendValue(_payoutAmount);

        emit ExternallyReleasedETH(_escrowId, _payoutAmount, msg.sender);
    }

    function externalReleaseWithPermit(
        bytes32 _escrowId,
        uint256 _payoutAmount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        IERC20Permit tokenPermit = IERC20Permit(escrows[_escrowId].payoutTokenAddress);
        // the use of `try/catch` allows the permit to fail and makes the code tolerant to frontrunning.
        // solhint-disable-next-line no-empty-blocks
        try tokenPermit.permit(msg.sender, address(this), _payoutAmount, _deadline, _v, _r, _s) {} catch {}
        externalRelease(_escrowId, _payoutAmount);
    }

    function forceRelease(
        bytes32 _escrowId,
        uint256 _payoutAmount
    ) external onlyRole(FORCE_RELEASER_ROLE) escrowExists(_escrowId) {
        require(_payoutAmount > 0, InvalidAmount(_payoutAmount));
        EscrowEntry storage escrow = escrows[_escrowId];

        escrow.payoutAmount = _payoutAmount;
        lockedBalances[escrow.depositedTokenAddress] -= escrow.depositedAmount;

        sendPayout(escrow.payoutTokenAddress, _payoutAmount);

        emit ForceReleased(_escrowId, _payoutAmount);
    }

    function emergencyWithdrawERC20(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(address(_token) != address(0), ZeroAddress());
        require(address(_to) != address(0), ZeroAddress());
        require(_amount > 0, InvalidAmount(_amount));

        _token.safeTransfer(_to, _amount);

        emit EmergencyWithdrawnERC20(address(_token), _to, _amount);
    }

    function emergencyWithdrawETH(
        address payable _to,
        uint256 _amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(address(_to) != address(0), ZeroAddress());
        require(_amount > 0, InvalidAmount(_amount));

        _to.sendValue(_amount);

        emit EmergencyWithdrawnETH(_to, _amount);
    }

    function externalRelease(
        bytes32 _escrowId,
        uint256 _payoutAmount
    ) public onlyRole(EXTERNAL_RELEASER_ROLE) escrowExists(_escrowId) {
        EscrowEntry storage escrow = escrows[_escrowId];
        require(escrow.minPayoutAmount <= _payoutAmount, InsufficientPayoutAmount(escrow.minPayoutAmount, _payoutAmount));
        require(escrow.payoutTokenAddress != ETH, PayoutTokenNotSupported(ETH));

        escrow.payoutAmount = _payoutAmount;
        lockedBalances[escrow.depositedTokenAddress] -= escrow.depositedAmount;

        // slither-disable-next-line arbitrary-send-erc20
        IERC20(escrow.payoutTokenAddress).safeTransferFrom(msg.sender, address(treasury), _payoutAmount);

        emit ExternallyReleased(_escrowId, _payoutAmount, msg.sender);
    }

    function setTreasury(ITreasury _treasury) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(address(_treasury) != address(0), ZeroAddress());
        treasury = _treasury;
        emit TreasurySet(address(_treasury));
    }

    function sendPayout(address _tokenAddress, uint256 _payoutAmount) internal {
        if (_tokenAddress == ETH) {
            payable(address(treasury)).sendValue(_payoutAmount);
        } else {
            IERC20(_tokenAddress).safeTransfer(address(treasury), _payoutAmount);
        }
    }
}
