// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library ResolvStakingEvents {
    event RewardAdded(address indexed _token);
    event RewardsReceiverSet(address indexed _user, address indexed _receiver);
    event CheckpointDelegateeSet(address indexed _user, address indexed _delegatee);
    event RewardTokenDeposited(address indexed _token, uint256 _amount);
    event EmergencyWithdrawnERC20(address indexed _token, address indexed _to, uint256 _amount);
    event Deposited(address indexed _user, address indexed _receiver, uint256 _amount);
    event Withdrawn(address indexed _user, address indexed _receiver, uint256 _amount, bool _claimRewards);
    event WithdrawalInitiated(address indexed _user, uint256 _amount);
    event WithdrawalCooldownSet(uint256 newCooldown);
    event ClaimEnabledSet(bool enabled);
    event TransferEnabledSet(bool enabled);
}
