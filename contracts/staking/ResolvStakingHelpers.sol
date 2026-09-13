// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IDefaultErrors} from "../interfaces/IDefaultErrors.sol";
import {ResolvStakingStructs} from "./libraries/ResolvStakingStructs.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

interface IResolvStaking {

    function getUserStakeAgeInfo(address _user) external view returns (ResolvStakingStructs.StakeAgeInfo memory);

    function getUserEffectiveBalance(address _user) external view returns (uint256 balance);

    function getUserAccumulatedRewardPerToken(address _user, address _token) external view returns (uint256 amount);

    function getUserClaimableAmounts(address _user, address _token) external view returns (uint256 amount);

    function rewardTokens() external view returns (address[] memory);

    function getReward(address _token) external view returns (ResolvStakingStructs.Reward memory reward);

    function totalEffectiveSupply() external view returns (uint256);
}

contract ResolvStakingHelpers is IDefaultErrors {

    IResolvStaking public immutable STAKING;

    constructor(IResolvStaking _staking) {
        require(address(_staking) != address(0), ZeroAddress());
        STAKING = _staking;
    }

    function getPendingClaimableReward(
        address _user,
        address _token
    ) external view returns (uint256 amount) {
        uint256 stakedBalance = IERC20(address(STAKING)).balanceOf(_user);

        ResolvStakingStructs.Reward memory reward = STAKING.getReward(_token);
        uint256 accRewardPerToken = reward.accumulatedRewardPerToken;
        uint256 lastUpdate = Math.min(block.timestamp, reward.periodFinish);
        if (lastUpdate - reward.lastUpdate != 0 && STAKING.totalEffectiveSupply() != 0) {
            accRewardPerToken += reward.rewardRate * (lastUpdate - reward.lastUpdate) / STAKING.totalEffectiveSupply();
        }

        uint256 effectiveBalance = STAKING.getUserEffectiveBalance(_user);
        uint256 userBalance = effectiveBalance == 0 ? stakedBalance : effectiveBalance;
        uint256 userAccReward = STAKING.getUserAccumulatedRewardPerToken(_user, _token);
        uint256 newClaimable = 0;
        if (userAccReward < accRewardPerToken) {
            newClaimable = userBalance * (accRewardPerToken - userAccReward)
                / ResolvStakingStructs.REWARD_RATE_SCALE_FACTOR;
        }

        return STAKING.getUserClaimableAmounts(_user, _token) + newClaimable;
    }

    function getProjectedEffectiveBalance(
        address _user,
        int256 _delta
    ) external view returns (uint256 boostFactor, uint256 effectiveBalance) {
        ResolvStakingStructs.StakeAgeInfo memory stakeAgeInfo = STAKING.getUserStakeAgeInfo(_user);
        uint256 stakedBalance = IERC20(address(STAKING)).balanceOf(_user);
        // slither-disable-next-line incorrect-equality
        if (stakedBalance == 0) {
            return (ResolvStakingStructs.BOOST_FIXED_POINT, 0);
        }

        uint256 elapsed = block.timestamp - stakeAgeInfo.lastUpdate;
        uint256 totalAccumulated = stakeAgeInfo.totalAccumulated + (stakedBalance * elapsed);
        uint256 newStakedBalance = _delta >= 0
            ? stakedBalance + SafeCast.toUint256(_delta)
            : stakedBalance - SafeCast.toUint256(- _delta);

        if (_delta > 0) {
            totalAccumulated += SafeCast.toUint256(_delta);
        } else if (_delta < 0) {
            totalAccumulated = (totalAccumulated * newStakedBalance) / stakedBalance;
        }

        uint256 avgAge = newStakedBalance > 0 ? totalAccumulated / newStakedBalance : 0;
        uint256 wahp = avgAge * ResolvStakingStructs.BOOST_FIXED_POINT / ResolvStakingStructs.ONE_YEAR;
        boostFactor = Math.min(
            ResolvStakingStructs.BOOST_FIXED_POINT + wahp,
            2 * ResolvStakingStructs.BOOST_FIXED_POINT
        );
        effectiveBalance = newStakedBalance * boostFactor / ResolvStakingStructs.BOOST_FIXED_POINT;

        return (boostFactor, effectiveBalance);
    }
}
