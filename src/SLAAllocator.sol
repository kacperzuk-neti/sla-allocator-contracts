// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";
import {FilAddresses} from "filecoin-solidity/v0.8/utils/FilAddresses.sol";
import {VerifRegAPI} from "filecoin-solidity/v0.8/VerifRegAPI.sol";
import {VerifRegTypes} from "filecoin-solidity/v0.8/types/VerifRegTypes.sol";

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
     * @notice Manager role which allows to manage datacap
     */
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    // solhint-disable gas-indexed-events
    /**
     * @notice Emitted when datacap is granted to a client
     * @param allocator Allocator who granted the datacap
     * @param client Client that received datacap (Filecoin address)
     * @param amount Amount of datacap
     */
    event DatacapAllocated(address indexed allocator, Client indexed client, uint256 amount);

    /**
     * @dev Thrown if trying to add 0 allowance or grant 0 datacap
     */
    error AmountEqualZero();

    // /**
    //  * @dev Thrown if VerifRegAPI call returns non-zero exit code
    //  */
    error ExitCodeError(int256);

    /**
     * @notice Address of the factory of beneficiary contracts
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
     * @notice Contract initializer. Should be called during deployment to configure roles and addresses.
     * @param admin Contract owner (granted DEFAULT_ADMIN_ROLE and UPGRADER_ROLE)
     * @param manager Manager address (granted MANAGER_ROLE)
     */
    function initialize(address admin, address manager) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        _grantRole(MANAGER_ROLE, manager);
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

    /**
     * @notice Grant allowance to a client.
     * @param amount Amount of datacap to grant
     * @dev Emits DatacapAllocated event
     * @dev Reverts with InsufficientAllowance if caller doesn't have sufficient allowance
     * @custom:oz-upgrades-unsafe-allow-reachable delegatecall
     */
    function mintDataCap(uint256 amount) external onlyRole(MANAGER_ROLE) {
        if (amount == 0) revert AmountEqualZero();
        VerifRegTypes.AddVerifiedClientParams memory params = VerifRegTypes.AddVerifiedClientParams({
            addr: FilAddresses.fromEthAddress(address(clientSmartContract)),
            allowance: CommonTypes.BigInt(abi.encodePacked(amount), false)
        });
        emit DatacapAllocated(msg.sender, clientSmartContract, amount);
        int256 exitCode = VerifRegAPI.addVerifiedClient(params);
        if (exitCode != 0) {
            revert ExitCodeError(exitCode);
        }
    }

    /**
     * @notice Get the list of providers
     * @return Array of provider FilActorIds
     */
    function getProviders() external view returns (CommonTypes.FilActorId[] memory) {
        return providers;
    }
}
