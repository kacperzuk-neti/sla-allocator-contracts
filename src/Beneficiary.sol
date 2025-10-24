// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract Beneficiary is Initializable, AccessControlUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function initialize(address provider) public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, provider);
    }
}
