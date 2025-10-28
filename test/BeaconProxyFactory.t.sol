// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BeaconProxyFactory} from "../src/BeaconProxyFactory.sol";
import {Beneficiary} from "../src/Beneficiary.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

contract BeaconProxyFactoryTest is Test {
    BeaconProxyFactory public factory;
    address public impl;
    address public manager;

    function setUp() public {
        manager = vm.addr(1);
        impl = address(new Beneficiary());
        factory = new BeaconProxyFactory(manager, impl);
    }

    function testEmitsUpgradedInConstructor() public {
        vm.expectEmit(true, true, true, true);
        emit UpgradeableBeacon.Upgraded(impl);

        new BeaconProxyFactory(manager, impl);
    }

    function testDeployEmitsEvent() public {
        vm.expectEmit(true, true, true, true);

        address expectedProxy = computeProxyAddress(manager, factory.nonce(manager) + 1);
        emit BeaconProxyFactory.ProxyCreated(expectedProxy);

        factory.create(manager);
    }

    function testDeployMarksProxyAsDeployed() public {
        address expectedProxy = computeProxyAddress(manager, factory.nonce(manager) + 1);
        factory.create(manager);

        assertTrue(factory.proxyDeployed(expectedProxy));
    }

    function testDeployIncrementsNonce() public {
        factory.create(manager);
        assertEq(factory.nonce(manager), 1);
        factory.create(manager);
        assertEq(factory.nonce(manager), 2);
    }

    function computeProxyAddress(address manager_, uint256 nonce_) private view returns (address) {
        bytes memory initCode = abi.encodePacked(
            type(BeaconProxy).creationCode,
            abi.encode(address(factory), abi.encodeCall(Beneficiary.initialize, (manager_)))
        );
        bytes32 salt = keccak256(abi.encode(manager_, nonce_));
        bytes32 bytecodeHash = keccak256(initCode);
        return Create2.computeAddress(salt, bytecodeHash, address(factory));
    }
}
