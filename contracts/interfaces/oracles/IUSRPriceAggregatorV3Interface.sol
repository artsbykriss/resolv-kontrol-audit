// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IDefaultErrors} from "../IDefaultErrors.sol";
import {IUsrPriceStorage} from "../IUsrPriceStorage.sol";

interface IUSRPriceAggregatorV3Interface is AggregatorV3Interface, IDefaultErrors {

    event UsrPriceStorageSet(address usrPriceStorage);

    error FunctionIsNotSupported();

    function setUsrPriceStorage(IUsrPriceStorage _usrPriceStorage) external;

}
