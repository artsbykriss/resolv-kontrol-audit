// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library ResolvStakingStructs {

    /**
     * @notice Stores information about a reward token.
     * @param token The reward token.
     * @param rewardRate The emission rate per second.
     * @param lastUpdate Timestamp of the last reward update.
     * @param periodFinish Timestamp when the current reward period ends.
     * @param accumulatedRewardPerToken Global accumulated reward per effective token (scaled by REWARD_DENOMINATOR).
     */
    struct Reward {
        IERC20 token;
        uint256 periodFinish;
        uint256 rewardRate;
        uint256 lastUpdate;
        uint256 accumulatedRewardPerToken;
    }

    /**
     * @notice Stores information about a withdrawal request.
     * @param amount The amount of tokens requested for withdrawal.
     * @param requestTime The timestamp when the withdrawal request was made.
     */
    struct PendingWithdrawal {
        uint256 amount;
        uint256 cooldownEnd;
    }

    /**
     * @notice Stores stake age data for a user.
     * @param totalAccumulated The accumulated "age" (in token-seconds) for the staked tokens.
     * @param lastUpdate Timestamp of the last age update.
     */
    struct StakeAgeInfo {
        uint256 totalAccumulated;
        uint256 lastUpdate;
    }

    /**
     * @notice Stores user-specific data.
     * @param rewardReceiver The address to receive rewards.
     * @param accumulatedRewardsPerToken Mapping of token addresses to accumulated reward per token.
     * @param claimableAmounts Mapping of token addresses to claimable amounts.
     * @param pendingWithdrawal The pending withdrawal request of the user.
     */
    struct UserData {
        address rewardReceiver;
        address checkpointDelegatee;
        mapping(address token => uint256 accRewardPerToken) accumulatedRewardsPerToken;
        mapping(address token => uint256 claimableAmount) claimableAmounts;
        StakeAgeInfo stakeAgeInfo;
        uint256 effectiveBalance;
        ResolvStakingStructs.PendingWithdrawal pendingWithdrawal;
    }

    /**
     * @notice Scale factor used in reward calculation math to reduce rounding errors caused by
     *         truncation during division.
     */
    uint256 internal constant REWARD_RATE_SCALE_FACTOR = 1e24;
    uint256 internal constant BOOST_FIXED_POINT = 1e18;
    uint256 internal constant ONE_YEAR = 365 days;

}
