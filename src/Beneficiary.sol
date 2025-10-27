// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title Beneficiary
 * @notice Upgradeable contract for managing beneficiaries with role-based access control
 * @dev This contract is designed to be deployed as a proxy contract
 */
contract Beneficiary is Initializable, AccessControlUpgradeable {
    /**
     * @notice Disabled constructor (proxy pattern)
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Contract initializator. Should be called during deployment
     * @param provider Address of the storage provider
     */
    function initialize(address provider) public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, provider);
    }
}
