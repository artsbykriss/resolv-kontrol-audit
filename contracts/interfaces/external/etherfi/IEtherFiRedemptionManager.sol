// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IEtherFiRedemptionManager {

    function redeemWeEth(uint256 _weEthAmount, address _receiver) external;

    function exitFeeInBps() external view returns (uint16);
}
