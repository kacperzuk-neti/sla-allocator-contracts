// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";
import {Beneficiary} from "./Beneficiary.sol";
import {SLAAllocator} from "./SLAAllocator.sol";

/**
 * @title BeneficiaryFactory
 * @notice Factory contract for creating deterministic beacon proxies using CREATE2
 */
contract BeneficiaryFactory is UUPSUpgradeable, AccessControlUpgradeable {
    /**
     * @notice Upgradable role which allows for contract upgrades
     */
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    error InstanceAlreadyExists();

    /**
     * @notice Tracks the deployment counter for each provider
     */
    mapping(address admin => mapping(CommonTypes.FilActorId provider => uint256 deployCounter)) public nonce;

    /**
     * @notice Tracks deployed instance by provider address
     */
    mapping(CommonTypes.FilActorId provider => address contractAddress) public instances;

    /**
     * @notice Address of the beacon used for new instances
     */
    address public beacon;

    /**
     * @notice Address of the SLAAllocator
     */
    SLAAllocator public slaAllocator;

    /**
     * @notice Emitted when a new proxy is successfully created
     * @param proxy The address of the newly deployed proxy
     * @param provider The provider for which the proxy was created
     */
    event ProxyCreated(address indexed proxy, CommonTypes.FilActorId indexed provider);

    /**
     * @notice Disabled constructor (proxy pattern)
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Contract initializator. Should be called during deployment
     * @dev Initializes the underlying UpgradeableBeacon with the given implementation
     *      and assigns the initial owner who can perform upgrades
     * @param admin The address to be set as the owner of the beacon (has upgrade permissions) and admin of the Factory itself
     * @param implementation The address of the initial Beneficiary implementation for the beacon
     * @param slaAllocator_ The address of the SLAAllocator
     */
    function initialize(address admin, address implementation, SLAAllocator slaAllocator_) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        beacon = address(new UpgradeableBeacon(implementation, admin));
        slaAllocator = slaAllocator_;
    }

    /**
     * @notice Creates a new instance of an upgradeable contract.
     * @dev Uses BeaconProxy to create a new proxy instance, pointing to the Beacon for the logic contract.
     * @dev Reverts if an instance for the given provider already exists.
     * @param admin The address of the admin responsible for the contract.
     * @param withdrawer The address of the withdrawer responsible for the contract.
     * @param provider The ID of the provider responsible for the contract.
     */
    function create(address admin, address withdrawer, CommonTypes.FilActorId provider) external {
        if (instances[provider] != address(0)) {
            revert InstanceAlreadyExists();
        }

        nonce[admin][provider]++;

        bytes memory initCode = abi.encodePacked(
            type(BeaconProxy).creationCode,
            abi.encode(beacon, abi.encodeCall(Beneficiary.initialize, (admin, withdrawer, provider, slaAllocator)))
        );

        address proxy = Create2.deploy(0, keccak256(abi.encode(admin, provider, nonce[admin][provider])), initCode);
        instances[provider] = proxy;
        emit ProxyCreated(proxy, provider);
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
