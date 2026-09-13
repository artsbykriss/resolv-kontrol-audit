// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ResolvStakingStructs} from "./ResolvStakingStructs.sol";

/**
 * @title StakingCheckpoints Library
 * @notice Library for managing staking checkpoints, reward calculations, and effective balance updates.
 * @dev !IMPORTANT! Note that the OpenZeppelin Upgrades plugin does not control that the library is upgrade safe.
 *      Please review the code carefully and test it thoroughly before any upgrade.
 *      See: https://github.com/OpenZeppelin/openzeppelin-upgrades/issues/52
 */
library ResolvStakingCheckpoints {

    using SafeERC20 for IERC20;

    /**
     * @notice Parameters for updating staking checkpoints and rewards.
     * @param user The address of the user.
     * @param rewardReceiver The address to receive the reward tokens.
     * @param totalSupply The total supply of staked tokens.
     * @param totalEffectiveSupply The total effective balance of all users.
     * @param userStakedBalance The staked token balance of the user.
     * @param claim A flag indicating whether to claim rewards.
     */
    struct CheckpointParams {
        address user;
        address rewardReceiver;
        uint256 totalSupply;
        uint256 totalEffectiveSupply;
        uint256 userStakedBalance;
        bool claim;
    }

    /**
     * @notice Parameters for updating the effective balance of a user.
     * @param user The address of the user.
     * @param userStakedBalance The current staked balance of the user.
     * @param delta The change in the staked balance (positive for deposits, negative for withdrawals).
     * @param totalEffectiveSupply The total effective supply of all users.
     */
    struct UpdateEffectiveBalanceParams {
        address user;
        uint256 userStakedBalance;
        int256 delta;
        uint256 totalEffectiveSupply;
    }

    event RewardClaimed(address indexed _user, address indexed _receiver, address indexed _token, uint256 _amount);
    event EffectiveBalanceUpdated(address indexed _user, uint256 _effectiveBalance);

    /**
     * @notice Updates rewards data for a user across all reward tokens.
     * @dev Calculates new rewards per token based on elapsed time, updates user claimable rewards,
            and optionally transfers rewards.
     */
    function checkpoint(
        mapping(address user => ResolvStakingStructs.UserData) storage usersData,
        mapping(address token => ResolvStakingStructs.Reward reward) storage rewards,
        address[] storage rewardTokens,
        ResolvStakingCheckpoints.CheckpointParams memory _params
    ) external {
        ResolvStakingStructs.UserData storage userData = usersData[_params.user];
        address receiver = _params.rewardReceiver;
        uint256 userBalance = 0;

        if (_params.user != address(0)) {
            userBalance = userData.effectiveBalance == 0 ? _params.userStakedBalance : userData.effectiveBalance;
            if (_params.claim && receiver == address(0)) {
                // if receiver is not explicitly declared, check if a default receiver is set
                receiver = userData.rewardReceiver;
                if (receiver == address(0)) {
                    // if no default receiver is set, direct claims to the user
                    receiver = _params.user;
                }
            }
        }

        uint256 rewardTokensSize = rewardTokens.length;
        for (uint256 i = 0; i < rewardTokensSize; i++) {
            address token = rewardTokens[i];
            ResolvStakingStructs.Reward storage reward = rewards[token];

            updateRewardPerToken(reward, _params.totalEffectiveSupply);

            if (_params.user != address(0)) {
                uint256 userAccReward = userData.accumulatedRewardsPerToken[token];
                uint256 newClaimable = 0;
                if (userAccReward < reward.accumulatedRewardPerToken) {
                    userData.accumulatedRewardsPerToken[token] = reward.accumulatedRewardPerToken;
                    newClaimable = userBalance * (reward.accumulatedRewardPerToken - userAccReward)
                        / ResolvStakingStructs.REWARD_RATE_SCALE_FACTOR;
                }
                uint256 totalClaimable = userData.claimableAmounts[token] + newClaimable;
                if (totalClaimable > 0) {
                    if (_params.claim) {
                        uint256 transferred = safeRewardTransfer(token, receiver, totalClaimable);
                        userData.claimableAmounts[token] = totalClaimable > transferred ? totalClaimable - transferred : 0;

                        emit RewardClaimed(_params.user, receiver, token, transferred);
                    } else if (newClaimable > 0) {
                        userData.claimableAmounts[token] = totalClaimable;
                    }
                }
            }
        }
    }

    /**
     * @notice Updates the effective balance for a user's staking position.
     * @param usersData A mapping of user addresses to their staking data.
     * @param _params The parameters for updating the effective balance
     * @return newTotalEffectiveSupply The new total effective supply after updating the user's effective balance.
     * @dev Adjusts the stake age and calculates a future boost factor based on the elapsed staking time.
     */
    function updateEffectiveBalance(
        mapping(address user => ResolvStakingStructs.UserData) storage usersData,
        UpdateEffectiveBalanceParams memory _params
    ) external returns (uint256 newTotalEffectiveSupply) {
        if (_params.user == address(0)) {
            newTotalEffectiveSupply = _params.totalEffectiveSupply;
            return newTotalEffectiveSupply;
        }

        ResolvStakingStructs.UserData storage userData = usersData[_params.user];

        // If the user had no stake and this is first deposit,
        // just update lastUpdate and exit, for the proper calculation of elapsed time during the next deposit
        if (_params.userStakedBalance == 0) {
            userData.stakeAgeInfo.lastUpdate = block.timestamp;
            userData.effectiveBalance = 0;
            newTotalEffectiveSupply = _params.totalEffectiveSupply + SafeCast.toUint256(_params.delta);
            return newTotalEffectiveSupply;
        }

        uint256 elapsed = block.timestamp - userData.stakeAgeInfo.lastUpdate;
        userData.stakeAgeInfo.lastUpdate = block.timestamp;
        userData.stakeAgeInfo.totalAccumulated += _params.userStakedBalance * elapsed;

        // for deposits (delta >= 0), we add a baseline (here 1 second per new token) so that new tokens have a nonzero starting age.
        // for withdrawals (delta < 0), we scale down proportionally. this maintains the same average age for the tokens that remain staked
        uint256 newStakedBalance = _params.delta >= 0
            ? _params.userStakedBalance + SafeCast.toUint256(_params.delta)
            : _params.userStakedBalance - SafeCast.toUint256(- _params.delta);
        if (_params.delta > 0) {
            userData.stakeAgeInfo.totalAccumulated += SafeCast.toUint256(_params.delta);
        } else if (_params.delta < 0) {
            userData.stakeAgeInfo.totalAccumulated = (userData.stakeAgeInfo.totalAccumulated * newStakedBalance) / _params.userStakedBalance;
        }

        uint256 avgAge = newStakedBalance > 0 ? userData.stakeAgeInfo.totalAccumulated / newStakedBalance : 0;
        uint256 wahp = avgAge * ResolvStakingStructs.BOOST_FIXED_POINT / ResolvStakingStructs.ONE_YEAR;
        uint256 boostFactor = Math.min(
            ResolvStakingStructs.BOOST_FIXED_POINT + wahp,
            2 * ResolvStakingStructs.BOOST_FIXED_POINT
        );

        uint256 oldEffectiveBalance = userData.effectiveBalance == 0 ? _params.userStakedBalance : userData.effectiveBalance;
        uint256 newEffectiveBalance = newStakedBalance * boostFactor / ResolvStakingStructs.BOOST_FIXED_POINT;
        userData.effectiveBalance = newEffectiveBalance;

        newTotalEffectiveSupply = _params.totalEffectiveSupply + newEffectiveBalance - oldEffectiveBalance;

        emit EffectiveBalanceUpdated(_params.user, userData.effectiveBalance);

        return newTotalEffectiveSupply;
    }

    function updateRewardPerToken(
        ResolvStakingStructs.Reward storage reward,
        uint256 _totalEffectiveSupply
    ) internal {
        uint256 accRewardPerToken = reward.accumulatedRewardPerToken;
        uint256 lastUpdate = Math.min(block.timestamp, reward.periodFinish);

        if (lastUpdate - reward.lastUpdate != 0 && _totalEffectiveSupply != 0) {
            accRewardPerToken += reward.rewardRate * (lastUpdate - reward.lastUpdate) / _totalEffectiveSupply;
            reward.accumulatedRewardPerToken = accRewardPerToken;
            reward.lastUpdate = lastUpdate;
        }
    }

    /**
     * @notice Safely transfers reward tokens to a specified address.
     * @dev Transfers the lesser of _amount and the available balance to avoid reverting.
     * @param _token The reward token address.
     * @param _to The address to receive the tokens.
     * @param _amount The amount of tokens to transfer.
     * @return transferred The actual amount transferred.
     */
    function safeRewardTransfer(
        address _token,
        address _to,
        uint256 _amount
    ) internal returns (uint256 transferred) {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        transferred = _amount;
        if (transferred > balance) {
            transferred = balance;
        }

        IERC20(_token).safeTransfer(_to, transferred);
    }

}
