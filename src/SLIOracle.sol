// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title SLI Oracle
 * @notice
 */
contract SLIOracle is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    /**
     * @notice Upgradable role which allows for contract upgrades
     */
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /**
     * @notice Oracle role which allows to update SLI values
     */
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    /**
     * @notice Struct containing all SLI metrics for a provider and a block number it was last updated
     */
    struct SLIAttestation {
        uint256 lastUpdate;
        uint16 availability;
        uint16 latency;
        uint16 indexing;
        uint16 retention;
        uint16 bandwidth;
        uint16 stability;
    }
    /**
     * @notice Mapping of provider addresses to their SLI attestations
     */
    mapping(address provider => SLIAttestation attestation) public attestations;

    /**
     * @notice Emitted when SLI values are updated for a provider
     * @param provider Address of the provider
     * @param slis New SLI values
     */
    event SLIAttestationEvent(address indexed provider, SLIAttestation indexed slis);

    /**
     * @notice Disabled constructor (proxy pattern)
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Contract initializator. Should be called during deployment
     * @param admin Contract owner
     * @param oracle Address with ORACLE_ROLE
     */
    function initialize(address admin, address oracle) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        _grantRole(ORACLE_ROLE, oracle);
    }

    /**
     * @notice Sets SLI values for a provider
     * @param provider Address of the provider
     * @param slis New SLI values
     */
    function setSLI(address provider, SLIAttestation calldata slis) external onlyRole(ORACLE_ROLE) {
        emit SLIAttestationEvent(provider, slis);
        attestations[provider] = slis;
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
