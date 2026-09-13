// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IResolvStakingSilo} from "../interfaces/staking/IResolvStakingSilo.sol";
import {AccessControlDefaultAdminRules} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ResolvStakingSilo is IResolvStakingSilo, AccessControlDefaultAdminRules {
    using SafeERC20 for IERC20;

    bytes32 public constant RESOLV_STAKING_ROLE = keccak256("RESOLV_STAKING_ROLE");

    IERC20 public immutable RESOLV_TOKEN;

    constructor(IERC20 _resolvToken) AccessControlDefaultAdminRules(1 days, msg.sender) {
        require(address(_resolvToken) != address(0), ZeroAddress());
        RESOLV_TOKEN = _resolvToken;
    }

    function withdraw(address _to, uint256 _amount) external onlyRole(RESOLV_STAKING_ROLE) {
        RESOLV_TOKEN.safeTransfer(_to, _amount);

        emit Withdrawn(_to, _amount);
    }

    /**
     * @dev Allows the DEFAULT_ADMIN to emergency withdraw ERC20 tokens from the contract.
     * @param _token The ERC20 token contract address to withdraw.
     * @param _to The recipient address to receive the tokens.
     * @param _amount The amount of tokens to withdraw.
     */
    function emergencyWithdrawERC20(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(address(_token) != address(0), ZeroAddress());
        require(address(_to) != address(0), ZeroAddress());
        require(_amount != 0, InvalidAmount());

        _token.safeTransfer(_to, _amount);

        emit EmergencyWithdrawnERC20(address(_token), _to, _amount);
    }

}
