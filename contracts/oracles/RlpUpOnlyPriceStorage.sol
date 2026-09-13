// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRlpPriceStorage} from "../interfaces/IRlpPriceStorage.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";

contract RlpUpOnlyPriceStorage is IRlpPriceStorage, AccessControlDefaultAdminRulesUpgradeable {

    bytes32 public constant SERVICE_ROLE = keccak256("SERVICE_ROLE");
    uint256 public constant BOUND_PERCENTAGE_DENOMINATOR = 1e18;

    mapping(bytes32 key => Price price) public prices;
    Price public lastPrice;

    uint256 public upperBoundPercentage;
    uint256 public lowerBoundPercentage;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function setPrice(bytes32 _key, uint256 _price) external onlyRole(SERVICE_ROLE) {
        require(_key != bytes32(0), InvalidKey());
        require(_price != 0, InvalidPrice());
        require(prices[_key].timestamp == 0, PriceAlreadySet(_key));

        uint256 lastPriceValue = lastPrice.price;
        uint256 priceValue = _price;

        if (lastPriceValue != 0) {
            uint256 upperBound = lastPriceValue + (lastPriceValue * upperBoundPercentage / BOUND_PERCENTAGE_DENOMINATOR);
            if (_price < lastPriceValue) {
                priceValue = lastPriceValue;
            } else {
                require(_price <= upperBound, InvalidPriceRange(_price, lastPriceValue, upperBound));
            }
        }

        uint256 currentTime = block.timestamp;
        Price memory price = Price({
            price: priceValue,
            timestamp: currentTime
        });
        prices[_key] = price;
        lastPrice = price;

        emit PriceSet(_key, priceValue, currentTime);
    }

    function initialize(
        uint256 _upperBoundPercentage
    ) public initializer {
        __AccessControlDefaultAdminRules_init(1 days, msg.sender);
        setUpperBoundPercentage(_upperBoundPercentage);
        setLowerBoundPercentage(0);
    }

    function setUpperBoundPercentage(uint256 _upperBoundPercentage) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_upperBoundPercentage > 0 && _upperBoundPercentage <= BOUND_PERCENTAGE_DENOMINATOR, InvalidUpperBoundPercentage());
        upperBoundPercentage = _upperBoundPercentage;
        emit UpperBoundPercentageSet(_upperBoundPercentage);
    }

    function setLowerBoundPercentage(uint256 _lowerBoundPercentage) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_lowerBoundPercentage == 0, InvalidLowerBoundPercentage());
        lowerBoundPercentage = _lowerBoundPercentage;
        emit LowerBoundPercentageSet(_lowerBoundPercentage);
    }

}
