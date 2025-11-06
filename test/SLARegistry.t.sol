// SPDX-License-Identifier: MIT
// solhint-disable use-natspec
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";
import {SLARegistry} from "../src/SLARegistry.sol";
import {SLIOracle} from "../src/SLIOracle.sol";
import {MockSLIOracle} from "./contracts/MockSLIOracle.sol";

contract SLARegistryTest is Test {
    SLARegistry public slaRegistry;
    address public client;
    CommonTypes.FilActorId public provider;
    SLARegistry.SLAParams public slaParams;
    MockSLIOracle public oracle;

    function setUp() public {
        SLARegistry impl = new SLARegistry();
        oracle = new MockSLIOracle();
        bytes memory initData = abi.encodeCall(SLARegistry.initialize, (address(this), SLIOracle(address(oracle))));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        slaRegistry = SLARegistry(address(proxy));
        client = address(0x123);
        provider = CommonTypes.FilActorId.wrap(321);
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
        // solhint-disable-next-line gas-small-strings
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
        vm.expectEmit(true, true, true, true);
        emit SLARegistry.SLARegistered(client, provider);
        slaRegistry.registerSLA(client, provider, slaParams);
    }

    function testScoreRevertsForUnknown() public {
        vm.expectRevert(abi.encodeWithSelector(SLARegistry.SLAUnknown.selector, client, provider));
        slaRegistry.score(client, provider);
        slaRegistry.registerSLA(client, provider, slaParams);
    }

    function testScoreDoesntRevertForKnown() public {
        slaRegistry.registerSLA(client, provider, slaParams);
        slaRegistry.score(client, provider);
    }

    function testScoreIsZeroForNoSLI() public {
        slaRegistry.registerSLA(client, provider, slaParams);
        assertEq(slaRegistry.score(client, provider), 0);
    }

    function testScoreIsNonZeroForSLI() public {
        slaRegistry.registerSLA(client, provider, slaParams);
        oracle.setLastUpdate(123);
        assertFalse(slaRegistry.score(client, provider) == 0);
    }
}
