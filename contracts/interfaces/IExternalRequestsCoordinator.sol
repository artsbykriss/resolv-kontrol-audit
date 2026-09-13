// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

interface IExternalRequestsCoordinator {

    event MintCompleted(
        bytes32 indexed _idempotencyKey,
        uint256 indexed _requestId,
        address indexed _manager,
        uint256 _mintAmount,
        bool _isProtocolToken
    );

    event BurnCompleted(
        bytes32 indexed _idempotencyKey,
        uint256 indexed _requestId,
        address indexed _manager,
        uint256 _withdrawalAmount,
        bool _isProtocolToken
    );

    event RlpManagerSet(address _manager);
    event UsrManagerSet(address _manager);

    error ZeroAddress();
    error InvalidToken(address _token);
    error InvalidManager(address _manager);
    error ManagerPaused(address _manager);

    function completeMint(
        bytes32 _idempotencyKey,
        uint256 _id,
        address _token,
        uint256 _mintAmount
    ) external;

    function completeBurn(
        bytes32 _idempotencyKey,
        uint256 _id,
        address _token,
        uint256 _withdrawalAmount
    ) external;

    function setRlpManager(address _manager) external;
    function setUsrManager(address _manager) external;
}
