// SPDX-License-Identifier: MIT
// solhint-disable use-natspec
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SLARegistry} from "../src/SLARegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SLARegistryTest is Test {
    SLARegistry public slaRegistry;

    function setUp() public {
        SLARegistry impl = new SLARegistry();
        bytes memory initData = abi.encodeWithSignature("initialize(address)", address(this));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        slaRegistry = SLARegistry(address(proxy));
    }

    function testIsAdminSet() public view {
        bytes32 adminRole = slaRegistry.DEFAULT_ADMIN_ROLE();
        assertTrue(slaRegistry.hasRole(adminRole, address(this)));
    }

    function testAuthorizeUpgradeRevert() public {
        address newImpl = address(new SLARegistry());
        vm.prank(vm.addr(1));
        vm.expectRevert();
        slaRegistry.upgradeToAndCall(newImpl, "");
    }
}
