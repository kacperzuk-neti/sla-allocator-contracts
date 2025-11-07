// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";

/**
 * @title SLI Oracle
 * @notice
 */
contract SLIOracle is Initializable, AccessControlUpgradeable, UUPSUpgradeable, MulticallUpgradeable {
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
        uint32 latency; // TTFB in milliseconds
        uint16 retention; // ??
        uint16 bandwidth; // Mbps
        uint16 stability; // ??
        uint8 availability; // 0-100, %
        uint8 indexing; // 0-100, %
    }
    /**
     * @notice Mapping of provider IDs to their SLI attestations
     */
    mapping(CommonTypes.FilActorId provider => SLIAttestation attestation) public attestations;

    /**
     * @notice Emitted when SLI values are updated for a provider
     * @param provider ID of the provider
     * @param slis New SLI values
     */
    event SLIAttestationUpdate(CommonTypes.FilActorId indexed provider, SLIAttestation indexed slis);

    /**
     * @notice Disabled constructor (proxy pattern)
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Contract initializator. Should be called during deployment
     * @param admin Contract owner
     * @param oracle Address that will get ORACLE_ROLE
     */
    function initialize(address admin, address oracle) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __Multicall_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        _grantRole(ORACLE_ROLE, oracle);
    }

    /**
     * @notice Sets SLI values for a provider
     * @param provider ID of the provider
     * @param slis New SLI values
     */
    function setSLI(CommonTypes.FilActorId provider, SLIAttestation calldata slis) external onlyRole(ORACLE_ROLE) {
        emit SLIAttestationUpdate(provider, slis);
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
