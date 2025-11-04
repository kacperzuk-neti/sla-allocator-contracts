// SPDX-License-Identifier: MIT
// solhint-disable use-natspec
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SLARegistry} from "../src/SLARegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract SLARegistryTest is Test {
    SLARegistry public slaRegistry;
    address public client;
    address public provider;
    SLARegistry.SLAParams public slaParams;

    function setUp() public {
        SLARegistry impl = new SLARegistry();
        bytes memory initData = abi.encodeWithSignature("initialize(address)", address(this));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        slaRegistry = SLARegistry(address(proxy));
        client = address(0x123);
        provider = address(0x456);
        slaParams = SLARegistry.SLAParams({
            availability: 99, latency: 99, indexing: 99, retention: 99, bandwidth: 99, stability: 99, registered: false
        });
    }

    function testIsAdminSet() public view {
        bytes32 adminRole = slaRegistry.DEFAULT_ADMIN_ROLE();
        assertTrue(slaRegistry.hasRole(adminRole, address(this)));
    }

    function testAuthorizeUpgradeRevert() public {
        address newImpl = address(new SLARegistry());
        address unauthorized = vm.addr(1);
        bytes32 upgraderRole = slaRegistry.UPGRADER_ROLE();
        bytes4 sel = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));

        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(sel, unauthorized, upgraderRole));
        slaRegistry.upgradeToAndCall(newImpl, "");
    }

    function testRegisterSLA() public {
        vm.prank(address(this));
        slaRegistry.registerSLA(client, provider, slaParams);

        (
            uint16 availability,
            uint16 latency,
            uint16 indexing,
            uint16 retention,
            uint16 bandwidth,
            uint16 stability,
            bool registered
        ) = slaRegistry.sla(client, provider);

        assertEq(availability, slaParams.availability);
        assertEq(latency, slaParams.latency);
        assertEq(indexing, slaParams.indexing);
        assertEq(retention, slaParams.retention);
        assertEq(bandwidth, slaParams.bandwidth);
        assertEq(stability, slaParams.stability);
        assertEq(registered, true);
    }

    function testRegisterSLARevert() public {
        vm.prank(address(this));
        slaRegistry.registerSLA(client, provider, slaParams);

        vm.expectRevert(abi.encodeWithSelector(SLARegistry.SLAAlreadyRegistered.selector, client, provider));
        slaRegistry.registerSLA(client, provider, slaParams);
    }

    function testSLARegisteredEventEmitted() public {
        vm.prank(address(this));
        vm.expectEmit(true, true, true, true);
        emit SLARegistry.SLARegistered(client, provider);
        slaRegistry.registerSLA(client, provider, slaParams);
    }

    function testRegisterSLARevertWhenNotAdmin() public {
        address notAdmin = address(0x333);
        bytes32 expectedRole = slaRegistry.DEFAULT_ADMIN_ROLE();
        vm.prank(notAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, notAdmin, expectedRole)
        );
        slaRegistry.registerSLA(client, provider, slaParams);
    }
}
