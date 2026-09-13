// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRlpPriceStorage} from "../IRlpPriceStorage.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IDefaultErrors} from "../IDefaultErrors.sol";

interface IRlpPriceAggregatorV3Interface is AggregatorV3Interface, IDefaultErrors {

    event RlpPriceStorageSet(address rlpPriceStorage);

    error FunctionIsNotSupported();

    function setRlpPriceStorage(IRlpPriceStorage _rlpPriceStorage) external;

}
