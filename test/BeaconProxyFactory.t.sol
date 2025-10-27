// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BeaconProxyFactory} from "../src/BeaconProxyFactory.sol";
import {Beneficiary} from "../src/Beneficiary.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

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
        vm.expectEmit(true, false, false, true);
        emit UpgradeableBeacon.Upgraded(impl);

        new BeaconProxyFactory(manager, impl);
    }

    function testDeployEmitsEvent() public {
        vm.expectEmit(false, true, false, true);
        emit BeaconProxyFactory.ProxyCreated(vm.addr(1));

        factory.create(manager);
    }

    function testDeployIncrementsNonce() public {
        factory.create(manager);
        assertEq(factory.nonce(manager), 1);
        factory.create(manager);
        assertEq(factory.nonce(manager), 2);
    }
}
