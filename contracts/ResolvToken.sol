// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract ResolvToken is Initializable, ERC20PermitUpgradeable, AccessControlDefaultAdminRulesUpgradeable {

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory _name,
        string memory _symbol,
        address _initSupplyHolder,
        uint256 _initSupply
    ) public initializer {
        __ERC20_init(_name, _symbol);
        __ERC20Permit_init(_name);
        _mint(_initSupplyHolder, _initSupply);

        __AccessControlDefaultAdminRules_init(1 days, msg.sender);
    }
}
