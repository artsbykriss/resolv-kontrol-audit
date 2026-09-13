// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ITreasury} from "./ITreasury.sol";
import {IDefaultErrors} from "./IDefaultErrors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITreasuryIntermediateEscrow is IDefaultErrors {

    struct EscrowEntry {
        uint256 depositedAmount;
        uint256 minPayoutAmount;
        uint256 payoutAmount;
        address recipientAddress;
        address depositedTokenAddress;
        address payoutTokenAddress;
    }

    event Locked(
        bytes32 indexed _id,
        uint256 _depositAmount,
        uint256 _minPayoutAmount,
        address _recipientAddress,
        address indexed _depositTokenAddress,
        address indexed _payoutTokenAddress
    );
    event Released(bytes32 indexed _id, uint256 _payoutAmount);
    event ExternallyReleasedETH(bytes32 indexed _id, uint256 _payoutAmount, address indexed _fromAddress);
    event ForceReleased(bytes32 indexed _id, uint256 _payoutAmount);
    event ExternallyReleased(bytes32 indexed _id, uint256 _payoutAmount, address indexed _fromAddress);
    event TreasurySet(address _treasury);
    event Received(address indexed _from, uint256 _amount);
    event EmergencyWithdrawnERC20(address indexed _token, address indexed _to, uint256 _amount);
    event EmergencyWithdrawnETH(address indexed _to, uint256 _amount);

    error EscrowIdAlreadyExists(bytes32 _id);
    error EscrowNotExistsOrAlreadyReleased(bytes32 _id);
    error InsufficientPayoutAmount(uint256 _minPayoutAmount, uint256 _payoutAmount);
    error PayoutTokenNotSupported(address _payoutTokenAddress);

    function lock(
        bytes32 _id,
        uint256 _depositAmount,
        uint256 _minPayoutAmount,
        address _recipientAddress,
        address _depositTokenAddress,
        address _payoutTokenAddress
    ) external;

    function release(
        bytes32 _escrowId,
        uint256 _payoutAmount
    ) external;

    function externalReleaseWithPermit(
        bytes32 _escrowId,
        uint256 _payoutAmount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external;

    function externalReleaseETH(
        bytes32 _escrowId,
        uint256 _payoutAmount
    ) external payable;

    function forceRelease(
        bytes32 _escrowId,
        uint256 _payoutAmount
    ) external;

    function externalRelease(
        bytes32 _escrowId,
        uint256 _payoutAmount
    ) external;

    function emergencyWithdrawERC20(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external;

    function emergencyWithdrawETH(
        address payable _to,
        uint256 _amount
    ) external;

    function setTreasury(ITreasury _treasury) external;
}
