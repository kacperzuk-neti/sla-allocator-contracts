// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Beneficiary} from "./Beneficiary.sol";

contract BeaconProxyFactory is UpgradeableBeacon {
    mapping(address owner => uint256 deployCounter) public nonce;
    mapping(address proxy => bool isDeployed) public proxyDeployed;
    event ProxyCreated(address indexed proxy);

    constructor(address initialOwner, address implementation_) UpgradeableBeacon(implementation_, initialOwner) {}

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
