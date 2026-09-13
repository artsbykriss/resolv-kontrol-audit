// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library ResolvStakingErrors {
    error RewardTokenAlreadyAdded(address _token);
    error RewardTokenNotFound(address _token);
    error InsufficientRewardBalance();
    error InsufficientBalance();
    error InvalidWithdrawalCooldown();
    error WithdrawalRequestNotFound();
    error CooldownNotMet();
    error InvalidAmount();
    error ZeroAddress();
    error InvalidDuration();
    error NonTransferable();
    error ZeroTotalEffectiveSupply();
    error InvalidCheckpointCaller();
    error ClaimNotEnabled();
}
