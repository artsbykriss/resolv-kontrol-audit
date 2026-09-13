// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {AccessControlDefaultAdminRules} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IEtherFiTreasuryExtension} from "./interfaces/IEtherFiTreasuryExtension.sol";
import {ILiquidityPool} from "./interfaces/external/etherfi/ILiquidityPool.sol";
import {ITreasury} from "./interfaces/ITreasury.sol";
import {IWeETH} from "./interfaces/external/etherfi/IWeETH.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IEtherFiRedemptionManager} from "./interfaces/external/etherfi/IEtherFiRedemptionManager.sol";
import {IWithdrawRequestNFT} from "./interfaces/external/etherfi/IWithdrawRequestNFT.sol";

contract EtherFiTreasuryExtension is IEtherFiTreasuryExtension, ERC721Holder, AccessControlDefaultAdminRules {

    using Address for address payable;
    using SafeERC20 for IERC20;

    bytes32 public constant SERVICE_ROLE = keccak256("SERVICE_ROLE");
    address public constant E_ETH_ADDRESS = address(0x35fA164735182de50811E8e2E824cFb9B6118ac2);
    address public constant WE_ETH_ADDRESS = address(0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee);
    ILiquidityPool public constant LIQUIDITY_POOL = ILiquidityPool(0x308861A430be4cce5502d0A12724771Fc6DaF216);
    IWithdrawRequestNFT public constant WITHDRAW_REQUEST_NFT = IWithdrawRequestNFT(0x7d5706f6ef3F89B3951E23e557CDFBC3239D4E2c);
    IEtherFiRedemptionManager public constant REDEMPTION_MANAGER = IEtherFiRedemptionManager(0xDadEf1fFBFeaAB4f68A9fD181395F68b4e4E7Ae0);

    ITreasury public treasury;
    address public referralCode;

    constructor(ITreasury _treasury, address _referralCode) AccessControlDefaultAdminRules(1 days, msg.sender) {
        setTreasury(_treasury);
        setReferralCode(_referralCode);
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function depositETHForEETH(bytes32 _idempotencyKey, uint256 _amount) external onlyRole(SERVICE_ROLE) {
        require(_amount > 0, InvalidAmount(_amount));

        treasury.transferETH(_idempotencyKey, payable(address(this)), _amount);

        uint256 eETHShares = LIQUIDITY_POOL.deposit{value: _amount}(referralCode);
        uint256 eEthAmount = LIQUIDITY_POOL.amountForShare(eETHShares);
        require(eEthAmount > 0, TooSmallAmount(eEthAmount));
        IERC20(E_ETH_ADDRESS).safeTransfer(address(treasury), eEthAmount);

        emit Deposited(_idempotencyKey, _amount, eETHShares, E_ETH_ADDRESS, eEthAmount);
    }

    function depositETHForWeETH(bytes32 _idempotencyKey, uint256 _amount) external onlyRole(SERVICE_ROLE) {
        require(_amount > 0, InvalidAmount(_amount));

        treasury.transferETH(_idempotencyKey, payable(address(this)), _amount);

        uint256 eETHShares = LIQUIDITY_POOL.deposit{value: _amount}(referralCode);
        uint256 eEthAmount = LIQUIDITY_POOL.amountForShare(eETHShares);
        require(eEthAmount > 0, TooSmallAmount(eEthAmount));
        IERC20(E_ETH_ADDRESS).safeIncreaseAllowance(WE_ETH_ADDRESS, eEthAmount);

        uint256 weETHAmount = IWeETH(WE_ETH_ADDRESS).wrap(eEthAmount);
        IERC20(WE_ETH_ADDRESS).safeTransfer(address(treasury), weETHAmount);

        emit Deposited(_idempotencyKey, _amount, eETHShares, WE_ETH_ADDRESS, weETHAmount);
    }

    function requestWithdrawal(bytes32 _idempotencyKey, uint256 _weETHAmount) external onlyRole(SERVICE_ROLE) {
        require(_weETHAmount > 0, InvalidAmount(_weETHAmount));

        treasury.transferERC20(_idempotencyKey, IERC20(WE_ETH_ADDRESS), address(this), _weETHAmount);

        uint256 eETHAmount = IWeETH(WE_ETH_ADDRESS).unwrap(_weETHAmount);
        IERC20(E_ETH_ADDRESS).safeIncreaseAllowance(address(LIQUIDITY_POOL), eETHAmount);
        uint256 requestId = LIQUIDITY_POOL.requestWithdraw(address(this), eETHAmount);

        emit WithdrawalRequested(_idempotencyKey, _weETHAmount, requestId);
    }

    function claimWithdrawal(uint256 _requestId) external onlyRole(SERVICE_ROLE) {
        uint256 initialBalance = address(this).balance;
        WITHDRAW_REQUEST_NFT.claimWithdraw(_requestId);

        uint256 ethAmount = address(this).balance - initialBalance;
        require(ethAmount > 0, TooSmallAmount(ethAmount));
        payable(address(treasury)).sendValue(ethAmount);

        emit WithdrawalClaimed(_requestId, ethAmount);
    }

    function instantRedeem(bytes32 _idempotencyKey, uint256 _weETHAmount) external onlyRole(SERVICE_ROLE) {
        require(_weETHAmount > 0, InvalidAmount(_weETHAmount));

        treasury.transferERC20(_idempotencyKey, IERC20(WE_ETH_ADDRESS), address(this), _weETHAmount);
        IERC20(WE_ETH_ADDRESS).safeIncreaseAllowance(address(REDEMPTION_MANAGER), _weETHAmount);

        REDEMPTION_MANAGER.redeemWeEth(_weETHAmount, address(treasury));

        emit InstantRedeemed(_idempotencyKey, _weETHAmount);
    }

    function wrapEETHToWeETH(bytes32 _idempotencyKey, uint256 _eETHAmount) external onlyRole(SERVICE_ROLE) {
        require(_eETHAmount > 0, InvalidAmount(_eETHAmount));

        treasury.transferERC20(_idempotencyKey, IERC20(E_ETH_ADDRESS), address(this), _eETHAmount);

        IERC20(E_ETH_ADDRESS).safeIncreaseAllowance(WE_ETH_ADDRESS, _eETHAmount);
        uint256 weETHAmount = IWeETH(WE_ETH_ADDRESS).wrap(_eETHAmount);
        IERC20(WE_ETH_ADDRESS).safeTransfer(address(treasury), weETHAmount);

        emit Wrapped(_idempotencyKey, _eETHAmount, weETHAmount);
    }

    function unwrapWeETHToEETH(bytes32 _idempotencyKey, uint256 _weETHAmount) external onlyRole(SERVICE_ROLE) {
        require(_weETHAmount > 0, InvalidAmount(_weETHAmount));

        treasury.transferERC20(_idempotencyKey, IERC20(WE_ETH_ADDRESS), address(this), _weETHAmount);

        uint256 eETHAmount = IWeETH(WE_ETH_ADDRESS).unwrap(_weETHAmount);
        IERC20(E_ETH_ADDRESS).safeTransfer(address(treasury), eETHAmount);

        emit Unwrapped(_idempotencyKey, _weETHAmount, eETHAmount);
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

    function emergencyWithdrawERC721(
        IERC721 _token,
        address _to,
        uint256 _tokenId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(address(_token) != address(0), ZeroAddress());
        require(address(_to) != address(0), ZeroAddress());

        _token.safeTransferFrom(address(this), _to, _tokenId);

        emit EmergencyWithdrawnERC721(address(_token), _to, _tokenId);
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

    function setTreasury(ITreasury _treasury) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(address(_treasury) != address(0), ZeroAddress());
        treasury = _treasury;
        emit TreasurySet(address(_treasury));
    }

    function setReferralCode(address _referralCode) public onlyRole(DEFAULT_ADMIN_ROLE) {
        referralCode = _referralCode;
        emit ReferralCodeSet(_referralCode);
    }
}
