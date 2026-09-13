// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IResolvStakingSilo {

    event Withdrawn(address indexed _to, uint256 _amount);
    event EmergencyWithdrawnERC20(address indexed _token, address indexed _to, uint256 _amount);

    error InvalidAmount();
    error ZeroAddress();
    error OnlyResolvStaking();

    function withdraw(address _to, uint256 _amount) external;
}
