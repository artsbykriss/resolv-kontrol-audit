// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IExternalRequestsCoordinator} from "./interfaces/IExternalRequestsCoordinator.sol";
import {ISimpleToken} from "./interfaces/ISimpleToken.sol";
import {ITreasury} from "./interfaces/ITreasury.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControlDefaultAdminRules} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

interface IExternalRequestsManager {
    enum State { CREATED, COMPLETED, CANCELLED }

    function completeMint(bytes32 _idempotencyKey, uint256 _id, uint256 _mintAmount) external;
    function completeBurn(bytes32 _idempotencyKey, uint256 _id, uint256 _withdrawalAmount) external;
    function treasuryAddress() external view returns (address);
    function paused() external view returns (bool);
    // solhint-disable-next-line style-guide-casing
    function ISSUE_TOKEN_ADDRESS() external view returns (address);

    function mintRequests(uint256 _id) external view returns (
        uint256 id,
        address provider,
        State state,
        uint256 amount,
        address token,
        uint256 minExpectedAmount
    );

    function burnRequests(uint256 _id) external view returns (
        uint256 id,
        address provider,
        State state,
        uint256 amount,
        address token,
        uint256 minExpectedAmount
    );
}

contract ExternalRequestsCoordinator is IExternalRequestsCoordinator, AccessControlDefaultAdminRules, Pausable {

    bytes32 public constant SERVICE_ROLE = keccak256("SERVICE_ROLE");

    ISimpleToken public immutable USR_TOKEN;
    ISimpleToken public immutable RLP_TOKEN;
    IExternalRequestsManager public rlpManager;
    IExternalRequestsManager public usrManager;

    constructor(
        address _usrToken,
        address _rlpToken,
        address _usrManager,
        address _rlpManager,
        address _admin
    ) AccessControlDefaultAdminRules(1 days, _admin) {
        require(_usrToken != address(0), ZeroAddress());
        require(_rlpToken != address(0), ZeroAddress());

        USR_TOKEN = ISimpleToken(_usrToken);
        RLP_TOKEN = ISimpleToken(_rlpToken);

        _setUsrManager(_usrManager);
        _setRlpManager(_rlpManager);
    }

    function setRlpManager(address _manager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setRlpManager(_manager);
    }

    function setUsrManager(address _manager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setUsrManager(_manager);
    }

    function completeMint(
        bytes32 _idempotencyKey,
        uint256 _id,
        address _token,
        uint256 _mintAmount
    ) external onlyRole(SERVICE_ROLE) whenNotPaused {
        IExternalRequestsManager manager = _getManagerByToken(_token);
        (address depositToken, uint256 depositAmount) = _getDepositInfo(manager, _id);

        manager.completeMint(_idempotencyKey, _id, _mintAmount);

        bool isProtocolToken = _isProtocolToken(depositToken);
        if (isProtocolToken) {
            ISimpleToken(depositToken).burn(_idempotencyKey, manager.treasuryAddress(), depositAmount);
        }

        emit MintCompleted(_idempotencyKey, _id, address(manager), _mintAmount, isProtocolToken);
    }

    function completeBurn(
        bytes32 _idempotencyKey,
        uint256 _id,
        address _token,
        uint256 _withdrawalAmount
    ) external onlyRole(SERVICE_ROLE) whenNotPaused {
        IExternalRequestsManager manager = _getManagerByToken(_token);
        address withdrawalToken = _getWithdrawalToken(manager, _id);
        address treasury = manager.treasuryAddress();

        bool isProtocolToken = _isProtocolToken(withdrawalToken);
        if (isProtocolToken) {
            ISimpleToken(withdrawalToken).mint(_idempotencyKey, treasury, _withdrawalAmount);
        }

        ITreasury(treasury).increaseAllowance(
            _idempotencyKey,
            IERC20(withdrawalToken),
            address(manager),
            _withdrawalAmount
        );

        manager.completeBurn(_idempotencyKey, _id, _withdrawalAmount);

        emit BurnCompleted(_idempotencyKey, _id, address(manager), _withdrawalAmount, isProtocolToken);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        Pausable._pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        Pausable._unpause();
    }

    function _setRlpManager(address _manager) internal {
        require(_manager != address(0), ZeroAddress());
        require(IExternalRequestsManager(_manager).ISSUE_TOKEN_ADDRESS() == address(RLP_TOKEN), InvalidManager(_manager));
        require(!IExternalRequestsManager(_manager).paused(), ManagerPaused(_manager));
        rlpManager = IExternalRequestsManager(_manager);
        emit RlpManagerSet(_manager);
    }

    function _setUsrManager(address _manager) internal {
        require(_manager != address(0), ZeroAddress());
        require(IExternalRequestsManager(_manager).ISSUE_TOKEN_ADDRESS() == address(USR_TOKEN), InvalidManager(_manager));
        require(!IExternalRequestsManager(_manager).paused(), ManagerPaused(_manager));
        usrManager = IExternalRequestsManager(_manager);
        emit UsrManagerSet(_manager);
    }

    function _getManagerByToken(address _token) internal view returns (IExternalRequestsManager) {
        if (_token == address(RLP_TOKEN)) {
            return rlpManager;
        } else if (_token == address(USR_TOKEN)) {
            return usrManager;
        } else {
            revert InvalidToken(_token);
        }
    }

    function _isProtocolToken(address _token) internal view returns (bool) {
        return _token == address(USR_TOKEN) || _token == address(RLP_TOKEN);
    }

    //slither-disable-next-line unused-return
    function _getDepositInfo(
        IExternalRequestsManager _manager,
        uint256 _id
    ) internal view returns (address token, uint256 amount) {
        (,,, amount, token,) = _manager.mintRequests(_id);
    }

    //slither-disable-next-line unused-return
    function _getWithdrawalToken(
        IExternalRequestsManager _manager,
        uint256 _id
    ) internal view returns (address token) {
        (,,,, token,) = _manager.burnRequests(_id);
    }
}
