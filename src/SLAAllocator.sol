// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";
import {FilAddresses} from "filecoin-solidity/v0.8/utils/FilAddresses.sol";
import {VerifRegAPI} from "filecoin-solidity/v0.8/VerifRegAPI.sol";
import {VerifRegTypes} from "filecoin-solidity/v0.8/types/VerifRegTypes.sol";
import {PrecompilesAPI} from "filecoin-solidity/v0.8/PrecompilesAPI.sol";

import {MinerUtils} from "./libs/MinerUtils.sol";
import {BeneficiaryFactory} from "./BeneficiaryFactory.sol";
import {Client} from "./Client.sol";
import {SLARegistry} from "./SLARegistry.sol";
import {RateLimited} from "./RateLimited.sol";

/**
 * @title SLA Allocator
 * @notice Upgradeable contract for SLA allocation with role-based access control
 * @dev This contract is designed to be deployed as a proxy contract
 */
contract SLAAllocator is Initializable, AccessControlUpgradeable, UUPSUpgradeable, EIP712Upgradeable, RateLimited {
    /**
     * @notice Error thrown when PaymentTransaction is already used
     */
    error PaymentTxnAlreadyUsed();

    /**
     * @notice Error thrown when attestation signature is not verified
     */
    error PaymentTxnNotVerified();

    /**
     * @notice Error thrown when transaction payer is the same as storage provider owner
     */
    error TxPayerSameAsSPOwner();

    /**
     * @notice Error thrown when amount exceeds non-passport limit
     */
    error AmountExceedsNonPassportLimit();

    /**
     * @notice Error thrown when SLA is already registered
     */
    error SLAAlreadyRegistered();

    struct SLA {
        SLARegistry registry;
        CommonTypes.FilActorId provider;
    }

    struct Passport {
        uint256 expirationTimestamp;
        address subject;
        uint64 score;
    }

    struct PassportSigned {
        Passport passport;
        bytes signature;
    }

    struct ManualAttestation {
        bytes32 attestationId;
        address client;
        CommonTypes.FilActorId provider;
        uint256 amount;
        string opaqueData;
    }

    struct ManualAttestationSigned {
        ManualAttestation attestation;
        bytes signature;
    }

    struct PaymentTransaction {
        bytes id;
        CommonTypes.FilAddress from;
        CommonTypes.FilAddress to;
        uint256 amount;
    }

    struct PaymentTransactionSigned {
        PaymentTransaction txn;
        bytes signature;
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

    /**
     * @notice Attestor role which allows sign attestations
     */
    bytes32 public constant ATTESTATOR_ROLE = keccak256("ATTESTATOR_ROLE");

    // solhint-disable gas-small-strings
    /**
     * @notice EIP-712 typehash for Passport struct
     */
    bytes32 private constant PASSPORT_TYPEHASH =
        keccak256("Passport(uint256 expirationTimestamp,address subject,uint64 score)");

    /**
     * @notice EIP-712 typehash for PaymentTransaction struct
     */
    bytes32 private constant PAYMENT_TX_TYPEHASH =
        keccak256("PaymentTransaction(bytes id,bytes from,bytes to,uint256 amount)");

    /**
     * @notice EIP-712 typehash for ManualAttestation struct
     */
    bytes32 private constant MANUAL_ATTESTATION_TYPEHASH = keccak256(
        "ManualAttestation(bytes32 attestationId,address client,uint64 provider,uint256 amount,string opaqueData)"
    );
    // solhint-enable gas-small-strings

    /**
     * @notice Maximum amount of datacap that can be granted without a passport
     */
    uint256 private constant MAX_NON_PASSPORT_LIMIT = 100 * 2 ** 40;

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
     * @notice Tracking for used payment transactions by id
     */
    mapping(bytes id => bool isUsed) public usedTransactions;

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

    /**
     * @notice Emitted when beneficiary factory is set
     * @param newBeneficiaryFactory The new beneficiary factory
     */
    event BeneficiaryFactorySet(BeneficiaryFactory indexed newBeneficiaryFactory);

    /**
     * @notice Emitted when client smart contract is set
     * @param newClientSmartContract The new client smart contract
     */
    event ClientSmartContractSet(Client indexed newClientSmartContract);

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
     * @param attestor Attestor address (granted ATTESTATOR_ROLE)
     */
    function initialize(address admin, address manager, address attestor) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __EIP712_init("SLAAllocator", "1");
        _initRateLimit();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        _grantRole(MANAGER_ROLE, manager);
        _grantRole(ATTESTATOR_ROLE, attestor);
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
            MinerUtils.getBeneficiaryWithChecks(provider, beneficiaryFactory, true, true, true);

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

    /**
     * @notice Grants DataCap to a client without passport
     * @param provider Provider FilActorId
     * @param slaContract SLARegistry contract address
     * @param amount Amount of DC to grant
     * @param txn Signed payment transaction
     */
    function requestDataCap(
        CommonTypes.FilActorId provider,
        address slaContract,
        uint256 amount,
        PaymentTransactionSigned calldata txn
    ) external globallyRateLimited {
        address client = msg.sender;

        CommonTypes.FilAddress memory providerOwner = MinerUtils.getOwner(provider).owner;
        uint64 resolvedProviderOwner = PrecompilesAPI.resolveAddress(providerOwner);
        uint64 resolvedTxnFrom = PrecompilesAPI.resolveAddress(txn.txn.from);

        if (resolvedProviderOwner == resolvedTxnFrom) {
            revert TxPayerSameAsSPOwner();
        }

        if (amount > MAX_NON_PASSPORT_LIMIT) {
            revert AmountExceedsNonPassportLimit();
        }

        bytes memory txnId = txn.txn.id;
        if (usedTransactions[txnId]) {
            revert PaymentTxnAlreadyUsed();
        }
        usedTransactions[txnId] = true;

        bool isVerified = verifyPaymentTransactionSigned(txn);
        if (!isVerified) {
            revert PaymentTxnNotVerified();
        }

        SLARegistry registry = SLARegistry(slaContract);
        _registerSLAAndGrant(client, provider, registry, amount);
    }

    /**
     * @notice Internal function to register SLA and grant datacap
     * @param client Client address
     * @param provider Provider FilActorId
     * @param registry SLARegistry contract
     * @param amount Amount of datacap to grant
     */
    function _registerSLAAndGrant(
        address client,
        CommonTypes.FilActorId provider,
        SLARegistry registry,
        uint256 amount
    ) internal {
        registry.score(client, provider);
        MinerUtils.getBeneficiaryWithChecks(provider, beneficiaryFactory, true, true, true);

        if (address(slaContracts[client][provider]) != address(0)) {
            revert SLAAlreadyRegistered();
        }

        slaContracts[client][provider] = registry;
        if (providerClients[provider] == address(0)) {
            providerClients[provider] = client;
            providers.push(provider);
            emit SLARegistered(client, provider);
        }

        clientSmartContract.increaseAllowance(client, provider, amount);
        emit DataCapGranted(client, provider, amount);
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

    /**
     * @notice Register provider as known to the system
     * @param provider Id of the provider
     */
    function addProvider(CommonTypes.FilActorId provider) external onlyRole(MANAGER_ROLE) {
        uint64 providerInt = CommonTypes.FilActorId.unwrap(provider);
        for (uint256 i = 0; i < providers.length; i++) {
            if (CommonTypes.FilActorId.unwrap(providers[i]) == providerInt) {
                // already in the list, nothing to do
                return;
            }
        }
        providers.push(provider);
    }

    /**
     * @notice Setter for beneficiary factory
     * @param newBeneficiaryFactory The new beneficiary factory
     */
    function setBeneficiaryFactory(BeneficiaryFactory newBeneficiaryFactory) external onlyRole(DEFAULT_ADMIN_ROLE) {
        beneficiaryFactory = newBeneficiaryFactory;
        emit BeneficiaryFactorySet(newBeneficiaryFactory);
    }

    /**
     * @notice Setter for client smart contract
     * @param newClientSmartContract The new client smart contract
     */
    function setClientSmartContract(Client newClientSmartContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        clientSmartContract = newClientSmartContract;
        emit ClientSmartContractSet(newClientSmartContract);
    }

    /**
     * @notice Verify signed Passport
     * @param passport PassportSigned struct
     * @return True if signature is valid and signer has ATTESTATOR_ROLE
     */
    function verifyPassportSigned(PassportSigned calldata passport) internal view returns (bool) {
        bytes32 structHash = _hashPassport(passport.passport);
        address signer = _recoverFromSig(structHash, passport.signature);
        return signer != address(0) && hasRole(ATTESTATOR_ROLE, signer);
    }

    /**
     * @notice Verify signed PaymentTransaction
     * @param txn PaymentTransactionSigned struct
     * @return True if signature is valid and signer has ATTESTATOR_ROLE
     */
    function verifyPaymentTransactionSigned(PaymentTransactionSigned calldata txn) internal view returns (bool) {
        bytes32 structHash = _hashPaymentTransaction(txn.txn);
        address signer = _recoverFromSig(structHash, txn.signature);
        return signer != address(0) && hasRole(ATTESTATOR_ROLE, signer);
    }

    /**
     * @notice Verify signed ManualAttestation
     * @param attestation ManualAttestationSigned struct
     * @return True if signature is valid and signer has ATTESTATOR_ROLE
     */
    function verifyManualAttestationSigned(ManualAttestationSigned calldata attestation) internal view returns (bool) {
        bytes32 structHash = _hashManualAttestation(attestation.attestation);
        address signer = _recoverFromSig(structHash, attestation.signature);
        return signer != address(0) && hasRole(ATTESTATOR_ROLE, signer);
    }

    /**
     * @notice Hash Passport struct
     * @param passport Passport struct
     * @return Hash of the struct
     */
    function _hashPassport(Passport calldata passport) internal pure returns (bytes32) {
        return keccak256(abi.encode(PASSPORT_TYPEHASH, passport.expirationTimestamp, passport.subject, passport.score));
    }

    /**
     * @notice Hash PaymentTransaction struct
     * @param txn PaymentTransaction struct
     * @return Hash of the struct
     */
    function _hashPaymentTransaction(PaymentTransaction calldata txn) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                PAYMENT_TX_TYPEHASH, keccak256(txn.id), keccak256(txn.from.data), keccak256(txn.to.data), txn.amount
            )
        );
    }

    /**
     * @notice Hash ManualAttestation struct
     * @param attestation ManualAttestation struct
     * @return Hash of the struct
     */
    function _hashManualAttestation(ManualAttestation calldata attestation) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                MANUAL_ATTESTATION_TYPEHASH,
                attestation.attestationId,
                attestation.client,
                attestation.provider,
                attestation.amount,
                keccak256(bytes(attestation.opaqueData))
            )
        );
    }

    /**
     * @notice Recover address from signature over struct hash
     * @param structHash Hash of the struct
     * @param signature bytes
     * @return Address that signed the struct
     */
    function _recoverFromSig(bytes32 structHash, bytes calldata signature) internal view returns (address) {
        bytes32 digest = _hashTypedDataV4(structHash);
        return ECDSA.recover(digest, signature);
    }
}
