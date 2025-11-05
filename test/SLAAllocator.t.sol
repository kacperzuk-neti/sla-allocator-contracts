// SPDX-License-Identifier: MIT
// solhint-disable use-natspec
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SLAAllocator} from "../src/SLAAllocator.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SLAAllocatorTest is Test {
    SLAAllocator public slaAllocator;

    function setUp() public {
        SLAAllocator impl = new SLAAllocator();
        bytes memory initData = abi.encodeWithSignature("initialize(address)", address(this));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        slaAllocator = SLAAllocator(address(proxy));
    }

    function testIsAdminSet() public view {
        bytes32 adminRole = slaAllocator.DEFAULT_ADMIN_ROLE();
        assertTrue(slaAllocator.hasRole(adminRole, address(this)));
    }

    function testAuthorizeUpgradeRevert() public {
        address newImpl = address(new SLAAllocator());
        address unauthorized = vm.addr(1);
        bytes32 upgraderRole = slaAllocator.UPGRADER_ROLE();
        // solhint-disable-next-line gas-small-strings
        bytes4 sel = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));

        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(sel, unauthorized, upgraderRole));
        slaAllocator.upgradeToAndCall(newImpl, "");
    }
}
