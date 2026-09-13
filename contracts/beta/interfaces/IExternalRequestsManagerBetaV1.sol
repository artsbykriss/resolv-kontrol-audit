// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IDefaultErrors} from "../../interfaces/IDefaultErrors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IExternalRequestsManagerBetaV1 is IDefaultErrors {

    event MintRequestCreated(uint256 indexed id, address indexed provider, address depositToken, uint256 amount);
    event MintRequestCompleted(bytes32 idempotencyKey, uint256 indexed id, uint256 mintedAmount);
    event MintRequestCancelled(uint256 indexed id);

    event BurnRequestCreated(
        uint256 indexed id,
        address indexed provider,
        uint256 issueTokenAmount,
        address withdrawalTokenAddress
    );
    event BurnRequestCompleted(uint256 indexed id, uint256 burnedAmount, uint256 withdrawalAmount);
    event BurnRequestCancelled(uint256 indexed id);

    event TreasurySet(address treasuryAddress);
    event ProvidersWhitelistSet(address providersWhitelistAddress);
    event WhitelistEnabledSet(bool isEnabled);
    event AllowedTokenAdded(address tokenAddress);
    event AllowedTokenRemoved(address tokenAddres);
    event EmergencyWithdrawn(address tokenAddress, uint256 amount);

    error UnknownProvider(address account);
    error IllegalState(State expected, State current);
    error IllegalAddress(address expected, address actual);
    error MintRequestNotExist(uint256 id);
    error BurnRequestNotExist(uint256 id);
    error TokenNotAllowed(address token);
    error InvalidProvidersWhitelist(address providersWhitelistAddress);

    enum State {CREATED, COMPLETED, CANCELLED}
    struct Request {
        uint256 id;
        address payable provider;
        State state;
        uint256 amount;
        address token;
        bool exists;
    }

    function setTreasury(address payable _treasuryAddress) external;

    function setProvidersWhitelist(address _providersWhitelistAddress) external;

    function setWhitelistEnabled(bool _isEnabled) external;

    function addAllowedToken(address _allowedTokenAddress) external;

    function removeAllowedToken(address _allowedTokenAddress) external;

    function pause() external;

    function unpause() external;

    function requestMint(address _depositTokenAddress, uint256 _amount) external;

    function requestMintWithPermit(
        address _depositTokenAddress,
        uint256 _amount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external;

    function cancelMint(uint256 _id) external;

    function completeMint(bytes32 _idempotencyKey, uint256 _id, uint256 _mintAmount) external;

    function requestBurn(uint256 _issueTokenAmount, address _withdrawalTokenAddress) external;

    function requestBurnWithPermit(
        uint256 _issueTokenAmount,
        address _withdrawalTokenAddress,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external;

    function cancelBurn(uint256 _id) external;

    function completeBurn(uint256 _id, uint256 _withdrawalAmount) external;

    function emergencyWithdraw(IERC20 _token) external;
}
