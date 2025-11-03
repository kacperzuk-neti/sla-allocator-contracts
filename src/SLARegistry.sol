// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title SLA Registry
 * @notice
 */
contract SLARegistry is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    /**
     * @notice Upgradable role which allows for contract upgrades
     */
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /**
     * @notice Mapping of client to provider to SLA parameters
     * @dev The key is a tuple of client and provider addresses
     * @dev The value is a struct containing the SLA parameters
     */
    mapping(address client => mapping(address provider => SLAParams)) public sla;

    /**
     * @notice Event emitted when a new SLA is registered for a given client and provider
     * @param client The client address
     * @param provider The provider address
     */
    event SLARegistered(address indexed client, address indexed provider);

    /**
     * @notice Error emitted when a SLA is already registered for a given client and provider
     * @param client The client address
     * @param provider The provider address
     */
    error SLAAlreadyRegistered(address client, address provider);

    /**
     * @notice Struct containing the SLA deal parameters
     */
    struct SLAParams {
        uint16 availability;
        uint16 retrievability;
        uint16 activationTime;
        uint64 termDays;
        uint64 sizeGiB;
    }

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

    /**
     * @notice Register a new SLA for a given client and provider
     * @param client The client address
     * @param provider The provider address
     * @param slaParams The SLA deal parameters
     */
    function registerSLA(address client, address provider, SLAParams memory slaParams)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _checkSLARegistered(client, provider);
        sla[client][provider] = slaParams;
        emit SLARegistered(client, provider);
    }

    /**
     * @notice Check if a SLA is already registered for a given client and provider
     * @param client The client address
     * @param provider The provider address
     * @dev Will revert if a SLA is already registered for the given client and provider
     */
    function _checkSLARegistered(address client, address provider) private view {
        if (sla[client][provider].availability != 0) {
            revert SLAAlreadyRegistered(client, provider);
        }
    }

    // solhint-disable no-empty-blocks
    /**
     * @notice Internal function used to implement new logic and check if upgrade is authorized
     * @dev Will revert (reject upgrade) if upgrade isn't called by UPGRADER_ROLE
     * @param newImplementation Address of new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    // solhint-enable no-empty-blocks

    /**
     * @notice Retrieves the score for a given provider.
     * @dev Returns the mocked score for a given provider.
     * @param provider The address of the provider.
     * @return The mocked score of the provider.
     */
    function score(address provider) public pure returns (uint256) {
        if (provider == address(0x123)) {
            return 75;
        }
        if (provider == address(0x456)) {
            return 35;
        }
        return 95;
    }
}
