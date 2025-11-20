// SPDX-License-Identifier: MIT
// solhint-disable use-natspec
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";

import {BeneficiaryFactory} from "../src/BeneficiaryFactory.sol";
import {Client} from "../src/Client.sol";
import {GetBeneficiary} from "../src/libs/GetBeneficiary.sol";
import {SLAAllocator} from "../src/SLAAllocator.sol";
import {SLARegistry} from "../src/SLAAllocator.sol";

import {ActorIdMock} from "./contracts/ActorIdMock.sol";
import {ActorIdExitCodeErrorFailingMock} from "./contracts/ActorIdExitCodeErrorFailingMock.sol";
import {ActorIdInvalidResponseLengthFailingMock} from "./contracts/ActorIdInvalidResponseLengthFailingMock.sol";
import {MockClient} from "./contracts/MockClient.sol";
import {MockProxy} from "./contracts/MockProxy.sol";
import {MockSLARegistry} from "./contracts/MockSLARegistry.sol";
import {Actor} from "filecoin-solidity/v0.8/utils/Actor.sol";
import {MockBeneficiaryFactory} from "./contracts/MockBeneficiaryFactory.sol";
import {ResolveAddressPrecompileMock} from "../test/contracts/ResolveAddressPrecompileMock.sol";
import {FilAddressIdConverter} from "filecoin-solidity/v0.8/utils/FilAddressIdConverter.sol";
import {ResolveAddressPrecompileFailingMock} from "../test/contracts/ResolveAddressPrecompileFailingMock.sol";

// solhint-disable-next-line max-states-count
contract SLAAllocatorTest is Test {
    SLAAllocator public slaAllocator;
    MockSLARegistry public slaRegistry;
    Client public clientSmartContract;
    SLAAllocator.SLA[] public slas;
    ActorIdMock public actorIdMock;
    MockBeneficiaryFactory public mockBeneficiaryFactory;
    ResolveAddressPrecompileMock public resolveAddressPrecompileMock;
    ResolveAddressPrecompileFailingMock public resolveAddressPrecompileFailingMock;
    ResolveAddressPrecompileMock public resolveAddress =
        ResolveAddressPrecompileMock(payable(0xFE00000000000000000000000000000000000001));

    address public constant CALL_ACTOR_ID = 0xfe00000000000000000000000000000000000005;

    // solhint-disable var-name-mixedcase
    CommonTypes.FilActorId public SP1 = CommonTypes.FilActorId.wrap(uint64(10000));
    CommonTypes.FilActorId public SP2 = CommonTypes.FilActorId.wrap(uint64(20000));
    CommonTypes.FilActorId public SP3 = CommonTypes.FilActorId.wrap(uint64(30000));
    CommonTypes.FilActorId public SP4 = CommonTypes.FilActorId.wrap(uint64(40000));
    CommonTypes.FilActorId public SP5 = CommonTypes.FilActorId.wrap(uint64(50000));
    CommonTypes.FilActorId public SP6 = CommonTypes.FilActorId.wrap(uint64(60000));

    address public admin = vm.addr(1);
    address public manager = vm.addr(2);
    address public unauthorized = vm.addr(5);

    function setUp() public {
        actorIdMock = new ActorIdMock();
        address actorIdProxy = address(new MockProxy(address(5555)));
        clientSmartContract = Client(address(new MockClient()));
        slaRegistry = new MockSLARegistry();
        resolveAddressPrecompileMock = new ResolveAddressPrecompileMock();
        resolveAddressPrecompileFailingMock = new ResolveAddressPrecompileFailingMock();
        mockBeneficiaryFactory = new MockBeneficiaryFactory();

        vm.etch(address(resolveAddress), address(resolveAddressPrecompileMock).code);
        vm.etch(CALL_ACTOR_ID, address(actorIdMock).code);
        vm.etch(address(5555), address(actorIdProxy).code);
        SLAAllocator impl = new SLAAllocator();
        bytes memory initData = abi.encodeCall(SLAAllocator.initialize, (admin, manager));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        slaAllocator = SLAAllocator(address(proxy));
        slaAllocator.initialize2(clientSmartContract, mockBeneficiaryFactory);

        slas.push(SLAAllocator.SLA(SLARegistry(address(slaRegistry)), SP1));
    }

    function testIsAdminSet() public view {
        bytes32 adminRole = slaAllocator.DEFAULT_ADMIN_ROLE();
        assertTrue(slaAllocator.hasRole(adminRole, admin));
    }

    function testAuthorizeUpgradeRevert() public {
        address newImpl = address(new SLAAllocator());
        bytes32 upgraderRole = slaAllocator.UPGRADER_ROLE();
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, unauthorized, upgraderRole)
        );
        slaAllocator.upgradeToAndCall(newImpl, "");
    }

    function testRequestDataCapRevertBeneficiaryInstanceNonexistent() public {
        slas[0].provider = SP1;
        vm.expectRevert(abi.encodeWithSelector(GetBeneficiary.BeneficiaryInstanceNonexistent.selector));
        slaAllocator.requestDataCap(slas, 1);
    }

    function testRequestDataCapExpirationBelowFiveYearsRevert() public {
        resolveAddress.setId(uint64(10000));
        address beneficiaryEthAddressContract = FilAddressIdConverter.toAddress(10000);
        mockBeneficiaryFactory.setInstance(SP1, beneficiaryEthAddressContract);
        slas[0].provider = SP1;
        vm.expectRevert(abi.encodeWithSelector(GetBeneficiary.ExpirationBelowFiveYears.selector));
        slaAllocator.requestDataCap(slas, 1);
    }

    function testRequestDataCapNoBeneficiarySetRevert() public {
        slas[0].provider = SP4;
        vm.expectRevert(abi.encodeWithSelector(GetBeneficiary.NoBeneficiarySet.selector));
        slaAllocator.requestDataCap(slas, 1);
    }

    function testRequestDataCapQuotaCannotBeNegativeRevert() public {
        resolveAddress.setId(uint64(50000));
        address beneficiaryEthAddressContract = FilAddressIdConverter.toAddress(50000);
        mockBeneficiaryFactory.setInstance(SP5, beneficiaryEthAddressContract);
        slas[0].provider = SP5;
        vm.expectRevert(abi.encodeWithSelector(GetBeneficiary.QuotaCannotBeNegative.selector));
        slaAllocator.requestDataCap(slas, 1);
    }

    function testRequestDataCapSucceed() public {
        resolveAddress.setId(uint64(20000));
        address beneficiaryEthAddressContract = FilAddressIdConverter.toAddress(20000);
        mockBeneficiaryFactory.setInstance(SP2, beneficiaryEthAddressContract);
        slas[0].provider = SP2;
        slaAllocator.requestDataCap(slas, 1);
    }

    function testGetBeneficiaryExpectRevertExitCodeError() public {
        slas[0].provider = CommonTypes.FilActorId.wrap(uint64(12345));
        vm.expectRevert(abi.encodeWithSelector(GetBeneficiary.ExitCodeError.selector));
        slaAllocator.requestDataCap(slas, 1);
    }

    function testRequestDataCapQuotaNotUnlimitedRevert() public {
        resolveAddress.setId(uint64(60000));
        address beneficiaryEthAddressContract = FilAddressIdConverter.toAddress(60000);
        mockBeneficiaryFactory.setInstance(SP6, beneficiaryEthAddressContract);
        slas[0].provider = SP6;
        vm.expectRevert(abi.encodeWithSelector(GetBeneficiary.QuotaNotUnlimited.selector));
        slaAllocator.requestDataCap(slas, 1);
    }

    function testRequestDataCapSingleClientPerSP() public {
        resolveAddress.setId(uint64(20000));
        address beneficiaryEthAddressContract = FilAddressIdConverter.toAddress(20000);
        mockBeneficiaryFactory.setInstance(SP2, beneficiaryEthAddressContract);
        slas[0].provider = SP2;
        slaAllocator.requestDataCap(slas, 1);

        resolveAddress.setId(uint64(50000));
        beneficiaryEthAddressContract = FilAddressIdConverter.toAddress(50000);
        mockBeneficiaryFactory.setInstance(SP2, beneficiaryEthAddressContract);
        vm.prank(vm.addr(5));
        vm.expectRevert(abi.encodeWithSelector(SLAAllocator.ProviderBoundToDifferentClient.selector));
        slaAllocator.requestDataCap(slas, 1);
    }

    function testRequestDataCapRevertInvalidBeneficiary() public {
        address beneficiaryEthAddressContract = FilAddressIdConverter.toAddress(20000);
        mockBeneficiaryFactory.setInstance(SP2, beneficiaryEthAddressContract);
        slas[0].provider = SP2;
        resolveAddress.setId(uint64(50000));
        beneficiaryEthAddressContract = FilAddressIdConverter.toAddress(50000);
        vm.expectRevert(abi.encodeWithSelector(GetBeneficiary.InvalidBeneficiary.selector, 50000, 20000));
        slaAllocator.requestDataCap(slas, 1);
    }

    function testRequestDataCapSameClientPerSPTwice() public {
        resolveAddress.setId(uint64(20000));
        address beneficiaryEthAddressContract = FilAddressIdConverter.toAddress(20000);
        mockBeneficiaryFactory.setInstance(SP2, beneficiaryEthAddressContract);
        slas[0].provider = SP2;
        slaAllocator.requestDataCap(slas, 1);
        slaAllocator.requestDataCap(slas, 1);
    }

    function testRequestDataCapExpectRevertFailedToGetActorID() public {
        ResolveAddressPrecompileFailingMock failingResolveAddress =
            ResolveAddressPrecompileFailingMock(payable(0xFE00000000000000000000000000000000000001));
        vm.etch(address(failingResolveAddress), address(resolveAddressPrecompileFailingMock).code);
        mockBeneficiaryFactory.setInstance(SP2, vm.addr(3));
        slas[0].provider = SP2;
        vm.expectRevert(abi.encodeWithSelector(GetBeneficiary.FailedToGetActorID.selector));
        slaAllocator.requestDataCap(slas, 1);
    }

    function testCantBeReinitialized() public {
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        slaAllocator.initialize(address(2), address(2));

        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        slaAllocator.initialize2(Client(address(2)), BeneficiaryFactory(address(1)));
    }

    function testDecreaseAllowanceRevertUnathorized() public {
        bytes32 managerRole = slaAllocator.MANAGER_ROLE();

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), managerRole)
        );
        slaAllocator.mintDataCap(1000);
    }

    function testMintDataCap() public {
        vm.prank(manager);
        slaAllocator.mintDataCap(1000);
    }

    function testMintDataCapEmitEvent() public {
        vm.prank(manager);
        vm.expectEmit(true, true, true, true);
        emit SLAAllocator.DatacapAllocated(manager, clientSmartContract, 1000);
        slaAllocator.mintDataCap(1000);
    }

    function testMintDatacapRevertAmountEqualZero() public {
        vm.prank(manager);
        vm.expectRevert(SLAAllocator.AmountEqualZero.selector);
        slaAllocator.mintDataCap(0);
    }

    function testMintDataCapRevertExitCodeError() public {
        ActorIdExitCodeErrorFailingMock actorIdFailingExitCodeErrorMock = new ActorIdExitCodeErrorFailingMock();
        vm.etch(CALL_ACTOR_ID, address(actorIdFailingExitCodeErrorMock).code);
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(SLAAllocator.ExitCodeError.selector, 1));
        slaAllocator.mintDataCap(1000);
    }

    function testMintDataCapRevertInvalidResponseLength() public {
        ActorIdInvalidResponseLengthFailingMock actorIdInvalidResponseLengthFailingMock =
            new ActorIdInvalidResponseLengthFailingMock();
        vm.etch(CALL_ACTOR_ID, address(actorIdInvalidResponseLengthFailingMock).code);
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(Actor.InvalidResponseLength.selector));
        slaAllocator.mintDataCap(1000);
    }

    function testIsManagerSet() public view {
        bytes32 managerRole = slaAllocator.MANAGER_ROLE();
        assertTrue(slaAllocator.hasRole(managerRole, manager));
    }

    function testIsBeneficiaryFactorySet() public view {
        assertEq(address(slaAllocator.beneficiaryFactory()), address(mockBeneficiaryFactory));
    }

    function testIsClientSmartContractSet() public view {
        assertEq(address(slaAllocator.clientSmartContract()), address(clientSmartContract));
    }

    function testGetProvidersReturnsAddedProviders() public {
        resolveAddress.setId(uint64(20000));
        address beneficiaryEthAddressContract = FilAddressIdConverter.toAddress(20000);
        mockBeneficiaryFactory.setInstance(SP2, beneficiaryEthAddressContract);
        slas[0].provider = SP2;
        slaAllocator.requestDataCap(slas, 1);

        CommonTypes.FilActorId[] memory providers = slaAllocator.getProviders();
        assertEq(providers.length, 1);

        uint64 got = uint64(CommonTypes.FilActorId.unwrap(providers[0]));
        uint64 expected = uint64(CommonTypes.FilActorId.unwrap(SP2));
        assertEq(got, expected);
    }

    function testAddProvider() public {
        vm.startPrank(manager);
        CommonTypes.FilActorId[] memory providers;

        providers = slaAllocator.getProviders();
        assertEq(providers.length, 0);

        slaAllocator.addProvider(CommonTypes.FilActorId.wrap(1));
        providers = slaAllocator.getProviders();
        assertEq(providers.length, 1);

        slaAllocator.addProvider(CommonTypes.FilActorId.wrap(1));
        providers = slaAllocator.getProviders();
        assertEq(providers.length, 1);

        vm.stopPrank();
        bytes32 expectedRole = slaAllocator.MANAGER_ROLE();
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, unauthorized, expectedRole)
        );
        slaAllocator.addProvider(CommonTypes.FilActorId.wrap(2));
    }

    function testSetBeneficiaryFactory() public {
        BeneficiaryFactory newBeneficiaryFactory = new BeneficiaryFactory();
        vm.prank(admin);
        slaAllocator.setBeneficiaryFactory(newBeneficiaryFactory);
        assertEq(address(slaAllocator.beneficiaryFactory()), address(newBeneficiaryFactory));
    }

    function testSetBeneficiaryFactoryEmitEvent() public {
        BeneficiaryFactory newBeneficiaryFactory = new BeneficiaryFactory();
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit SLAAllocator.BeneficiaryFactorySet(newBeneficiaryFactory);
        slaAllocator.setBeneficiaryFactory(newBeneficiaryFactory);
    }

    function testSetBeneficiaryFactoryRevertUnauthorized() public {
        BeneficiaryFactory newBeneficiaryFactory = new BeneficiaryFactory();
        bytes32 adminRole = slaAllocator.DEFAULT_ADMIN_ROLE();
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, unauthorized, adminRole)
        );
        slaAllocator.setBeneficiaryFactory(newBeneficiaryFactory);
    }

    function testSetClientSmartContract() public {
        Client newClientSmartContract = new Client();
        vm.prank(admin);
        slaAllocator.setClientSmartContract(newClientSmartContract);
        assertEq(address(slaAllocator.clientSmartContract()), address(newClientSmartContract));
    }

    function testSetClientSmartContractEmitEvent() public {
        Client newClientSmartContract = new Client();
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit SLAAllocator.ClientSmartContractSet(newClientSmartContract);
        slaAllocator.setClientSmartContract(newClientSmartContract);
    }

    function testSetClientSmartContractRevertUnauthorized() public {
        Client newClientSmartContract = new Client();
        bytes32 adminRole = slaAllocator.DEFAULT_ADMIN_ROLE();
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, unauthorized, adminRole)
        );
        slaAllocator.setClientSmartContract(newClientSmartContract);
    }
}
