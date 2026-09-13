// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMulticall {

    struct Call {
        address target;
        bytes callData;
    }

    struct Result {
        bool success;
        bytes returnData;
    }

    error MulticallFailed(bytes data);

    function aggregate(
        Call[] calldata _calls
    ) external returns (uint256 blockNumber, bytes[] memory returnData);

    function tryBlockAndAggregate(
        bool _requireSuccess,
        Call[] calldata _calls
    ) external returns (uint256 blockNumber, bytes32 blockHash, Result[] memory returnData);

    function tryAggregate(
        bool _requireSuccess,
        Call[] calldata _calls
    ) external returns (Result[] memory returnData);

    function getBlockHash(uint256 _blockNumber) external view returns (bytes32 blockHash);

    function getBlockNumber() external view returns (uint256 blockNumber);

    function getCurrentBlockGasLimit() external view returns (uint256 gaslimit);

    function getCurrentBlockTimestamp() external view returns (uint256 timestamp);

    function getEthBalance(address _address) external view returns (uint256 balance);

}
