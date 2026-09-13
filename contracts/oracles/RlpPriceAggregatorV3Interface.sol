// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {IRlpPriceAggregatorV3Interface} from "../interfaces/oracles/IRlpPriceAggregatorV3Interface.sol";
import {IRlpPriceStorage} from "../interfaces/IRlpPriceStorage.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/*
 @title Price feed contract that partially implements AggregatorV3Interface
 @notice This contract wraps the RlpPriceStorage feed
*/
contract RlpPriceAggregatorV3Interface is IRlpPriceAggregatorV3Interface, Ownable2StepUpgradeable {

    uint8 internal constant RLP_PRICE_DECIMALS = 18;
    IRlpPriceStorage public rlpPriceStorage;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*
       @dev Rounds IDs are returned as `0` as invalid round IDs.
    */
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        roundId = answeredInRound = 0;

        (uint256 price, uint256 timestamp) = rlpPriceStorage.lastPrice();
        answer = SafeCast.toInt256(price / 10 ** (RLP_PRICE_DECIMALS - decimals()));
        startedAt = updatedAt = timestamp;

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    function description() external pure returns (string memory value) {
        return "RLP Price AggregatorV3 interface";
    }

    /*
      @dev Custom version number to distinguish from Chainlink feeds.
    */
    function version() external pure returns (uint256 value) {
        return 879;
    }

    /*
      @dev Functions that use the round ID as an argument are not supported.
    */
    /* solhint-disable named-return-values */
    function getRoundData(uint80) external pure returns (uint80, int256, uint256, uint256, uint80) {
        revert FunctionIsNotSupported();
    }
    /* solhint-enable named-return-values */

    function initialize(IRlpPriceStorage _rlpPriceStorage) public initializer {
        __Ownable_init(msg.sender);
        setRlpPriceStorage(_rlpPriceStorage);
    }

    function setRlpPriceStorage(IRlpPriceStorage _rlpPriceStorage) public onlyOwner {
        if (address(_rlpPriceStorage) == address(0)) revert ZeroAddress();
        rlpPriceStorage = _rlpPriceStorage;
        emit RlpPriceStorageSet(address(_rlpPriceStorage));
    }

    function decimals() public pure returns (uint8 value) {
        return 8;
    }
}
