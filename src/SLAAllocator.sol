// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";
import {GetBeneficiary} from "./libs/GetBeneficiary.sol";
import {BeneficiaryFactory} from "./BeneficiaryFactory.sol";
import {Client} from "./Client.sol";
import {SLARegistry} from "./SLARegistry.sol";

/**
 * @title SLA Allocator
 * @notice Upgradeable contract for SLA allocation with role-based access control
 * @dev This contract is designed to be deployed as a proxy contract
 */
contract SLAAllocator is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    struct SLA {
        SLARegistry registry;
        CommonTypes.FilActorId provider;
    }

    /**
     * @notice Error thrown when a SLA is not registered
     */
    error SLANotRegistered();

    /**
     * @notice Error thrown when a provider is bound to a different client
     */
    error ProviderBoundToDifferentClient();

    /**
     * @notice Upgradable role which allows for contract upgrades
     */
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /**
     * @notice Address of the registry of beneficiary contracts
     */
    BeneficiaryFactory public beneficiaryFactory;

    /**
     * @notice TEMPORARY! Each provider's client
     */
    mapping(CommonTypes.FilActorId provider => address client) public providerClients;

    /**
     * @notice Addresses of known SLA Contracts
     */
    mapping(address client => mapping(CommonTypes.FilActorId provider => SLARegistry contractAddress)) public
        slaContracts;

    /**
     * @notice List of provider FilActorIds
     */
    CommonTypes.FilActorId[] public providers;

    /**
     * @notice Address of Client Smart Contract for this allocator
     */
    Client public clientSmartContract;

    /**
     * @notice Event emitted when DataCap is granted to a client
     * @param client The client address
     * @param provider The provider FilActorId
     * @param amount The amount of DataCap granted
     */
    event DataCapGranted(address indexed client, CommonTypes.FilActorId indexed provider, uint256 amount);

    /**
     * @notice New SLA between client and provider registered in the allocator
     * @param client The client address
     * @param provider The provider FilActorId
     */
    event SLARegistered(address indexed client, CommonTypes.FilActorId indexed provider);

    error BeneficiaryFactoryAlreadySet();

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
    function initialize(address admin) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
    }

    /**
     * @notice Setter for beneficiary factory
     * @param clientSmartContract_ Instance of Client smart contract
     * @param beneficiaryFactory_ Instance of BeneficiaryFactory
     */
    function initialize2(Client clientSmartContract_, BeneficiaryFactory beneficiaryFactory_)
        external
        reinitializer(2)
    {
        beneficiaryFactory = beneficiaryFactory_;
        clientSmartContract = clientSmartContract_;
    }

    // solhint-disable no-unused-vars
    /**
     * @notice Grants DataCap to a client
     * @param slas Providers and SLA contracts
     * @param amount Amount of DC to grant
     */
    function requestDataCap(SLA[] calldata slas, uint256 amount) external {
        address client = msg.sender;

        for (uint256 i = 0; i < slas.length; ++i) {
            CommonTypes.FilActorId provider = slas[i].provider;
            SLARegistry registry = slas[i].registry;

            // make sure SLA is registered (it doesnt revert)
            registry.score(client, provider);

            // make sure beneficiary is set correctly
            GetBeneficiary.getBeneficiaryWithChecks(provider, true, true, true);

            // make sure this provider isnt working with other client already

            // update state
            slaContracts[client][provider] = slas[i].registry;
            if (providerClients[provider] == address(0)) {
                providerClients[provider] = client;
                providers.push(provider);
                emit SLARegistered(client, provider);
            } else if (providerClients[provider] != client) {
                revert ProviderBoundToDifferentClient();
            }

            clientSmartContract.increaseAllowance(client, provider, amount);
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
}
