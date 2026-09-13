// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ResolvStakingStructs} from "../../staking/libraries/ResolvStakingStructs.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IResolvStaking {

    function depositWithPermit(
        uint256 _amount,
        address _receiver,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external;

    function deposit(
        uint256 _amount,
        address _receiver
    ) external;

    function withdraw(
        bool _claimRewards,
        address _receiver
    ) external;

    function initiateWithdrawal(uint256 _amount) external;

    function claim(address _user, address _receiver) external;

    function updateCheckpoint(address _user) external;

    function depositReward(
        address _token,
        uint256 _amount,
        uint256 _duration
    ) external;

    function setRewardsReceiver(address _receiver) external;

    function setCheckpointDelegatee(address _delegatee) external;

    function addRewardToken(IERC20 _token) external;

    function emergencyWithdrawERC20(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external;

    function setClaimEnabled(bool _enabled) external;

    function setWithdrawalCooldown(uint256 _cooldown) external;

    function getUserAccumulatedRewardPerToken(address _user, address _token) external view returns (uint256 amount);

    function getUserClaimableAmounts(address _user, address _token) external view returns (uint256 amount);

    function getUserStakeAgeInfo(address _user) external view returns (ResolvStakingStructs.StakeAgeInfo memory info);

    function getUserEffectiveBalance(address _user) external view returns (uint256 balance);

    function getReward(address _token) external view returns (ResolvStakingStructs.Reward memory reward);
}
