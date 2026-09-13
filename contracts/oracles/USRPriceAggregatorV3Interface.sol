// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IUsrPriceStorage} from "../interfaces/IUsrPriceStorage.sol";
import {IUSRPriceAggregatorV3Interface} from "../interfaces/oracles/IUSRPriceAggregatorV3Interface.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/*
 @title Price feed contract that partially implements AggregatorV3Interface
 @notice This contract wraps the UsrPriceStorage feed
*/
contract USRPriceAggregatorV3Interface is IUSRPriceAggregatorV3Interface, Ownable2StepUpgradeable {

    uint8 internal constant USR_PRICE_DECIMALS = 18;
    IUsrPriceStorage public usrPriceStorage;

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

        // slither-disable-next-line unused-return
        (uint256 price,,,uint256 timestamp) = usrPriceStorage.lastPrice();
        answer = SafeCast.toInt256(price / 10 ** (USR_PRICE_DECIMALS - decimals()));
        startedAt = updatedAt = timestamp;

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    function description() external pure returns (string memory value) {
        return "USR Price AggregatorV3 interface";
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

    function initialize(IUsrPriceStorage _usrPriceStorage) public initializer {
        __Ownable_init(msg.sender);
        setUsrPriceStorage(_usrPriceStorage);
    }

    function setUsrPriceStorage(IUsrPriceStorage _usrPriceStorage) public onlyOwner {
        if (address(_usrPriceStorage) == address(0)) revert ZeroAddress();
        usrPriceStorage = _usrPriceStorage;
        emit UsrPriceStorageSet(address(_usrPriceStorage));
    }

    function decimals() public pure returns (uint8 value) {
        return 8;
    }
}
