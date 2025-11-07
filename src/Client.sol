// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";

/**
 * @title Client
 * @notice Upgradeable contract for managing client allowances with role-based access control
 */
contract Client is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    /**
     * @notice Allocator role which allows for increasing and decreasing allowances
     */
    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");

    /**
     * @notice Mapping of allowances for clients and providers using FilActorId
     */
    mapping(address client => mapping(CommonTypes.FilActorId provider => uint256 amount)) public allowances;

    /**
     * @notice Event emitted when an allowance is changed
     * @param client Client address
     * @param provider Provider fil actor id
     * @param allowanceBefore Allowance before the change
     * @param allowanceAfter Allowance after the change
     */
    event AllowanceChanged(
        address indexed client, CommonTypes.FilActorId indexed provider, uint256 allowanceBefore, uint256 allowanceAfter
    );

    /**
     * @notice Error emitted when the amount is zero
     */
    error AmountEqualsZero();

    /**
     * @notice Error emitted when the allowance is zero
     */
    error AlreadyZero();

    /**
     * @notice Disabled constructor (proxy pattern)
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Contract initializator. Should be called during deployment
     * @param admin Contract owner
     * @param allocator Address of the allocator contract that can increase and decrease allowances
     */
    function initialize(address admin, address allocator) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ALLOCATOR_ROLE, allocator);
    }

    /**
     * @notice Increases the allowance for a given client and provider
     * @param client Address of the client
     * @param provider Address of the provider
     * @param amount Amount to increase the allowance by
     * Emits an AllowanceChanged event
     */
    function increaseAllowance(address client, CommonTypes.FilActorId provider, uint256 amount)
        external
        onlyRole(ALLOCATOR_ROLE)
    {
        if (amount == 0) revert AmountEqualsZero();
        uint256 allowanceBefore = allowances[client][provider];
        allowances[client][provider] += amount;
        emit AllowanceChanged(client, provider, allowanceBefore, allowances[client][provider]);
    }

    /**
     * @notice Decreases the allowance for a given client and provider
     * @param client Address of the client
     * @param provider Address of the provider
     * @param amount Amount to decrease the allowance by
     * @dev If the amount is greater than the allowance, the allowance is set to 0
     * Emits an AllowanceChanged event
     */
    function decreaseAllowance(address client, CommonTypes.FilActorId provider, uint256 amount)
        external
        onlyRole(ALLOCATOR_ROLE)
    {
        if (amount == 0) revert AmountEqualsZero();
        uint256 allowanceBefore = allowances[client][provider];
        if (allowanceBefore == 0) {
            revert AlreadyZero();
        }
        if (allowanceBefore < amount) {
            amount = allowanceBefore;
        }
        allowances[client][provider] -= amount;
        emit AllowanceChanged(client, provider, allowanceBefore, allowances[client][provider]);
    }

    // solhint-disable no-empty-blocks
    /**
     * @notice Internal function used to implement new logic and check if upgrade is authorized
     * @dev Will revert (reject upgrade) if upgrade isn't called by DEFAULT_ADMIN_ROLE
     * @param newImplementation Address of new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
