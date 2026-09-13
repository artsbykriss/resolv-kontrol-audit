// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Minimal stand-in for the USR `SimpleToken` (role-free mint/burn + idempotent variants).
contract MockUSR is ERC20 {
    constructor() ERC20("Resolv USD", "USR") {}
    function decimals() public pure override returns (uint8) { return 18; }
    function mint(address to, uint256 amt) external { _mint(to, amt); }
    function mint(bytes32, address to, uint256 amt) external { _mint(to, amt); }
    function burn(address from, uint256 amt) external { _burn(from, amt); }
    function burn(bytes32, address from, uint256 amt) external { _burn(from, amt); }
}
