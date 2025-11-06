// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";
import {SLIOracle} from "./SLIOracle.sol";

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
    mapping(address client => mapping(CommonTypes.FilActorId provider => SLAParams)) public sla;

    /**
     * @notice SLIOracle instance
     */
    SLIOracle public oracle;

    /**
     * @notice Event emitted when a new SLA is registered for a given client and provider
     * @param client The client address
     * @param provider The provider ID
     */
    event SLARegistered(address indexed client, CommonTypes.FilActorId indexed provider);

    /**
     * @notice Error emitted when a SLA is already registered for a given client and provider
     * @param client The client address
     * @param provider The provider ID
     */
    error SLAAlreadyRegistered(address client, CommonTypes.FilActorId provider);

    /**
     * @notice Error emitted when trying to get a score for unregistered SLA
     * @param client The client address
     * @param provider The provider ID
     */
    error SLAUnknown(address client, CommonTypes.FilActorId provider);

    /**
     * @notice Struct containing the SLA deal parameters
     */
    struct SLAParams {
        uint16 availability;
        uint16 latency;
        uint16 indexing;
        uint16 retention;
        uint16 bandwidth;
        uint16 stability;
        bool registered;
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
     * @param oracle_ SLIOracle
     */
    function initialize(address admin, SLIOracle oracle_) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        oracle = oracle_;
    }

    /**
     * @notice Register a new SLA for a given client and provider
     * @param client The client address
     * @param provider The provider address
     * @param slaParams The SLA deal parameters
     */
    function registerSLA(address client, CommonTypes.FilActorId provider, SLAParams memory slaParams) public {
        _checkSLARegistered(client, provider);
        slaParams.registered = true;
        sla[client][provider] = slaParams;
        emit SLARegistered(client, provider);
    }

    /**
     * @notice Check if a SLA is already registered for a given client and provider
     * @param client The client address
     * @param provider The provider address
     * @dev Will revert if a SLA is already registered for the given client and provider
     */
    function _checkSLARegistered(address client, CommonTypes.FilActorId provider) private view {
        if (sla[client][provider].registered) {
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
     * @return The score of the provider.
     */
    function score(address client, CommonTypes.FilActorId provider) public view returns (uint256) {
        if (!sla[client][provider].registered) {
            revert SLAUnknown(client, provider);
        }

        (
            uint256 lastUpdate,
            /* uint16 availability */,
            /* uint16 latency */,
            /* uint16 indexing */,
            /* uint16 retention */,
            /* uint16 bandwidth */,
            /* uint16 stability */
        ) = oracle.attestations(provider);

        if (lastUpdate == 0) return 0;

        // FIXME

        return 1;
    }
}
