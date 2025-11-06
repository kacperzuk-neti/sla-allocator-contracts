// SPDX-License-Identifier: MIT
// solhint-disable use-natspec
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";

import {BeneficiaryFactory} from "../src/BeneficiaryFactory.sol";
import {Client} from "../src/Client.sol";
import {GetBeneficiary} from "../src/libs/GetBeneficiary.sol";
import {SLAAllocator} from "../src/SLAAllocator.sol";
import {SLARegistry} from "../src/SLAAllocator.sol";

import {ActorIdMock} from "./contracts/ActorIdMock.sol";
import {MockClient} from "./contracts/MockClient.sol";
import {MockProxy} from "./contracts/MockProxy.sol";
import {MockSLARegistry} from "./contracts/MockSLARegistry.sol";

contract SLAAllocatorTest is Test {
    SLAAllocator public slaAllocator;
    MockSLARegistry public slaRegistry;
    SLAAllocator.SLA[] public slas;
    ActorIdMock public actorIdMock;
    address public constant CALL_ACTOR_ID = 0xfe00000000000000000000000000000000000005;

    // solhint-disable var-name-mixedcase
    CommonTypes.FilActorId public SP1 = CommonTypes.FilActorId.wrap(uint64(10000));
    CommonTypes.FilActorId public SP2 = CommonTypes.FilActorId.wrap(uint64(20000));
    CommonTypes.FilActorId public SP3 = CommonTypes.FilActorId.wrap(uint64(30000));
    CommonTypes.FilActorId public SP4 = CommonTypes.FilActorId.wrap(uint64(40000));
    CommonTypes.FilActorId public SP5 = CommonTypes.FilActorId.wrap(uint64(50000));
    CommonTypes.FilActorId public SP6 = CommonTypes.FilActorId.wrap(uint64(60000));
    CommonTypes.FilActorId public client = CommonTypes.FilActorId.wrap(uint64(11111));
    // solhint-enable var-name-mixedcase

    function setUp() public {
        actorIdMock = new ActorIdMock();
        address actorIdProxy = address(new MockProxy(address(5555)));
        vm.etch(CALL_ACTOR_ID, address(actorIdMock).code);
        vm.etch(address(5555), address(actorIdProxy).code);
        BeneficiaryFactory beneficiaryFactory = new BeneficiaryFactory();
        Client clientSmartContract = Client(address(new MockClient()));
        slaRegistry = new MockSLARegistry();

        SLAAllocator impl = new SLAAllocator();
        bytes memory initData = abi.encodeCall(SLAAllocator.initialize, (address(this)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        slaAllocator = SLAAllocator(address(proxy));
        slaAllocator.initialize2(clientSmartContract, beneficiaryFactory);

        slas.push(SLAAllocator.SLA(SLARegistry(address(slaRegistry)), SP1));
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

    function testRequestDataCapExpirationBelowFiveYearsRevert() public {
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
        slas[0].provider = SP5;
        vm.expectRevert(abi.encodeWithSelector(GetBeneficiary.QuotaCannotBeNegative.selector));
        slaAllocator.requestDataCap(slas, 1);
    }

    function testRequestDataCapSucceed() public {
        slas[0].provider = SP2;
        slaAllocator.requestDataCap(slas, 1);
    }

    function testGetBeneficiaryExpectRevertExitCodeError() public {
        slas[0].provider = CommonTypes.FilActorId.wrap(uint64(12345));
        vm.expectRevert(abi.encodeWithSelector(GetBeneficiary.ExitCodeError.selector));
        slaAllocator.requestDataCap(slas, 1);
    }

    function testRequestDataCapQuotaNotUnlimitedRevert() public {
        slas[0].provider = SP6;
        vm.expectRevert(abi.encodeWithSelector(GetBeneficiary.QuotaNotUnlimited.selector));
        slaAllocator.requestDataCap(slas, 1);
    }

    function testRequestDataCapSingleClientPerSP() public {
        slas[0].provider = SP2;
        slaAllocator.requestDataCap(slas, 1);

        vm.prank(vm.addr(5));
        vm.expectRevert(abi.encodeWithSelector(SLAAllocator.ProviderBoundToDifferentClient.selector));
        slaAllocator.requestDataCap(slas, 1);
    }

    function testRequestDataCapSameClientPerSPTwice() public {
        slas[0].provider = SP2;
        slaAllocator.requestDataCap(slas, 1);
        slaAllocator.requestDataCap(slas, 1);
    }

    function testCantBeReinitialized() public {
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        slaAllocator.initialize(address(2));

        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        slaAllocator.initialize2(Client(address(2)), BeneficiaryFactory(address(1)));
    }
}
