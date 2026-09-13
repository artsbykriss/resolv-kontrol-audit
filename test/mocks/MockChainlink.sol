// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @dev Configurable Chainlink oracle mock used by UsrRedemptionExtension.
contract MockChainlink {
    mapping(address => int256) public price;
    mapping(address => uint8) public priceDecimals;
    mapping(address => uint256) public updatedAt;

    function set(address token, int256 p, uint8 dec, uint256 ts) external {
        price[token] = p;
        priceDecimals[token] = dec;
        updatedAt[token] = ts;
    }

    function getLatestRoundData(address token) external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, price[token], 0, updatedAt[token], 1);
    }

    function getPrice(address token) external view returns (uint256) {
        return uint256(price[token]);
    }

    function quoteCurrency() external pure returns (address) {
        return address(0);
    }
}
