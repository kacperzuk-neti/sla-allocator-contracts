// SPDX-License-Identifier: MIT
// solhint-disable use-natspec

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BeaconProxyFactory} from "../src/BeaconProxyFactory.sol";
import {Beneficiary} from "../src/Beneficiary.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {SLARegistry} from "../src/SLARegistry.sol";

contract BeaconProxyFactoryTest is Test {
    BeaconProxyFactory public factory;
    address public impl;
    address public manager;
    address public slaRegistry;
    address public provider;

    function setUp() public {
        manager = vm.addr(1);
        provider = vm.addr(2);
        slaRegistry = address(new SLARegistry());
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
        emit BeaconProxyFactory.ProxyCreated(expectedProxy, provider);

        factory.create(manager, provider, slaRegistry);
    }

    function testDeployMarksProxyAsDeployed() public {
        address expectedProxy = computeProxyAddress(manager, factory.nonce(manager) + 1);
        factory.create(manager, provider, slaRegistry);

        assertTrue(factory.instances(provider) == expectedProxy);
    }

    function testDeployIncrementsNonce() public {
        factory.create(manager, provider, slaRegistry);
        assertEq(factory.nonce(manager), 1);
    }

    function testDeployRevertsIfInstanceExists() public {
        factory.create(manager, provider, slaRegistry);

        vm.expectRevert(abi.encodeWithSelector(BeaconProxyFactory.InstanceAlreadyExists.selector));
        factory.create(manager, provider, slaRegistry);
    }

    function computeProxyAddress(address manager_, uint256 nonce_) private view returns (address) {
        bytes memory initCode = abi.encodePacked(
            type(BeaconProxy).creationCode,
            abi.encode(address(factory), abi.encodeCall(Beneficiary.initialize, (manager_, provider, slaRegistry)))
        );
        bytes32 salt = keccak256(abi.encode(manager_, nonce_));
        bytes32 bytecodeHash = keccak256(initCode);
        return Create2.computeAddress(salt, bytecodeHash, address(factory));
    }
}
