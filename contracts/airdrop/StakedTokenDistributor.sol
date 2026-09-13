// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlDefaultAdminRules} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IStakedTokenDistributor} from "../interfaces/airdrop/IStakedTokenDistributor.sol";
import {IResolvStaking} from "../interfaces/staking/IResolvStaking.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";


contract StakedTokenDistributor is
    IStakedTokenDistributor,
    AccessControlDefaultAdminRules,
    Pausable
{
    using SafeERC20 for IERC20;

    IResolvStaking public immutable RESOLV_STAKING;

    address public immutable TOKEN;

    bytes32 public immutable MERKLE_ROOT;

    uint256 public immutable END_TIME;

    mapping(address => bool) public blacklist;

    mapping(uint256 => uint256) private claimedBitMap;

    constructor(
        address _token,
        bytes32 _merkleRoot,
        IResolvStaking _resolvStaking,
        uint256 _endTime
    ) AccessControlDefaultAdminRules(1 days, msg.sender) {
        require(_endTime > block.timestamp, EndTimeInPast());
        require(address(_token) != address(0), ZeroAddress());

        TOKEN = _token;
        MERKLE_ROOT = _merkleRoot;
        END_TIME = _endTime;
        RESOLV_STAKING = _resolvStaking;
        IERC20 token = IERC20(_token);
        token.safeIncreaseAllowance(address(_resolvStaking), type(uint256).max);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        Pausable._pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        Pausable._unpause();
    }

    function withdraw(address _reciever) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(address(_reciever) != address(0), ZeroAddress());
        require(block.timestamp > END_TIME, NoWithdrawDuringClaim());
        IERC20(TOKEN).safeTransfer(_reciever, IERC20(TOKEN).balanceOf(address(this)));
        Pausable._pause();
        emit Withdrawn(_reciever);
    }

    function addToBlacklist(
        address _user
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(address(_user) != address(0), ZeroAddress());
        blacklist[_user] = true;
        emit AddedToBlacklist(_user);
    }

    function removeFromBlacklist(
        address _user
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(address(_user) != address(0), ZeroAddress());
        blacklist[_user] = false;
        emit RemovedFromBlacklist(_user);
    }

    function claim(
        uint256 _index,
        uint256 _amount,
        bytes32[] calldata _merkleProof
    ) public override whenNotPaused {
        require(block.timestamp < END_TIME, ClaimWindowFinished());
        require(!blacklist[msg.sender], Blacklisted());
        require(!isClaimed(_index), AlreadyClaimed());

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(_index, msg.sender, _amount));

        require(MerkleProof.verify(_merkleProof, MERKLE_ROOT, node), InvalidProof());

        // Mark it claimed and send the token.
        _setClaimed(_index);

        RESOLV_STAKING.deposit(_amount, msg.sender);

        emit Claimed(_index, msg.sender, _amount);
    }

    function isClaimed(uint256 index) public view override returns (bool) {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = claimedBitMap[claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    function _setClaimed(uint256 index) private {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        claimedBitMap[claimedWordIndex] =
            claimedBitMap[claimedWordIndex] |
            (1 << claimedBitIndex);
    }

}
