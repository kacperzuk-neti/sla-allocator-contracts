// SPDX-License-Identifier: MIT
// solhint-disable use-natspec

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {Actor} from "filecoin-solidity/v0.8/utils/Actor.sol";
import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";
import {FilAddresses} from "filecoin-solidity/v0.8/utils/FilAddresses.sol";
import {MinerTypes} from "filecoin-solidity/v0.8/types/MinerTypes.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {Beneficiary} from "../src/Beneficiary.sol";
import {SLAAllocator} from "../src/SLAAllocator.sol";
import {MinerUtils} from "../src/libs/MinerUtils.sol";

import {MockProxy} from "./contracts/MockProxy.sol";
import {MockSLAAllocator} from "./contracts/MockSLAAllocator.sol";
import {ActorAddressMock} from "./contracts/ActorAddressMock.sol";
import {ActorIdMock} from "./contracts/ActorIdMock.sol";
import {FilAddressIdConverter} from "filecoin-solidity/v0.8/utils/FilAddressIdConverter.sol";
import {ResolveAddressPrecompileMock} from "../test/contracts/ResolveAddressPrecompileMock.sol";
import {ResolveAddressPrecompileFailingMock} from "../test/contracts/ResolveAddressPrecompileFailingMock.sol";
import {MockBeneficiaryFactory} from "./contracts/MockBeneficiaryFactory.sol";
import {Client} from "../src/Client.sol";
// import {DataCapTypes} from "filecoin-solidity/v0.8/types/DataCapTypes.sol";
import {MockClient} from "./contracts/MockClient.sol";

// solhint-disable-next-line max-states-count
contract BeneficiaryTest is Test {
    Beneficiary public beneficiary;
    ActorIdMock public actorIdMock;
    ActorAddressMock public actorAddressMock;
    MockBeneficiaryFactory public mockBeneficiaryFactory;
    Client public mockClient;
    ResolveAddressPrecompileMock public resolveAddress =
        ResolveAddressPrecompileMock(payable(0xFE00000000000000000000000000000000000001));
    ResolveAddressPrecompileMock public resolveAddressPrecompileMock;
    CommonTypes.FilActorId public provider = CommonTypes.FilActorId.wrap(0x999);
    SLAAllocator public slaAllocator;
    address public manager = vm.addr(1);
    address public burnAddress = vm.addr(2);
    address public terminationOracle = vm.addr(3);
    address public clientAddress = vm.addr(1000);
    address public constant CALL_ACTOR_ID = 0xfe00000000000000000000000000000000000005;
    address public constant CALL_ACTOR_ADDRESS = 0xfe00000000000000000000000000000000000003;

    // solhint-disable var-name-mixedcase
    CommonTypes.FilActorId public SP1 = CommonTypes.FilActorId.wrap(uint64(10000));
    CommonTypes.FilActorId public SP2 = CommonTypes.FilActorId.wrap(uint64(20000));
    CommonTypes.FilActorId public SP3 = CommonTypes.FilActorId.wrap(uint64(30000));
    CommonTypes.FilActorId public SP5 = CommonTypes.FilActorId.wrap(uint64(50000));
    CommonTypes.FilActorId public SP7 = CommonTypes.FilActorId.wrap(uint64(70000));
    CommonTypes.FilActorId public SP8 = CommonTypes.FilActorId.wrap(uint64(80000));
    CommonTypes.FilActorId public SP6 = CommonTypes.FilActorId.wrap(uint64(60000));
    CommonTypes.FilActorId public SP9 = CommonTypes.FilActorId.wrap(uint64(90000));
    CommonTypes.FilActorId public SP10 = CommonTypes.FilActorId.wrap(uint64(100000));
    CommonTypes.FilActorId public beneficiaryContractId = CommonTypes.FilActorId.wrap(uint64(1022));

    CommonTypes.FilAddress public SP1Address = FilAddresses.fromActorID(CommonTypes.FilActorId.unwrap(SP1));
    CommonTypes.FilAddress public SP2Address = FilAddresses.fromActorID(CommonTypes.FilActorId.unwrap(SP2));
    CommonTypes.FilAddress public SP3Address = FilAddresses.fromActorID(CommonTypes.FilActorId.unwrap(SP3));
    CommonTypes.FilAddress public SP7Address = FilAddresses.fromActorID(CommonTypes.FilActorId.unwrap(SP7));
    CommonTypes.FilAddress public SP8Address = FilAddresses.fromActorID(CommonTypes.FilActorId.unwrap(SP8));
    CommonTypes.FilAddress public beneficiaryContractAddress =
        FilAddresses.fromActorID(CommonTypes.FilActorId.unwrap(beneficiaryContractId));
    bytes public transferTo = abi.encodePacked(vm.addr(5));
    address public beneficiaryEthAddressContract;
    // solhint-enable var-name-mixedcase
    function setUp() public {
        actorIdMock = new ActorIdMock();
        actorAddressMock = new ActorAddressMock();
        address actorIdProxy = address(new MockProxy(address(5555)));
        address actorAddressProxy = address(new MockProxy(address(6666)));
        mockBeneficiaryFactory = new MockBeneficiaryFactory();
        resolveAddressPrecompileMock = new ResolveAddressPrecompileMock();
        mockClient = Client(address(new MockClient()));
        slaAllocator = SLAAllocator(address(new MockSLAAllocator()));

        vm.etch(CALL_ACTOR_ID, address(actorIdProxy).code);
        vm.etch(CALL_ACTOR_ADDRESS, address(actorAddressProxy).code);
        vm.etch(address(5555), address(actorIdMock).code);
        actorIdMock = ActorIdMock(payable(address(5555)));
        vm.etch(address(6666), address(actorAddressMock).code);
        vm.etch(address(resolveAddress), address(resolveAddressPrecompileMock).code);
        resolveAddress.setId(address(this), uint64(1022));
        resolveAddressPrecompileMock.setId(address(9999), uint64(1023));

        beneficiary = setupBeneficiary(address(this), manager, provider, slaAllocator, burnAddress);
        actorIdMock.setGetClaimsResult(
            hex"8282018081881903E81866D82A5828000181E203922020071E414627E89D421B3BAFCCB24CBA13DDE9B6F388706AC8B1D48E58935C76381908001A003815911A005034D60000"
        );
    }

    function setupBeneficiary(
        address admin_,
        address withdrawer_,
        CommonTypes.FilActorId provider_,
        SLAAllocator slaAllocator_,
        address burnAddress_
    ) public returns (Beneficiary) {
        Beneficiary impl = new Beneficiary();

        // solhint-disable gas-small-strings
        bytes memory initData = abi.encodeCall(
            Beneficiary.initialize, (admin_, withdrawer_, provider_, slaAllocator_, burnAddress_, mockClient)
        );
        // solhint-enable gas-small-strings
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        return Beneficiary(payable(address(proxy)));
    }

    function testIsAdminSet() public view {
        bytes32 adminRole = beneficiary.DEFAULT_ADMIN_ROLE();
        assertTrue(beneficiary.hasRole(adminRole, address(this)));
    }

    function testIsManagerSet() public view {
        bytes32 managerRole = beneficiary.MANAGER_ROLE();
        assertTrue(beneficiary.hasRole(managerRole, manager));
    }

    function testIsWithdrawerSet() public view {
        bytes32 withdrawerRole = beneficiary.WITHDRAWER_ROLE();
        assertTrue(beneficiary.hasRole(withdrawerRole, manager));
    }

    function testIsManagerSetAsWithdrawerRoleAdmin() public view {
        bytes32 managerRole = beneficiary.MANAGER_ROLE();
        bytes32 withdrawerRole = beneficiary.WITHDRAWER_ROLE();
        assertTrue(beneficiary.getRoleAdmin(withdrawerRole) == managerRole);
    }

    function testSetBurnAddress() public {
        beneficiary.setBurnAddress(address(0x123));
        assertEq(beneficiary.burnAddress(), address(0x123));
    }

    function testSetBurnAddressEmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit Beneficiary.BurnAddressUpdated(address(0x123));
        beneficiary.setBurnAddress(address(0x123));
    }

    function testSetBurnAddressRevert() public {
        address notAdmin = address(0x333);
        bytes32 expectedRole = beneficiary.DEFAULT_ADMIN_ROLE();
        vm.prank(notAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, notAdmin, expectedRole)
        );
        beneficiary.setBurnAddress(address(0x123));
    }

    function testWithdrawForGreenBand() public {
        vm.deal(address(beneficiary), 10000);
        vm.startPrank(manager);
        vm.expectEmit(true, true, true, true);
        emit Beneficiary.Withdrawn(SP1Address, 10000, 0);
        beneficiary.withdraw(SP1Address);
    }

    function testWithdrawForAmberBand() public {
        CommonTypes.FilActorId providerWithAmberBandScore = CommonTypes.FilActorId.wrap(0x123);
        beneficiary = setupBeneficiary(address(this), manager, providerWithAmberBandScore, slaAllocator, burnAddress);
        vm.deal(address(beneficiary), 10000);
        vm.startPrank(manager);
        vm.expectEmit(true, true, true, true);

        emit Beneficiary.Withdrawn(SP1Address, 5000, 5000);
        beneficiary.withdraw(SP1Address);
    }

    function testWithdrawForRedBand() public {
        CommonTypes.FilActorId providerWithRedBandScore = CommonTypes.FilActorId.wrap(0x456);
        beneficiary = setupBeneficiary(address(this), manager, providerWithRedBandScore, slaAllocator, burnAddress);
        vm.deal(address(beneficiary), 10000);
        vm.startPrank(manager);
        vm.expectEmit(true, true, true, true);

        emit Beneficiary.Withdrawn(SP1Address, 1000, 9000);
        beneficiary.withdraw(SP1Address);
    }

    function testWithddrawRevertsWhenNotWithdrawer() public {
        address notWithdrawer = address(0x123);
        bytes32 expectedRole = beneficiary.WITHDRAWER_ROLE();
        vm.prank(notWithdrawer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, notWithdrawer, expectedRole
            )
        );
        beneficiary.withdraw(SP1Address);
    }

    function testRevertsWithdrawalFailed() public {
        vm.deal(address(beneficiary), 10000);
        vm.startPrank(manager);
        vm.expectRevert(abi.encodeWithSelector(Beneficiary.WithdrawalFailed.selector));

        beneficiary.withdraw(SP2Address);
    }

    function testSetWithdrawerRoleAndRevoke() public {
        bytes32 withdrawerRole = beneficiary.WITHDRAWER_ROLE();
        vm.startPrank(manager);

        beneficiary.grantRole(withdrawerRole, address(0x123));
        assertTrue(beneficiary.hasRole(withdrawerRole, address(0x123)));
        beneficiary.revokeRole(withdrawerRole, address(0x123));
        assertFalse(beneficiary.hasRole(withdrawerRole, address(0x123)));
    }

    function testInvalidResponseLength() public {
        vm.deal(address(beneficiary), 10000);
        vm.startPrank(manager);
        vm.expectRevert(abi.encodeWithSelector(Actor.InvalidResponseLength.selector));
        beneficiary.withdraw(SP3Address);
    }

    function testRevertsAccessControlWhenNotManagerWhenGrantingWithdrawerRole() public {
        address notManager = address(0x333);
        bytes32 managerRole = beneficiary.MANAGER_ROLE();
        bytes32 withdrawerRole = beneficiary.WITHDRAWER_ROLE();
        vm.prank(notManager);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, notManager, managerRole)
        );
        beneficiary.grantRole(withdrawerRole, address(0x123));
    }

    function testGetBeneficiaryForSP1() public view {
        MinerTypes.GetBeneficiaryReturn memory result = MinerUtils.getBeneficiary(SP1);
        assertEq(result.active.beneficiary.data, hex"00c2a101");
    }

    function testGetBeneficiaryForSP2() public view {
        MinerTypes.GetBeneficiaryReturn memory result = MinerUtils.getBeneficiary(SP2);
        assertEq(result.active.beneficiary.data, hex"00c2a101");
    }

    function testGetBeneficiaryForSP3() public view {
        MinerTypes.GetBeneficiaryReturn memory result = MinerUtils.getBeneficiary(SP3);
        assertEq(result.active.beneficiary.data, hex"00C2A101");
    }

    function testGetBeneficiaryPendingChangeForSP3() public view {
        MinerTypes.GetBeneficiaryReturn memory result = MinerUtils.getBeneficiary(SP3);
        assertEq(result.proposed.new_beneficiary.data, hex"00D4C101");
    }

    function testGetBeneficiaryWithChecksForSP7() public {
        resolveAddress.setAddress(hex"00FE07", uint64(1022));
        beneficiaryEthAddressContract = FilAddressIdConverter.toAddress(1022);
        mockBeneficiaryFactory.setInstance(SP7, beneficiaryEthAddressContract);
        MinerUtils.getBeneficiaryWithChecks(SP7, mockBeneficiaryFactory, true, true, false);
    }

    function testChangeBeneficiaryExpectRevertInvalidResponseLength() public {
        vm.expectRevert(abi.encodeWithSelector(Actor.InvalidResponseLength.selector));
        beneficiary.changeBeneficiary(
            CommonTypes.FilActorId.wrap(12345), FilAddresses.fromBytes(hex"00fb07"), 1000, 6000000
        );
    }

    function testChangeBeneficiaryExpectRevertExitCodeError() public {
        vm.expectRevert(abi.encodeWithSelector(Beneficiary.ExitCodeError.selector, 1));
        beneficiary.changeBeneficiary(
            CommonTypes.FilActorId.wrap(10000), FilAddresses.fromBytes(hex"00fb07"), 1000, 6000000
        );
    }

    function testChangeBeneficiaryEmitEvent() public {
        vm.expectEmit(true, true, true, true);
        emit Beneficiary.BeneficiaryProposalSigned(
            CommonTypes.FilActorId.wrap(20000), FilAddresses.fromBytes(hex"00fb07"), 1000, 6000000
        );
        beneficiary.changeBeneficiary(
            CommonTypes.FilActorId.wrap(20000), FilAddresses.fromBytes(hex"00fb07"), 1000, 6000000
        );
    }

    function testSetSLAAllocator() public {
        SLAAllocator newSLAAllocator = SLAAllocator(address(0x123));
        beneficiary.setSLAAllocator(newSLAAllocator);
        assertEq(address(beneficiary.slaAllocator()), address(newSLAAllocator));
    }

    function testSetSLAAllocatorEmitsEvent() public {
        SLAAllocator newSLAAllocator = SLAAllocator(address(0x123));
        vm.expectEmit(true, true, true, true);
        emit Beneficiary.SLAAllocatorUpdated(newSLAAllocator);
        beneficiary.setSLAAllocator(newSLAAllocator);
    }

    function testSetSLAAllocatorRevert() public {
        address notAdmin = address(0x333);
        bytes32 expectedRole = beneficiary.DEFAULT_ADMIN_ROLE();
        vm.prank(notAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, notAdmin, expectedRole)
        );
        beneficiary.setSLAAllocator(SLAAllocator(address(0x123)));
    }

    // solhint-disable-next-line no-empty-blocks
    function testChangeBeneficiaryCalldata() public {
        // FIXME verify that miner is called correctly for changeBeneficiary
    }

    function testChangeBeneficiaryRevertWhenNotAdmin() public {
        address notAdmin = address(0x333);
        bytes32 expectedRole = beneficiary.DEFAULT_ADMIN_ROLE();
        vm.prank(notAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, notAdmin, expectedRole)
        );
        beneficiary.changeBeneficiary(
            CommonTypes.FilActorId.wrap(20000), FilAddresses.fromBytes(hex"00fb07"), 1000, 6000000
        );
    }

    function testAcceptBeneficiaryRevertsWhenNoPendingChange() public {
        vm.expectRevert(MinerUtils.NoNewBeneficiaryProposed.selector);
        beneficiary.acceptBeneficiary(SP7);
    }

    function testAcceptBeneficiaryRevertsWhenNewBeneficiaryIsNotThisContract() public {
        resolveAddress.setId(address(beneficiary), uint64(1023));
        resolveAddress.setAddress(hex"00D4C101", uint64(9999));

        vm.expectRevert(abi.encodeWithSelector(MinerUtils.InvalidNewBeneficiary.selector, 1023, 9999));
        beneficiary.acceptBeneficiary(SP3);
    }

    function shouldAcceptBeneficiary() public {
        resolveAddress.setId(address(beneficiary), uint64(1023));
        resolveAddress.setAddress(hex"00D4C101", uint64(1023));
        vm.expectEmit(true, true, true, true);
        emit Beneficiary.BeneficiaryAccepted(SP3, FilAddresses.fromBytes(hex"00fb07"));
        beneficiary.acceptBeneficiary(SP3);
    }

    function testAcceptBeneficiaryCallableByAnyone() public {
        address randomCaller = address(0x1234);
        vm.prank(randomCaller);
        vm.expectRevert(MinerUtils.NoNewBeneficiaryProposed.selector);
        beneficiary.acceptBeneficiary(SP7);
    }

    function testShouldRevertAcceptWhenChangeReverts() public {
        resolveAddress.setId(address(beneficiary), uint64(1023));
        resolveAddress.setAddress(hex"00C2A101", uint64(1023));
        resolveAddress.setAddress(hex"00D4C101", uint64(1023));
        vm.expectRevert(abi.encodeWithSelector(Beneficiary.ExitCodeError.selector, 1));
        beneficiary.acceptBeneficiary(SP8);
    }

    function testShouldRevertAcceptWhenQuotaIsNotUnlimited() public {
        resolveAddress.setId(address(beneficiary), uint64(1023));
        resolveAddress.setAddress(hex"00C2A101", uint64(1024));
        resolveAddress.setAddress(hex"00D4C101", uint64(1023));
        vm.expectRevert(abi.encodeWithSelector(MinerUtils.QuotaNotUnlimited.selector));
        beneficiary.acceptBeneficiary(SP6);
    }

    function testShouldRevertWhenGetActorResolvesWithFalse() public {
        ResolveAddressPrecompileFailingMock failingResolveAddress =
            ResolveAddressPrecompileFailingMock(payable(0xFE00000000000000000000000000000000000001));
        vm.etch(address(failingResolveAddress), address(failingResolveAddress).code);
        vm.expectRevert(abi.encodeWithSelector(MinerUtils.FailedToGetActorID.selector));
        beneficiary.acceptBeneficiary(SP3);
    }

    function testShouldRevertWhenNewQuotaIsBelowActive() public {
        resolveAddress.setId(address(beneficiary), uint64(1023));
        resolveAddress.setAddress(hex"00C2A101", uint64(1023));
        resolveAddress.setAddress(hex"00D4C101", uint64(1023));
        vm.expectRevert(abi.encodeWithSelector(MinerUtils.NewQuotaBelowActive.selector));
        beneficiary.acceptBeneficiary(SP9);
    }

    function testShouldRevertWhenNewExpirationIsBelowActive() public {
        resolveAddress.setId(address(beneficiary), uint64(1023));
        resolveAddress.setAddress(hex"00C2A101", uint64(1023));
        resolveAddress.setAddress(hex"00D4C101", uint64(1023));
        vm.expectRevert(abi.encodeWithSelector(MinerUtils.NewExpirationBelowActive.selector));
        beneficiary.acceptBeneficiary(SP10);
    }
}
