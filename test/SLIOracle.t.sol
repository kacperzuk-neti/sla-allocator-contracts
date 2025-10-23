// SPDX-License-Identifier: MIT
// solhint-disable use-natspec
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SLIOracle} from "../src/SLIOracle.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SLIOracleTest is Test {
    SLIOracle public sliOracle;

    function setUp() public {
        SLIOracle impl = new SLIOracle();
        bytes memory initData = abi.encodeWithSignature("initialize(address)", address(this));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        sliOracle = SLIOracle(address(proxy));
    }

    function testIsAdminSet() public view {
        bytes32 adminRole = sliOracle.DEFAULT_ADMIN_ROLE();
        assertTrue(sliOracle.hasRole(adminRole, address(this)));
    }

    function testAuthorizeUpgradeRevert() public {
        address newImpl = address(new SLIOracle());
        vm.prank(vm.addr(1));
        vm.expectRevert();
        sliOracle.upgradeToAndCall(newImpl, "");
    }
}
