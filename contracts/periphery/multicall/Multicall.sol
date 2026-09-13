// SPDX-License-Identifier: MIT
// solhint-disable avoid-low-level-calls
// slither-disable-start pess-arbitrary-call
pragma solidity ^0.8.28;

import {IMulticall} from "./IMulticall.sol";
import {AccessControlDefaultAdminRules} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

contract Multicall is IMulticall, AccessControlDefaultAdminRules {

    bytes32 public constant SERVICE_ROLE = keccak256("SERVICE_ROLE");

    constructor(address _initialDefaultAdmin) AccessControlDefaultAdminRules(1 days, _initialDefaultAdmin) {}

    function aggregate(
        Call[] calldata _calls
    ) external onlyRole(SERVICE_ROLE) returns (uint256 blockNumber, bytes[] memory returnData) {
        blockNumber = block.number;
        returnData = new bytes[](_calls.length);
        for (uint256 i = 0; i < _calls.length; i++) {
            (bool success, bytes memory ret) = _calls[i].target.call(_calls[i].callData);
            require(success, MulticallFailed(ret));
            returnData[i] = ret;
        }
    }

    function tryBlockAndAggregate(
        bool _requireSuccess,
        Call[] calldata _calls
    ) external returns (uint256 blockNumber, bytes32 blockHash, Result[] memory returnData) {
        blockNumber = block.number;
        blockHash = blockhash(block.number);
        returnData = tryAggregate(_requireSuccess, _calls);
    }

    function getBlockHash(uint256 _blockNumber) external view returns (bytes32 blockHash) {
        blockHash = blockhash(_blockNumber);
    }

    function getBlockNumber() external view returns (uint256 blockNumber) {
        blockNumber = block.number;
    }

    function getCurrentBlockGasLimit() external view returns (uint256 gaslimit) {
        gaslimit = block.gaslimit;
    }

    function getCurrentBlockTimestamp() external view returns (uint256 timestamp) {
        timestamp = block.timestamp;
    }

    function getEthBalance(address _address) external view returns (uint256 balance) {
        balance = _address.balance;
    }

    function tryAggregate(
        bool _requireSuccess,
        Call[] calldata _calls
    ) public onlyRole(SERVICE_ROLE) returns (Result[] memory returnData) {
        returnData = new Result[](_calls.length);
        for (uint256 i = 0; i < _calls.length; i++) {
            (bool success, bytes memory ret) = _calls[i].target.call(_calls[i].callData);
            require(!_requireSuccess || success, MulticallFailed(ret));

            returnData[i].success = success;
            returnData[i].returnData = ret;
        }
    }
}
// slither-disable-end pess-arbitrary-call
