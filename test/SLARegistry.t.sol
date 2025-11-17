// SPDX-License-Identifier: MIT
// solhint-disable use-natspec
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";
import {SLARegistry} from "../src/SLARegistry.sol";
import {SLIOracle} from "../src/SLIOracle.sol";
import {MockProxy} from "./contracts/MockProxy.sol";
import {MockSLIOracle} from "./contracts/MockSLIOracle.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {MinerUtils} from "../src/libs/MinerUtils.sol";
import {ActorIdMock} from "./contracts/ActorIdMock.sol";
import {ResolveAddressPrecompileMock} from "./contracts/ResolveAddressPrecompileMock.sol";
import {ActorIdExitCodeErrorFailingMock} from "./contracts/ActorIdExitCodeErrorFailingMock.sol";
import {ResolveAddressPrecompileFailingMock} from "../test/contracts/ResolveAddressPrecompileFailingMock.sol";
import {FilAddressIdConverter} from "filecoin-solidity/v0.8/utils/FilAddressIdConverter.sol";
import {ActorIdUnauthorizedCallerFailingMock} from "./contracts/ActorIdUnauthorizedCallerFailingMock.sol";

contract SLARegistryTest is Test {
    SLARegistry public slaRegistry;
    address public client;
    CommonTypes.FilActorId public provider;
    SLARegistry.SLAParams public slaParams;
    MockSLIOracle public oracle;

    ActorIdMock public actorIdMock;
    ResolveAddressPrecompileFailingMock public resolveAddressPrecompileFailingMock;
    ResolveAddressPrecompileMock public resolveAddress =
        ResolveAddressPrecompileMock(payable(0xFE00000000000000000000000000000000000001));
    ResolveAddressPrecompileMock public resolveAddressPrecompileMock;
    address public constant CALL_ACTOR_ID = 0xfe00000000000000000000000000000000000005;
    address public constant CALL_ACTOR_ADDRESS = 0xfe00000000000000000000000000000000000003;
    ActorIdExitCodeErrorFailingMock public actorIdExitCodeErrorFailingMock;
    ActorIdUnauthorizedCallerFailingMock public actorIdUnauthorizedCallerFailingMock;

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

        actorIdMock = new ActorIdMock();
        actorIdExitCodeErrorFailingMock = new ActorIdExitCodeErrorFailingMock();
        resolveAddressPrecompileMock = new ResolveAddressPrecompileMock();
        resolveAddressPrecompileFailingMock = new ResolveAddressPrecompileFailingMock();
        actorIdUnauthorizedCallerFailingMock = new ActorIdUnauthorizedCallerFailingMock();

        address actorIdProxy = address(new MockProxy(address(5555)));
        vm.etch(CALL_ACTOR_ID, address(actorIdProxy).code);
        vm.etch(address(5555), address(actorIdMock).code);
        vm.etch(address(resolveAddress), address(resolveAddressPrecompileMock).code);
    }

    function testIsAdminSet() public view {
        bytes32 adminRole = slaRegistry.DEFAULT_ADMIN_ROLE();
        assertTrue(slaRegistry.hasRole(adminRole, address(this)));
    }

    function testAuthorizeUpgradeRevert() public {
        address newImpl = address(new SLARegistry());
        address unauthorized = vm.addr(1);
        bytes32 upgraderRole = slaRegistry.UPGRADER_ROLE();

        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, unauthorized, upgraderRole)
        );
        slaRegistry.upgradeToAndCall(newImpl, "");
    }

    function testRegisterSLA() public {
        vm.prank(client);
        slaRegistry.registerSLA(client, provider, slaParams);

        (
            uint32 latency,
            uint16 retention,
            uint16 bandwidth,
            uint16 stability,
            uint8 availability,
            uint8 indexing,
            bool registered
        ) = slaRegistry.slas(client, provider);

        assertEq(availability, slaParams.availability);
        assertEq(latency, slaParams.latency);
        assertEq(indexing, slaParams.indexing);
        assertEq(retention, slaParams.retention);
        assertEq(bandwidth, slaParams.bandwidth);
        assertEq(stability, slaParams.stability);
        assertEq(registered, true);
    }

    function testRegisterSLARevert() public {
        vm.prank(client);
        slaRegistry.registerSLA(client, provider, slaParams);

        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(SLARegistry.SLAAlreadyRegistered.selector, client, provider));
        slaRegistry.registerSLA(client, provider, slaParams);
    }

    function testSLARegisteredEventEmitted() public {
        vm.expectEmit(true, true, true, true);
        emit SLARegistry.SLARegistered(client, provider);
        vm.prank(client);
        slaRegistry.registerSLA(client, provider, slaParams);
    }

    function testScoreRevertsForUnknown() public {
        vm.expectRevert(abi.encodeWithSelector(SLARegistry.SLAUnknown.selector, client, provider));
        slaRegistry.score(client, provider);
        vm.prank(client);
        slaRegistry.registerSLA(client, provider, slaParams);
    }

    function testScoreDoesntRevertForKnown() public {
        vm.prank(client);
        slaRegistry.registerSLA(client, provider, slaParams);
        slaRegistry.score(client, provider);
    }

    function testScoreIsZeroForNoSLI() public {
        vm.prank(client);
        slaRegistry.registerSLA(client, provider, slaParams);
        assertEq(slaRegistry.score(client, provider), 0);
    }

    function testScoreIsNonZeroForSLI() public {
        vm.prank(client);
        slaRegistry.registerSLA(client, provider, slaParams);
        oracle.setLastUpdate(123);
        assertFalse(slaRegistry.score(client, provider) == 0);
    }

    function testSLARegistryExpectRevertExitCodeError() public {
        vm.etch(address(5555), address(actorIdExitCodeErrorFailingMock).code);
        vm.expectRevert(abi.encodeWithSelector(MinerUtils.ExitCodeError.selector));
        slaRegistry.registerSLA(client, provider, slaParams);
    }

    function testSLARegistryExpectRevertUnauthorizedCaller() public {
        resolveAddress.setId(CommonTypes.FilActorId.unwrap(provider));
        vm.etch(address(5555), address(actorIdUnauthorizedCallerFailingMock).code);
        vm.expectRevert(abi.encodeWithSelector(SLARegistry.UnauthorizedCaller.selector));
        slaRegistry.registerSLA(client, provider, slaParams);
    }

    function testSLARegistryProvider() public {
        resolveAddress.setId(CommonTypes.FilActorId.unwrap(provider));
        address evmProviderAddress = FilAddressIdConverter.toAddress(CommonTypes.FilActorId.unwrap(provider));
        vm.prank(evmProviderAddress);
        slaRegistry.registerSLA(client, provider, slaParams);
    }

    function testSLARegistryClient() public {
        vm.prank(client);
        slaRegistry.registerSLA(client, provider, slaParams);
    }
}
