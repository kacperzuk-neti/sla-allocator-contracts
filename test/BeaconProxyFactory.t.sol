// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BeaconProxyFactory} from "../src/BeaconProxyFactory.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Beneficiary} from "../src/Beneficiary.sol";
import {Vm} from "forge-std/Vm.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract BeaconProxyFactoryTest is Test {
    BeaconProxyFactory public factory;
    address public impl;
    address public manager;

    function setUp() public {
        manager = vm.addr(1);
        impl = address(new Beneficiary());
        factory = new BeaconProxyFactory(manager, impl);
    }

    function testDeployEmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit BeaconProxyFactory.ProxyCreated(vm.addr(1));
        factory.create(manager);
    }

    function testDeployIncrementsNonce() public {
        factory.create(manager);
        assertEq(factory.nonce(manager), 1);
        factory.create(manager);
        assertEq(factory.nonce(manager), 2);
    }

    function testDeployContract() public {
        address addr = address(new BeaconProxyFactory(manager, impl));
        uint32 size;

        assembly {
            size := extcodesize(addr)
        }
        assertGt(size, 0);
    }
}
