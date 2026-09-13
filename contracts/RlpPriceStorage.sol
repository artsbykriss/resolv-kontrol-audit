// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRlpPriceStorage} from "./interfaces/IRlpPriceStorage.sol";
import {AccessControlDefaultAdminRules} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

contract RlpPriceStorage is IRlpPriceStorage, AccessControlDefaultAdminRules {

    bytes32 public constant SERVICE_ROLE = keccak256("SERVICE_ROLE");
    uint256 public constant BOUND_PERCENTAGE_DENOMINATOR = 1e18;

    mapping(bytes32 key => Price price) public prices;
    Price public lastPrice;

    uint256 public upperBoundPercentage;
    uint256 public lowerBoundPercentage;

    constructor(
        uint256 _upperBoundPercentage,
        uint256 _lowerBoundPercentage
    ) AccessControlDefaultAdminRules(1 days, msg.sender) {
        setUpperBoundPercentage(_upperBoundPercentage);
        setLowerBoundPercentage(_lowerBoundPercentage);
    }

    function setPrice(bytes32 _key, uint256 _price) external onlyRole(SERVICE_ROLE) {
        if (_key == bytes32(0)) revert InvalidKey();
        if (_price == 0) revert InvalidPrice();
        if (prices[_key].timestamp != 0) revert PriceAlreadySet(_key);

        uint256 currentPrice = lastPrice.price;
        if (lastPrice.price != 0) {
            uint256 upperBound = currentPrice + (currentPrice * upperBoundPercentage / BOUND_PERCENTAGE_DENOMINATOR);
            uint256 lowerBound = currentPrice - (currentPrice * lowerBoundPercentage / BOUND_PERCENTAGE_DENOMINATOR);
            if (_price > upperBound || _price < lowerBound) {
                revert InvalidPriceRange(_price, lowerBound, upperBound);
            }
        }

        uint256 currentTime = block.timestamp;
        Price memory price = Price({
            price: _price,
            timestamp: currentTime
        });
        prices[_key] = price;
        lastPrice = price;

        emit PriceSet(_key, _price, currentTime);
    }

    function setUpperBoundPercentage(uint256 _upperBoundPercentage) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_upperBoundPercentage == 0
            || _upperBoundPercentage > BOUND_PERCENTAGE_DENOMINATOR) revert InvalidUpperBoundPercentage();

        upperBoundPercentage = _upperBoundPercentage;
        emit UpperBoundPercentageSet(_upperBoundPercentage);
    }

    function setLowerBoundPercentage(uint256 _lowerBoundPercentage) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_lowerBoundPercentage == 0
            || _lowerBoundPercentage > BOUND_PERCENTAGE_DENOMINATOR) revert InvalidLowerBoundPercentage();

        lowerBoundPercentage = _lowerBoundPercentage;
        emit LowerBoundPercentageSet(_lowerBoundPercentage);
    }

}
