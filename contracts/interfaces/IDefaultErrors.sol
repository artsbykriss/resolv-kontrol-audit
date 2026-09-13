// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IDefaultErrors {

    error IdempotencyKeyAlreadyExist(bytes32 _idempotencyKey);
    error InvalidAmount(uint256 _amount);
    error TooSmallAmount(uint256 _amount);
    error ZeroAddress();
    error InvalidRequest(uint256 _requestId);

}
