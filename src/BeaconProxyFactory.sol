// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Beneficiary} from "./Beneficiary.sol";

/**
 * @title BeaconProxyFactory
 * @notice Factory contract for creating deterministic beacon proxies using CREATE2
 * @dev This factory extends UpgradeableBeacon and uses CREATE2 to deploy BeaconProxy
 * instances at predictable addresses.
 */
contract BeaconProxyFactory is UpgradeableBeacon {
    /**
     * @notice Tracks the deployment counter for each manager
     */
    mapping(address owner => uint256 deployCounter) public nonce;

    /**
     * @notice Returns the deployment status of a proxy contract by its address
     */
    mapping(address proxy => bool isDeployed) public proxyDeployed;

    /**
     * @notice Emitted when a new proxy is successfully created
     * @param proxy The address of the newly deployed proxy
     */
    event ProxyCreated(address indexed proxy);

    constructor(address initialOwner, address implementation_) UpgradeableBeacon(implementation_, initialOwner) {}

    /**
     * @notice Creates a new instance of an upgradeable contract.
     * @dev Uses BeaconProxy to create a new proxy instance, pointing to the Beacon for the logic contract.
     * @param manager_ The address of the manager responsible for the contract.
     */
    function create(address manager_) external {
        nonce[manager_]++;
        bytes memory initCode = abi.encodePacked(
            type(BeaconProxy).creationCode,
            abi.encode(address(this), abi.encodeCall(Beneficiary.initialize, (manager_)))
        );
        address proxy = Create2.deploy(0, keccak256(abi.encode(manager_, nonce[manager_])), initCode);
        proxyDeployed[proxy] = true;
        emit ProxyCreated(proxy);
    }
}
