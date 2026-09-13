// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IResolvStaking} from "./IResolvStaking.sol";

interface IResolvStakingV2 is IResolvStaking {

    function setTransferEnabled(bool _enabled) external;

}
