// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Stand-in for the Resolv `Treasury` surface used by the redemption extension:
///      `aaveBorrow` (funds shortfall) and `increaseAllowance` (grants the extension allowance).
contract MockTreasury {
    mapping(bytes32 => bool) public borrowed;
    mapping(bytes32 => uint256) public borrowedAmount;

    function aaveBorrow(bytes32 id, address token, uint256 amount, uint256) external {
        require(!borrowed[id], "replay");
        borrowed[id] = true;
        borrowedAmount[id] = amount;
        // simulate Aave pulling liquidity: mint the shortfall to the treasury
        MockUSRMintable(token).mint(address(this), amount);
    }

    function increaseAllowance(bytes32, IERC20 token, address spender, uint256 amount) external {
        token.approve(spender, amount);
    }
}

interface MockUSRMintable {
    function mint(address to, uint256 amt) external;
}
