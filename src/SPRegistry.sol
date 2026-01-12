// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title SPRegistry
 * @notice Standalone upgradeable contract for managing Storage Provider registry
 */
contract SPRegistry is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    /**
     * @notice Role identifier for allocators who can create storage entities
     */
    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");

    /**
     * @notice Storage entity struct
     */
    struct StorageEntity {
        bool isActive;
        address owner;
        uint64[] storageProviders;
        mapping(uint64 => ProviderDetails) providerDetails;
    }

    /**
     * @notice Provider details struct
     */
    struct ProviderDetails {
        bool isActive;
        uint256 spaceLeft;
    }

    /**
     * @notice Provider details view struct
     */
    struct ProviderDetailsView {
        bool isActive;
        uint64 providerId;
        uint256 spaceLeft;
    }

    /**
     * @notice Storage entity view struct
     */
    struct StorageEntityView {
        bool isActive;
        address owner;
        uint64[] storageProviders;
        ProviderDetailsView[] providerDetails;
    }

    /**
     * @notice Storage entities by owner address
     * @dev Storage entities by owner address
     */
    mapping(address entityOwner => StorageEntity entity) public storageEntities;

    /**
     * @notice Storage providers by ID
     * @dev Storage providers by ID
     */
    mapping(uint64 storageProvider => bool isUsed) public usedStorageProviders;

    /**
     * @notice Entity addresses
     */
    address[] public entityAddresses;

    /**
     * @notice Storage entity created event
     * @param creator The address that created the storage entity
     * @param entityOwner The owner address of the storage entity
     * @param storageProviders The storage providers associated with the storage entity
     */
    event StorageEntityCreated(address indexed creator, address indexed entityOwner, uint64[] storageProviders);

    /**
     * @notice Storage providers added event
     * @param creator The address that added the storage providers
     * @param storageEntity The storage entity that the storage providers were added to
     * @param addedStorageProviders The storage providers that were added
     */
    event StorageProvidersAdded(address indexed creator, address indexed storageEntity, uint64[] addedStorageProviders);

    /**
     * @notice Storage provider removed event
     * @param creator The address that removed the storage providers
     * @param storageEntity The storage entity that the storage providers were removed from
     * @param removedStorageProviders The storage providers that were removed
     */
    event StorageProviderRemoved(
        address indexed creator, address indexed storageEntity, uint64[] removedStorageProviders
    );

    /**
     * @notice Storage entity active status changed event
     * @param creator The address that changed the active status of the storage entity
     * @param storageEntity The storage entity that the active status was changed
     * @param isActive The new active status
     */
    event StorageEntityActiveStatusChanged(address indexed creator, address indexed storageEntity, bool isActive);

    error CallerIsNoOwnerOrStorageEntity();
    error CallerIsNotAdminOrAllocator();
    error StorageEntityAlreadyExists();
    error StorageProviderAlreadyUsed();
    error StorageEntityDoesNotExist();
    error StorageProviderNotAssignedToEntity();
    error InvalidZeroAddress();

    /**
     * @notice Initialize the SPRegistry contract
     * @param admin The address that will have the DEFAULT_ADMIN_ROLE
     */
    function initialize(address admin) public initializer {
        if (admin == address(0)) {
            revert InvalidZeroAddress();
        }
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ALLOCATOR_ROLE, admin);
    }

    /**
     * @notice Grant the ALLOCATOR_ROLE to an address
     * @param allocator The address to grant the role to
     */
    function grantAllocatorRole(address allocator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (allocator == address(0)) {
            revert InvalidZeroAddress();
        }
        _grantRole(ALLOCATOR_ROLE, allocator);
    }

    /**
     * @notice Revoke the ALLOCATOR_ROLE from an address
     * @param allocator The address to revoke the role from
     */
    function revokeAllocatorRole(address allocator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(ALLOCATOR_ROLE, allocator);
    }

    /**
     * @notice Create a new storage entity
     * @param entityOwner The owner address of the storage entity
     * @param storageProviders Array of storage provider IDs to associate with the entity
     */
    function createStorageEntity(address entityOwner, uint64[] calldata storageProviders)
        external
        onlyRole(ALLOCATOR_ROLE)
    {
        if (storageEntities[entityOwner].owner != address(0)) {
            revert StorageEntityAlreadyExists();
        }
        _ensureNoStorageProviderUsed(storageProviders);

        StorageEntity storage storageEntity = storageEntities[entityOwner];
        storageEntity.owner = entityOwner;
        storageEntity.storageProviders = storageProviders;
        storageEntity.isActive = true;

        entityAddresses.push(entityOwner);

        for (uint256 i = 0; i < storageProviders.length; i++) {
            usedStorageProviders[storageProviders[i]] = true;
        }

        emit StorageEntityCreated(msg.sender, entityOwner, storageProviders);
    }

    /**
     * @notice Add storage providers to an existing storage entity
     * @param entityOwner The owner address of the storage entity
     * @param storageProviders Array of storage provider IDs to add
     */
    function addStorageProviders(address entityOwner, uint64[] calldata storageProviders)
        external
        onlyRole(ALLOCATOR_ROLE)
    {
        _ensureNoStorageProviderUsed(storageProviders);

        StorageEntity storage se = storageEntities[entityOwner];
        _ensureStorageEntityExists(se);

        for (uint256 i = 0; i < storageProviders.length; i++) {
            se.storageProviders.push(storageProviders[i]);
            usedStorageProviders[storageProviders[i]] = true;
        }

        emit StorageProvidersAdded(msg.sender, entityOwner, storageProviders);
    }

    /**
     * @notice Remove storage providers from a storage entity
     * @param entityOwner The owner address of the storage entity
     * @param storageProviders Array of storage provider IDs to remove
     */
    function removeStorageProviders(address entityOwner, uint64[] calldata storageProviders)
        external
        onlyRole(ALLOCATOR_ROLE)
    {
        StorageEntity storage se = storageEntities[entityOwner];
        _ensureStorageEntityExists(se);

        for (uint256 j = 0; j < storageProviders.length; j++) {
            uint64 sp = storageProviders[j];
            _ensureStorageProviderIsAssignedToStorageEntity(se, sp);

            usedStorageProviders[sp] = false;
            for (uint256 i = 0; i < se.storageProviders.length; i++) {
                if (se.storageProviders[i] == sp) {
                    se.storageProviders[i] = se.storageProviders[se.storageProviders.length - 1];
                    se.storageProviders.pop();
                    se.providerDetails[sp] = ProviderDetails({isActive: false, spaceLeft: 0});
                    break;
                }
            }
        }

        emit StorageProviderRemoved(msg.sender, entityOwner, storageProviders);
    }

    /**
     * @notice Set the active status of a storage entity
     * @param entityOwner The owner address of the storage entity
     * @param isActive The new active status
     */
    function setStorageEntityActiveStatus(address entityOwner, bool isActive) external onlyRole(ALLOCATOR_ROLE) {
        StorageEntity storage se = storageEntities[entityOwner];
        _ensureStorageEntityExists(se);

        se.isActive = isActive;

        emit StorageEntityActiveStatusChanged(msg.sender, entityOwner, isActive);
    }

    /**
     * @notice Set details for a specific storage provider
     * @param entityOwner The owner address of the storage entity
     * @param storageProvider The storage provider ID
     * @param details The provider details to set
     */
    function setStorageProviderDetails(address entityOwner, uint64 storageProvider, ProviderDetails calldata details)
        external
        onlyRole(ALLOCATOR_ROLE)
    {
        StorageEntity storage se = storageEntities[entityOwner];
        _ensureStorageEntityExists(se);
        _ensureStorageProviderIsAssignedToStorageEntity(se, storageProvider);

        se.providerDetails[storageProvider] = details;
    }

    /**
     * @notice Check if a storage provider is already used
     * @param storageProvider The storage provider ID to check
     * @return True if the storage provider is used
     */
    function isStorageProviderUsed(uint64 storageProvider) external view returns (bool) {
        return usedStorageProviders[storageProvider];
    }

    /**
     * @notice Get a storage entity by owner address
     * @param entityOwner The owner address of the storage entity
     * @return A view struct containing the storage entity data
     */
    function getStorageEntity(address entityOwner) external view returns (StorageEntityView memory) {
        StorageEntity storage se = storageEntities[entityOwner];
        _ensureStorageEntityExists(se);

        return _storageEntityToView(se);
    }

    /**
     * @notice Get all storage entities
     * @return An array of storage entity views
     */
    function getStorageEntities() external view returns (StorageEntityView[] memory) {
        StorageEntityView[] memory entityViews = new StorageEntityView[](entityAddresses.length);
        for (uint256 i = 0; i < entityAddresses.length; i++) {
            entityViews[i] = _storageEntityToView(storageEntities[entityAddresses[i]]);
        }
        return entityViews;
    }

    /**
     * @notice Will revert if any storage provider in the list is already used
     * @param storageProviders The storage providers to check
     */
    function _ensureNoStorageProviderUsed(uint64[] calldata storageProviders) internal view {
        for (uint256 i = 0; i < storageProviders.length; i++) {
            if (usedStorageProviders[storageProviders[i]]) {
                revert StorageProviderAlreadyUsed();
            }
        }
    }

    /**
     * @notice Ensure a storage entity exists
     * @param se The storage entity
     */
    function _ensureStorageEntityExists(StorageEntity storage se) internal view {
        if (se.owner == address(0)) {
            revert StorageEntityDoesNotExist();
        }
    }

    /**
     * @notice Ensure a storage provider is assigned to a storage entity
     * @param se The storage entity
     * @param storageProvider The storage provider ID
     */
    function _ensureStorageProviderIsAssignedToStorageEntity(StorageEntity storage se, uint64 storageProvider)
        internal
        view
    {
        bool isAssigned = false;
        for (uint256 i = 0; i < se.storageProviders.length; i++) {
            if (se.storageProviders[i] == storageProvider) {
                isAssigned = true;
                break;
            }
        }
        if (!isAssigned) {
            revert StorageProviderNotAssignedToEntity();
        }
    }

    /**
     * @notice Convert a storage entity to a view struct
     * @param se The storage entity
     * @return A view struct containing the storage entity data
     */
    function _storageEntityToView(StorageEntity storage se) internal view returns (StorageEntityView memory) {
        StorageEntityView memory entityView;
        entityView.isActive = se.isActive;
        entityView.owner = se.owner;
        entityView.storageProviders = se.storageProviders;
        entityView.providerDetails = new ProviderDetailsView[](se.storageProviders.length > 0 ? se.storageProviders.length : 0);
        if (se.storageProviders.length > 0) {
            for (uint256 i = 0; i < se.storageProviders.length; i++) {
                uint64 providerId = se.storageProviders[i];
                entityView.providerDetails[i] = ProviderDetailsView({
                    providerId: providerId,
                    spaceLeft: se.providerDetails[providerId].spaceLeft,
                    isActive: se.providerDetails[providerId].isActive
                });
            }
        }
        return entityView;
    }

    /**
     * @notice Authorize an upgrade (only admin can upgrade)
     * @param newImplementation The address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        // Upgrade authorization is handled by the modifier
    }
}
