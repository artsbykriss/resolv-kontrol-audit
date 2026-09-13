// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @dev Configurable UsrPriceStorage mock.
contract MockUsrPriceStorage {
    uint256 public constant PRICE_SCALING_FACTOR = 1e18;
    uint256 public p;
    uint256 public ts;

    function set(uint256 _p, uint256 _ts) external {
        p = _p;
        ts = _ts;
    }

    function lastPrice() external view returns (uint256, uint256, uint256, uint256) {
        return (p, 0, 0, ts);
    }

    function prices(bytes32) external view returns (uint256, uint256, uint256, uint256) {
        return (p, 0, 0, ts);
    }
}
