// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";
import {GetBeneficiary} from "./libs/GetBeneficiary.sol";

/**
 * @title SLA Allocator
 * @notice Upgradeable contract for SLA allocation with role-based access control
 * @dev This contract is designed to be deployed as a proxy contract
 */
contract SLAAllocator is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    /**
     * @notice Upgradable role which allows for contract upgrades
     */
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /**
     * @notice Disabled constructor (proxy pattern)
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Contract initializator. Should be called during deployment
     * @param admin Contract owner
     */
    function initialize(address admin) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
    }

    // solhint-disable no-unused-vars
    /**
     * @notice Grants DataCap to a client
     * @param clientId The Client actor ID
     * @param providerId The SP actor ID
     * @param amount The amount of datacap to grant
     */
    function grantDataCap(CommonTypes.FilActorId clientId, CommonTypes.FilActorId providerId, uint256 amount)
        public
        view
    {
        GetBeneficiary.getBeneficiaryWithChecks(providerId, true, true, true);
    }

    // solhint-disable no-empty-blocks
    /**
     * @notice Internal function used to implement new logic and check if upgrade is authorized
     * @dev Will revert (reject upgrade) if upgrade isn't called by UPGRADER_ROLE
     * @param newImplementation Address of new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
    // solhint-enable no-empty-blocks
}
