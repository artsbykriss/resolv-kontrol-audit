// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ITreasury} from "./ITreasury.sol";
import {IDefaultErrors} from "./IDefaultErrors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IEtherFiTreasuryExtension is IDefaultErrors {

    event Received(address indexed _from, uint256 _amount);
    event Deposited(bytes32 indexed _idempotencyKey, uint256 _amount, uint256 _eETHShares, address indexed _asset, uint256 _assetAmount);
    event WithdrawalRequested(bytes32 indexed _idempotencyKey, uint256 _weETHAmount, uint256 indexed _requestId);
    event WithdrawalClaimed(uint256 indexed _requestId, uint256 _ethAmount);
    event InstantRedeemed(bytes32 indexed _idempotencyKey, uint256 _weETHAmount);
    event Wrapped(bytes32 indexed _idempotencyKey, uint256 _eETHAmount, uint256 _weETHAmount);
    event Unwrapped(bytes32 indexed _idempotencyKey, uint256 _weETHAmount, uint256 _eETHAmount);
    event EmergencyWithdrawnERC20(address indexed _token, address indexed _to, uint256 _amount);
    event EmergencyWithdrawnERC721(address indexed _token, address indexed _to, uint256 _tokenId);
    event EmergencyWithdrawnETH(address indexed _to, uint256 _amount);
    event TreasurySet(address _treasury);
    event ReferralCodeSet(address indexed _referralCode);

    function depositETHForEETH(bytes32 _idempotencyKey, uint256 _amount) external;

    function depositETHForWeETH(bytes32 _idempotencyKey, uint256 _amount) external;

    function requestWithdrawal(bytes32 _idempotencyKey, uint256 _weETHAmount) external;

    function claimWithdrawal(uint256 _requestId) external;

    function instantRedeem(bytes32 _idempotencyKey, uint256 _weETHAmount) external;

    function wrapEETHToWeETH(bytes32 _idempotencyKey, uint256 _eETHAmount) external;

    function unwrapWeETHToEETH(bytes32 _idempotencyKey, uint256 _weETHAmount) external;

    function emergencyWithdrawERC20(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external;

    function emergencyWithdrawERC721(
        IERC721 _token,
        address _to,
        uint256 _tokenId
    ) external;

    function emergencyWithdrawETH(
        address payable _to,
        uint256 _amount
    ) external;

    function setTreasury(ITreasury _treasury) external;

    function setReferralCode(address _referralCode) external;
}
