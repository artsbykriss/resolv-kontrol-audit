// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20VotesUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {NoncesUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IResolvStaking} from "../interfaces/staking/IResolvStaking.sol";
import {ResolvStakingStructs} from "./libraries/ResolvStakingStructs.sol";
import {ResolvStakingErrors} from "./libraries/ResolvStakingErrors.sol";
import {ResolvStakingEvents} from "./libraries/ResolvStakingEvents.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ResolvStakingCheckpoints} from "./libraries/ResolvStakingCheckpoints.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IResolvStakingSilo} from "../interfaces/staking/IResolvStakingSilo.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title ResolvStaking
 * @notice A staking contract that accepts RESOLV tokens and distributes rewards to stakers.
 */
/// @custom:oz-upgrades-unsafe-allow external-library-linking
contract ResolvStaking is IResolvStaking, ERC20PermitUpgradeable, ERC20VotesUpgradeable, AccessControlDefaultAdminRulesUpgradeable, ReentrancyGuardUpgradeable {

    using SafeERC20 for IERC20;
    using ResolvStakingCheckpoints for mapping(address user => ResolvStakingStructs.UserData);

    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    uint256 internal constant MAX_WITHDRAWAL_COOLDOWN = 33 days;

    /// @notice Length of time over which rewards sent to this contract are distributed to stakers.
    uint256 public constant REWARD_DURATION = 14 days;

    /// @notice The RESOLV token that is staked.
    IERC20 public stakeToken;
    /// @notice The total effective supply of staked tokens (with WAHP applied).
    uint256 public totalEffectiveSupply;
    /// @notice Temporary tokens silo for pending withdrawals.
    IResolvStakingSilo public silo;

    address[] public rewardTokens;
    mapping(address token => ResolvStakingStructs.Reward reward) public rewards;
    bool public claimEnabled;

    uint256 public withdrawalCooldown;
    mapping(address user => ResolvStakingStructs.UserData) public usersData;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function depositWithPermit(
        uint256 _amount,
        address _receiver,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        IERC20Permit resolvPermit = IERC20Permit(address(stakeToken));
        // the use of `try/catch` allows the permit to fail and makes the code tolerant to frontrunning.
        // solhint-disable-next-line no-empty-blocks
        try resolvPermit.permit(msg.sender, address(this), _amount, _deadline, _v, _r, _s) {} catch {}
        deposit(_amount, _receiver);
    }

    /**
     * @notice Withdraws staked tokens after the cooldown period.
     * @param _claimRewards If true, claims pending rewards during withdrawal.
     * @param _receiver The address to receive the withdrawn tokens.
     * @dev Requires a pending withdrawal request to exist and cooldown period to be met.
     */
    function withdraw(
        bool _claimRewards,
        address _receiver
    ) external nonReentrant {
        ResolvStakingStructs.PendingWithdrawal storage pendingWithdrawal = usersData[msg.sender].pendingWithdrawal;
        uint256 amount = pendingWithdrawal.amount;
        require(amount != 0, ResolvStakingErrors.WithdrawalRequestNotFound());
        require(block.timestamp >= pendingWithdrawal.cooldownEnd, ResolvStakingErrors.CooldownNotMet());

        checkpoint(msg.sender, _claimRewards, _receiver, 0);

        silo.withdraw(_receiver, amount);

        pendingWithdrawal.amount = 0;
        pendingWithdrawal.cooldownEnd = 0;

        emit ResolvStakingEvents.Withdrawn(msg.sender, _receiver, amount, _claimRewards);
    }

    /**
     * @notice Initiate a withdrawal of a specified amount of staked tokens.
     * @param _amount The amount of staked tokens to withdraw.
     * @dev The caller must have a balance of at least `_amount`
     */
    // slither-disable-next-line pess-unprotected-initialize
    function initiateWithdrawal(uint256 _amount) external nonReentrant {
        require(_amount > 0, ResolvStakingErrors.InvalidAmount());
        require(balanceOf(msg.sender) >= _amount, ResolvStakingErrors.InsufficientBalance());
        ResolvStakingStructs.UserData storage userData = usersData[msg.sender];

        checkpoint(msg.sender, false, address(0), - SafeCast.toInt256(_amount));

        userData.pendingWithdrawal.amount += _amount;
        userData.pendingWithdrawal.cooldownEnd = block.timestamp + withdrawalCooldown;
        _burn(msg.sender, _amount);
        stakeToken.safeTransfer(address(silo), _amount);

        emit ResolvStakingEvents.WithdrawalInitiated(msg.sender, _amount);
    }

    /**
     * @notice Claims rewards for the caller and sends them to the specified receiver.
     * @param _receiver The address to receive the rewards. If zero, uses the caller's default receiver.
     */
    function claim(address _user, address _receiver) external nonReentrant {
        require(msg.sender == _user || msg.sender == usersData[_user].checkpointDelegatee,
            ResolvStakingErrors.InvalidCheckpointCaller());
        checkpoint(_user, true, _receiver, 0);
    }

    /**
     * @notice Updates the user's reward checkpoint without claiming rewards.
     * @param _user The address of the user.
     */
    function updateCheckpoint(address _user) external nonReentrant {
        if (_user != address(0)) {
            require(msg.sender == _user || msg.sender == usersData[_user].checkpointDelegatee,
                ResolvStakingErrors.InvalidCheckpointCaller());
        }
        checkpoint(_user, false, address(0), 0);
    }

    /**
     * @notice Deposits a specified amount of reward tokens into the contract.
     * @param _token The address of the reward token to deposit.
     * @param _amount The amount of reward tokens to deposit.
     * @param _duration The duration over which the rewards will be distributed (If zero, uses the default REWARD_DURATION).
     * @dev Only callable by accounts with the DISTRIBUTOR_ROLE.
     *      Updates the reward rate and period finish for the reward token.
     */
    function depositReward(
        address _token,
        uint256 _amount,
        uint256 _duration
    ) external nonReentrant onlyRole(DISTRIBUTOR_ROLE) {
        require(_amount > 0, ResolvStakingErrors.InvalidAmount());
        require(totalEffectiveSupply > 0, ResolvStakingErrors.ZeroTotalEffectiveSupply());
        ResolvStakingStructs.Reward storage reward = rewards[_token];
        require(address(reward.token) != address(0), ResolvStakingErrors.RewardTokenNotFound(_token));
        require(_duration <= REWARD_DURATION, ResolvStakingErrors.InvalidDuration());
        uint256 duration = _duration == 0 ? REWARD_DURATION : _duration;

        checkpoint(address(0), false, address(0), 0);

        uint256 amountReceived = reward.token.balanceOf(address(this));
        reward.token.safeTransferFrom(msg.sender, address(this), _amount);
        amountReceived = reward.token.balanceOf(address(this)) - amountReceived;

        uint256 periodFinish = reward.periodFinish;
        if (block.timestamp >= periodFinish) {
            reward.rewardRate = amountReceived * ResolvStakingStructs.REWARD_RATE_SCALE_FACTOR / duration;
        } else {
            uint256 remainingReward = (periodFinish - block.timestamp) * reward.rewardRate;
            reward.rewardRate = (amountReceived * ResolvStakingStructs.REWARD_RATE_SCALE_FACTOR + remainingReward) / duration;
        }

        // This check doesn't guarantee that the contract has received sufficient rewards,
        // as it can't differentiate unclaimed staker rewards from the balance.
        // Although it helps avoid degenerate cases, it's insufficient on its own.
        require(
            reward.token.balanceOf(address(this)) * ResolvStakingStructs.REWARD_RATE_SCALE_FACTOR >= reward.rewardRate * duration,
            ResolvStakingErrors.InsufficientRewardBalance()
        );

        reward.lastUpdate = block.timestamp;
        reward.periodFinish = block.timestamp + duration;

        emit ResolvStakingEvents.RewardTokenDeposited(_token, _amount);
    }

    /**
     * @notice Set the rewards receiver for the caller.
     * @param _receiver The address to set as the rewards receiver.
     */
    function setRewardsReceiver(address _receiver) external {
        usersData[msg.sender].rewardReceiver = _receiver;
        emit ResolvStakingEvents.RewardsReceiverSet(msg.sender, _receiver);
    }

    /**
     * @notice Sets the checkpoint delegatee for the caller.
     * @param _delegatee The address to set as the delegatee.
     */
    function setCheckpointDelegatee(address _delegatee) external {
        usersData[msg.sender].checkpointDelegatee = _delegatee;
        emit ResolvStakingEvents.CheckpointDelegateeSet(msg.sender, _delegatee);
    }

    /**
     * @notice Adds a new reward token to the staking contract.
     * @param _token The reward token to add.
     */
    function addRewardToken(IERC20 _token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(address(_token) != address(0), ResolvStakingErrors.ZeroAddress());
        require(address(rewards[address(_token)].token) == address(0), ResolvStakingErrors.RewardTokenAlreadyAdded(address(_token)));

        rewardTokens.push(address(_token));
        rewards[address(_token)].token = _token;

        emit ResolvStakingEvents.RewardAdded(address(_token));
    }

    /**
     * @dev Allows the EMERGENCY_ROLE to emergency withdraw ERC20 tokens from the contract.
     * @param _token The ERC20 token contract address to withdraw.
     * @param _to The recipient address to receive the tokens.
     * @param _amount The amount of tokens to withdraw.
     */
    function emergencyWithdrawERC20(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external onlyRole(EMERGENCY_ROLE) {
        require(address(_token) != address(0), ResolvStakingErrors.ZeroAddress());
        require(address(_to) != address(0), ResolvStakingErrors.ZeroAddress());
        require(_amount > 0, ResolvStakingErrors.InvalidAmount());

        _token.safeTransfer(_to, _amount);

        emit ResolvStakingEvents.EmergencyWithdrawnERC20(address(_token), _to, _amount);
    }

    /**
     * @notice Sets the claimEnabled flag.
     * @param _enabled The new value for the claimEnabled flag.
     */
    function setClaimEnabled(bool _enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        claimEnabled = _enabled;
        emit ResolvStakingEvents.ClaimEnabledSet(_enabled);
    }

    function getUserAccumulatedRewardPerToken(address _user, address _token) external view returns (uint256 amount) {
        return usersData[_user].accumulatedRewardsPerToken[_token];
    }

    function getUserClaimableAmounts(address _user, address _token) external view returns (uint256 amount) {
        return usersData[_user].claimableAmounts[_token];
    }

    function getUserStakeAgeInfo(address _user) external view returns (ResolvStakingStructs.StakeAgeInfo memory info) {
        return usersData[_user].stakeAgeInfo;
    }

    function getUserEffectiveBalance(address _user) external view returns (uint256 balance) {
        return usersData[_user].effectiveBalance;
    }

    function getReward(address _token) external view returns (ResolvStakingStructs.Reward memory reward) {
        return rewards[_token];
    }

    /**
     * @notice Deposits RESOLV tokens for staking.
     * @param _amount The amount of tokens to deposit.
     * @param _receiver The address that will receive the staked tokens.
     * @dev Updates reward checkpoints before minting tokens.
     */
    function deposit(
        uint256 _amount,
        address _receiver
    ) public nonReentrant {
        require(_amount > 0, ResolvStakingErrors.InvalidAmount());
        require(_receiver != address(0), ResolvStakingErrors.ZeroAddress());

        checkpoint(_receiver, false, address(0), SafeCast.toInt256(_amount));

        stakeToken.safeTransferFrom(msg.sender, address(this), _amount);
        _mint(_receiver, _amount);

        emit ResolvStakingEvents.Deposited(msg.sender, _receiver, _amount);
    }

    function initialize(
        string memory _name,
        string memory _symbol,
        IERC20 _stakeToken,
        IResolvStakingSilo _silo,
        uint256 _withdrawalCooldown
    ) public initializer {
        __ERC20_init(_name, _symbol);
        __ERC20Permit_init(_name);
        __AccessControlDefaultAdminRules_init(1 days, msg.sender);
        __ReentrancyGuard_init();

        require(address(_stakeToken) != address(0), ResolvStakingErrors.ZeroAddress());
        require(address(_silo) != address(0), ResolvStakingErrors.ZeroAddress());
        stakeToken = _stakeToken;
        silo = _silo;

        setWithdrawalCooldown(_withdrawalCooldown);
    }

    /**
     * @notice Sets the withdrawal cooldown period.
     * @param _cooldown The new cooldown period.
     */
    function setWithdrawalCooldown(uint256 _cooldown) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_cooldown <= MAX_WITHDRAWAL_COOLDOWN, ResolvStakingErrors.InvalidWithdrawalCooldown());
        withdrawalCooldown = _cooldown;
        emit ResolvStakingEvents.WithdrawalCooldownSet(_cooldown);
    }

    function nonces(
        address owner
    ) public view virtual override(NoncesUpgradeable, ERC20PermitUpgradeable) returns (uint256) {
        return super.nonces(owner);
    }

    /**
     * @dev This function always reverts with a NonTransferable error.
     */
    function transfer(address, uint256) public pure override returns (bool) {
        revert ResolvStakingErrors.NonTransferable();
    }

    /**
     * @dev This function always reverts with a NonTransferable error.
     */
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert ResolvStakingErrors.NonTransferable();
    }

    /**
     * @notice Internal hook to update reward checkpoints when token balances change.
     * @param _from The address transferring tokens.
     * @param _to The address receiving tokens.
     * @param _value The amount of tokens being transferred.
     */
    function _update(
        address _from,
        address _to,
        uint256 _value
    ) internal override(ERC20VotesUpgradeable, ERC20Upgradeable) {
        super._update(_from, _to, _value);
    }

    /**
     * @notice Updates the reward checkpoints for a user.
     * @param _user The address of the user.
     * @param _claim If true, claims any pending rewards.
     * @param _rewardReceiver The address to receive rewards. If zero, uses the default receiver.
     * @param _delta The change in the staked balance (positive for deposits, negative for withdrawals).
     * @dev This function updates global reward indexes and user-specific reward data.
     */
    // slither-disable-start reentrancy-no-eth
    function checkpoint(
        address _user,
        bool _claim,
        address _rewardReceiver,
        int256 _delta
    ) internal {
        require(!_claim || claimEnabled, ResolvStakingErrors.ClaimNotEnabled());
        usersData.checkpoint(
            rewards,
            rewardTokens,
            ResolvStakingCheckpoints.CheckpointParams({
                user: _user,
                rewardReceiver: _rewardReceiver,
                totalSupply: totalSupply(),
                totalEffectiveSupply: totalEffectiveSupply,
                userStakedBalance: balanceOf(_user),
                claim: _claim
            }));
        totalEffectiveSupply = usersData.updateEffectiveBalance(
            ResolvStakingCheckpoints.UpdateEffectiveBalanceParams({
                user: _user,
                userStakedBalance: balanceOf(_user),
                delta: _delta,
                totalEffectiveSupply: totalEffectiveSupply
            }));
    }
    // slither-disable-end reentrancy-no-eth

}
