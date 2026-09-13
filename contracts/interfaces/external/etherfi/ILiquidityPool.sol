// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ILiquidityPool {

    function deposit(address _referral) external payable returns (uint256);

    function requestWithdraw(address _recipient, uint256 _amount) external returns (uint256);

    function sharesForAmount(uint256 _amount) external view returns (uint256);

    function sharesForWithdrawalAmount(uint256 _amount) external view returns (uint256);

    function amountForShare(uint256 _share) external view returns (uint256);
}
