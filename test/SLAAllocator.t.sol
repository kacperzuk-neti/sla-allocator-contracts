// SPDX-License-Identifier: MIT
// solhint-disable use-natspec
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";

import {BeneficiaryFactory} from "../src/BeneficiaryFactory.sol";
import {Client} from "../src/Client.sol";
import {MinerUtils} from "../src/libs/MinerUtils.sol";
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
import {VerifySignaturesHelper} from "../test/contracts/VerifySignaturesHelper.sol";

// solhint-disable-next-line max-states-count
contract SLAAllocatorTest is Test {
    SLAAllocator public slaAllocator;
    MockSLARegistry public slaRegistry;
    VerifySignaturesHelper public verifySignaturesHelper;
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
    uint256 public unauthorizedKey = 0xBBB;
    address public unauthorized = vm.addr(unauthorizedKey);
    uint256 public attestorKey = 0xAAA;
    address public attestor = vm.addr(attestorKey);

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
        VerifySignaturesHelper impl2 = new VerifySignaturesHelper();
        bytes memory initData = abi.encodeCall(SLAAllocator.initialize, (admin, manager, attestor));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        ERC1967Proxy proxyHelper = new ERC1967Proxy(address(impl2), initData);
        slaAllocator = SLAAllocator(address(proxy));
        slaAllocator.initialize2(clientSmartContract, mockBeneficiaryFactory);
        verifySignaturesHelper = VerifySignaturesHelper(address(proxyHelper));
        verifySignaturesHelper.initialize2(clientSmartContract, mockBeneficiaryFactory);

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
        vm.expectRevert(abi.encodeWithSelector(MinerUtils.BeneficiaryInstanceNonexistent.selector));
        slaAllocator.requestDataCap(slas, 1);
    }

    function testRequestDataCapExpirationBelowFiveYearsRevert() public {
        resolveAddress.setId(address(this), uint64(10000));
        resolveAddress.setAddress(hex"00C2A101", uint64(10000));
        address beneficiaryEthAddressContract = FilAddressIdConverter.toAddress(10000);
        mockBeneficiaryFactory.setInstance(SP1, beneficiaryEthAddressContract);
        slas[0].provider = SP1;
        vm.expectRevert(abi.encodeWithSelector(MinerUtils.ExpirationBelowFiveYears.selector));
        slaAllocator.requestDataCap(slas, 1);
    }

    function testRequestDataCapNoBeneficiarySetRevert() public {
        slas[0].provider = SP4;
        vm.expectRevert(abi.encodeWithSelector(MinerUtils.NoBeneficiarySet.selector));
        slaAllocator.requestDataCap(slas, 1);
    }

    function testRequestDataCapQuotaCannotBeNegativeRevert() public {
        resolveAddress.setId(address(this), uint64(50000));
        resolveAddress.setAddress(hex"00C2A101", uint64(50000));
        address beneficiaryEthAddressContract = FilAddressIdConverter.toAddress(50000);
        mockBeneficiaryFactory.setInstance(SP5, beneficiaryEthAddressContract);
        slas[0].provider = SP5;
        vm.expectRevert(abi.encodeWithSelector(MinerUtils.QuotaCannotBeNegative.selector));
        slaAllocator.requestDataCap(slas, 1);
    }

    function testRequestDataCapSucceed() public {
        resolveAddress.setId(address(this), uint64(20000));
        resolveAddress.setAddress(hex"00C2A101", uint64(20000));
        address beneficiaryEthAddressContract = FilAddressIdConverter.toAddress(20000);
        mockBeneficiaryFactory.setInstance(SP2, beneficiaryEthAddressContract);
        slas[0].provider = SP2;
        slaAllocator.requestDataCap(slas, 1);
    }

    function testGetBeneficiaryExpectRevertExitCodeError() public {
        slas[0].provider = CommonTypes.FilActorId.wrap(uint64(12345));
        vm.expectRevert(abi.encodeWithSelector(MinerUtils.ExitCodeError.selector));
        slaAllocator.requestDataCap(slas, 1);
    }

    function testRequestDataCapQuotaNotUnlimitedRevert() public {
        resolveAddress.setId(address(this), uint64(60000));
        resolveAddress.setAddress(hex"00C2A101", uint64(60000));
        address beneficiaryEthAddressContract = FilAddressIdConverter.toAddress(60000);
        mockBeneficiaryFactory.setInstance(SP6, beneficiaryEthAddressContract);
        slas[0].provider = SP6;
        vm.expectRevert(abi.encodeWithSelector(MinerUtils.QuotaNotUnlimited.selector));
        slaAllocator.requestDataCap(slas, 1);
    }

    function testRequestDataCapSingleClientPerSP() public {
        resolveAddress.setId(address(this), uint64(20000));
        resolveAddress.setAddress(hex"00C2A101", uint64(20000));
        address beneficiaryEthAddressContract = FilAddressIdConverter.toAddress(20000);
        mockBeneficiaryFactory.setInstance(SP2, beneficiaryEthAddressContract);
        slas[0].provider = SP2;
        slaAllocator.requestDataCap(slas, 1);

        resolveAddress.setId(address(this), uint64(50000));
        resolveAddress.setAddress(hex"00C2A101", uint64(50000));
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
        resolveAddress.setId(address(this), uint64(50000));
        resolveAddress.setAddress(hex"00C2A101", uint64(50000));
        beneficiaryEthAddressContract = FilAddressIdConverter.toAddress(50000);
        vm.expectRevert(abi.encodeWithSelector(MinerUtils.InvalidBeneficiary.selector, 50000, 20000));
        slaAllocator.requestDataCap(slas, 1);
    }

    function testRequestDataCapSameClientPerSPTwice() public {
        resolveAddress.setId(address(this), uint64(20000));
        resolveAddress.setAddress(hex"00C2A101", uint64(20000));
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
        vm.expectRevert(abi.encodeWithSelector(MinerUtils.FailedToGetActorID.selector));
        slaAllocator.requestDataCap(slas, 1);
    }

    function testCantBeReinitialized() public {
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        slaAllocator.initialize(address(2), address(2), address(3));

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
        resolveAddress.setId(address(this), uint64(20000));
        resolveAddress.setAddress(hex"00C2A101", uint64(20000));
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

    function testVerifyPassportSigned() public view {
        SLAAllocator.Passport memory passport = SLAAllocator.Passport({
            expirationTimestamp: 1, subject: 0x0000000000000000000000000000000000000123, score: 100
        });

        bytes32 structHash = verifySignaturesHelper.hashPassportExt(passport);
        bytes32 digestOnChain = verifySignaturesHelper.digestToSignExt(structHash);
        bytes32 digestOffChain = 0xe4473ea9d9322580ba9176aaf92e816e5fb409f88767d41e27362b59a923e3f4;

        assertEq(digestOnChain, digestOffChain);

        bytes memory signature =
            hex"efd096e7750ccf6608f0d3da8c469413085f2dd5c9aa1ecb2aa70c947d3dd56e3f62c9ff06dc1d300a4ec470723f0c167d4b751a044045c5fbd7458e83bf3ee91b";

        SLAAllocator.PassportSigned memory signed =
            SLAAllocator.PassportSigned({passport: passport, signature: signature});

        bool verified = verifySignaturesHelper.verifyPassportSignedExt(signed);
        assertTrue(verified, "Signature invalid");
    }

    function testVerifyPaymentTransactionSignature() public view {
        SLAAllocator.PaymentTransaction memory txn = SLAAllocator.PaymentTransaction({
            id: bytes("1"),
            from: CommonTypes.FilAddress({data: hex"f101"}),
            to: CommonTypes.FilAddress({data: hex"f102"}),
            amount: 1
        });

        bytes32 structHash = verifySignaturesHelper.hashPaymentTransactionExt(txn);
        bytes32 digestOnChain = verifySignaturesHelper.digestToSignExt(structHash);
        bytes32 digestOffChain = 0xeb2d73b584bf46b56d41777d6ff22c88a8c39d3638acda00f1216637c8935662;

        assertEq(digestOnChain, digestOffChain);

        bytes memory signature =
            hex"c8b3e98ca2aff787d06bcc4db12fbd586fdfef4093caf3ba730d734d4dadd2e2425f9daedcf6ecb2b52139bf354133b357b1a7e2d222285be29a2c7fbde185071b";

        SLAAllocator.PaymentTransactionSigned memory signed =
            SLAAllocator.PaymentTransactionSigned({txn: txn, signature: signature});

        bool verified = verifySignaturesHelper.verifyPaymentTransactionSignedExt(signed);
        assertTrue(verified, "Signature invalid");
    }

    function testVerifyManualAttestationSignature() public view {
        bytes32 attestationId = bytes32(uint256(1));

        SLAAllocator.ManualAttestation memory att = SLAAllocator.ManualAttestation({
            attestationId: attestationId,
            client: 0x0000000000000000000000000000000000000123,
            provider: SP1,
            amount: 1,
            opaqueData: "data"
        });

        bytes32 structHash = verifySignaturesHelper.hashManualAttestationExt(att);
        bytes32 digestOnChain = verifySignaturesHelper.digestToSignExt(structHash);
        bytes32 digestOffChain = 0xd78d976d5f4f8827cce3b16f23a691baafdf9269541d9a21b84233567d585000;

        assertEq(digestOnChain, digestOffChain);

        bytes memory signature =
            hex"f38955965e6619d56f115c4d617c5e94422b1d2e433495a03fd02fc7b7971e793455938c05fd526443886ee701c6875dca740f8f4c064d44118c3321891e01201c";

        SLAAllocator.ManualAttestationSigned memory signed =
            SLAAllocator.ManualAttestationSigned({attestation: att, signature: signature});

        bool verified = verifySignaturesHelper.verifyManualAttestationSignedExt(signed);
        assertTrue(verified, "Signature invalid");
    }

    function testVerifyPassportSignedWrongData() public view {
        SLAAllocator.Passport memory passport = SLAAllocator.Passport({
            expirationTimestamp: 1, subject: 0x0000000000000000000000000000000000000124, score: 100
        });

        bytes memory signature =
            hex"efd096e7750ccf6608f0d3da8c469413085f2dd5c9aa1ecb2aa70c947d3dd56e3f62c9ff06dc1d300a4ec470723f0c167d4b751a044045c5fbd7458e83bf3ee91b";

        SLAAllocator.PassportSigned memory signed =
            SLAAllocator.PassportSigned({passport: passport, signature: signature});

        bool notVerified = verifySignaturesHelper.verifyPassportSignedExt(signed);
        assertFalse(notVerified, "Signature valid");
    }

    function testVerifyPassportSignedWrongSignature() public {
        SLAAllocator.Passport memory passport = SLAAllocator.Passport({
            expirationTimestamp: 1, subject: 0x0000000000000000000000000000000000000123, score: 100
        });

        bytes memory signature =
            hex"efd096e7750ccf6608f0d3da8c469413085f2dd5c9aa1ecb2aa70c947d3dd56e3f62c9ff06dc1d300a4ec470723f0c167d4b751a044045c5fbd7458e83bf3ee9ff";

        SLAAllocator.PassportSigned memory signed =
            SLAAllocator.PassportSigned({passport: passport, signature: signature});

        vm.expectRevert(ECDSA.ECDSAInvalidSignature.selector);
        verifySignaturesHelper.verifyPassportSignedExt(signed);
    }

    function testVerifyPaymentTransactionSignatureWrongData() public view {
        SLAAllocator.PaymentTransaction memory txn = SLAAllocator.PaymentTransaction({
            id: bytes("1"),
            from: CommonTypes.FilAddress({data: hex"f101"}),
            to: CommonTypes.FilAddress({data: hex"f102"}),
            amount: 2
        });

        bytes memory signature =
            hex"c8b3e98ca2aff787d06bcc4db12fbd586fdfef4093caf3ba730d734d4dadd2e2425f9daedcf6ecb2b52139bf354133b357b1a7e2d222285be29a2c7fbde185071b";

        SLAAllocator.PaymentTransactionSigned memory signed =
            SLAAllocator.PaymentTransactionSigned({txn: txn, signature: signature});

        bool notVerified = verifySignaturesHelper.verifyPaymentTransactionSignedExt(signed);
        assertFalse(notVerified, "Signature valid");
    }

    function testVerifyPaymentTransactionSignatureWrongSignature() public {
        SLAAllocator.PaymentTransaction memory txn = SLAAllocator.PaymentTransaction({
            id: bytes("1"),
            from: CommonTypes.FilAddress({data: hex"f101"}),
            to: CommonTypes.FilAddress({data: hex"f102"}),
            amount: 1
        });

        bytes memory signature =
            hex"c8b3e98ca2aff787d06bcc4db12fbd586fdfef4093caf3ba730d734d4dadd2e2425f9daedcf6ecb2b52139bf354133b357b1a7e2d222285be29a2c7fbde18507ff";

        SLAAllocator.PaymentTransactionSigned memory signed =
            SLAAllocator.PaymentTransactionSigned({txn: txn, signature: signature});

        vm.expectRevert(ECDSA.ECDSAInvalidSignature.selector);
        verifySignaturesHelper.verifyPaymentTransactionSignedExt(signed);
    }

    function testVerifyManualAttestationSignatureWrongData() public view {
        bytes32 attestationId = bytes32(uint256(1));

        SLAAllocator.ManualAttestation memory att = SLAAllocator.ManualAttestation({
            attestationId: attestationId,
            client: 0x0000000000000000000000000000000000000123,
            provider: SP1,
            amount: 2,
            opaqueData: "data"
        });

        bytes memory signature =
            hex"f38955965e6619d56f115c4d617c5e94422b1d2e433495a03fd02fc7b7971e793455938c05fd526443886ee701c6875dca740f8f4c064d44118c3321891e01201c";

        SLAAllocator.ManualAttestationSigned memory signed =
            SLAAllocator.ManualAttestationSigned({attestation: att, signature: signature});

        bool notVerified = verifySignaturesHelper.verifyManualAttestationSignedExt(signed);
        assertFalse(notVerified, "Signature valid");
    }

    function testVerifyManualAttestationSignatureWrongSignature() public {
        bytes32 attestationId = bytes32(uint256(1));

        SLAAllocator.ManualAttestation memory att = SLAAllocator.ManualAttestation({
            attestationId: attestationId,
            client: 0x0000000000000000000000000000000000000123,
            provider: SP1,
            amount: 1,
            opaqueData: "data"
        });

        bytes memory signature =
            hex"f38955965e6619d56f115c4d617c5e94422b1d2e433495a03fd02fc7b7971e793455938c05fd526443886ee701c6875dca740f8f4c064d44118c3321891e0120ff";

        SLAAllocator.ManualAttestationSigned memory signed =
            SLAAllocator.ManualAttestationSigned({attestation: att, signature: signature});

        vm.expectRevert(ECDSA.ECDSAInvalidSignature.selector);
        verifySignaturesHelper.verifyManualAttestationSignedExt(signed);
    }

    function testRequestDataCapWithNoPasspportEmitEvent() public {
        resolveAddress.setId(address(this), uint64(20000));
        resolveAddress.setAddress(hex"00C2A101", uint64(20000));
        resolveAddress.setAddress(hex"f101", uint64(123));

        address beneficiaryEthAddressContract = FilAddressIdConverter.toAddress(20000);
        mockBeneficiaryFactory.setInstance(SP2, beneficiaryEthAddressContract);

        address client = address(this);

        SLAAllocator.PaymentTransaction memory txn = SLAAllocator.PaymentTransaction({
            id: bytes("1"),
            from: CommonTypes.FilAddress({data: hex"f101"}),
            to: CommonTypes.FilAddress({data: hex"f102"}),
            amount: 1
        });

        bytes32 structHash = verifySignaturesHelper.hashPaymentTransactionExt(txn);
        bytes32 digest = verifySignaturesHelper.digestToSignExt(structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attestorKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        SLAAllocator.PaymentTransactionSigned memory signedTxn =
            SLAAllocator.PaymentTransactionSigned({txn: txn, signature: signature});

        vm.prank(client);
        vm.expectEmit(true, true, false, true);
        emit SLAAllocator.DataCapGranted(client, SP2, 1);
        verifySignaturesHelper.requestDataCap(SP2, address(slaRegistry), 1, signedTxn);
    }
}
