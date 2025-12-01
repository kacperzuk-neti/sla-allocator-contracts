// SPDX-License-Identifier: MIT
// solhint-disable use-natspec

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";
import {BeneficiaryFactory} from "../src/BeneficiaryFactory.sol";
import {Beneficiary} from "../src/Beneficiary.sol";
import {SLAAllocator} from "../src/SLAAllocator.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract BeneficiaryFactoryTest is Test {
    BeneficiaryFactory public factory;
    address public beneficiaryImpl;
    address public admin;
    address public slaAllocator;
    address public withdrawer;
    address public burnAddress;
    address public terminationOracle;
    CommonTypes.FilActorId public provider;
    BeneficiaryFactory public factoryImpl;
    bytes public initData;

    function setUp() public {
        admin = vm.addr(1);
        withdrawer = vm.addr(2);
        provider = CommonTypes.FilActorId.wrap(1);
        slaAllocator = vm.addr(101);
        burnAddress = vm.addr(102);
        terminationOracle = vm.addr(103);
        beneficiaryImpl = address(new Beneficiary());

        factoryImpl = new BeneficiaryFactory();
        initData = abi.encodeCall(
            BeneficiaryFactory.initialize,
            (admin, beneficiaryImpl, SLAAllocator(slaAllocator), burnAddress, terminationOracle)
        );
        factory = BeneficiaryFactory(address(new ERC1967Proxy(address(factoryImpl), initData)));
    }

    function testEmitsUpgradedInConstructor() public {
        vm.expectEmit(true, true, true, true);
        emit UpgradeableBeacon.Upgraded(beneficiaryImpl);
        new ERC1967Proxy(address(factoryImpl), initData);
    }

    function testDeployEmitsEvent() public {
        vm.expectEmit(true, true, true, true);

        address expectedProxy = computeProxyAddress(admin, withdrawer, provider, factory.nonce(admin, provider) + 1);
        emit BeneficiaryFactory.ProxyCreated(expectedProxy, provider);

        factory.create(admin, withdrawer, provider);
    }

    function testDeployMarksProxyAsDeployed() public {
        address expectedProxy = computeProxyAddress(admin, withdrawer, provider, factory.nonce(admin, provider) + 1);
        factory.create(admin, withdrawer, provider);

        assertTrue(factory.instances(provider) == expectedProxy);
    }

    function testDeployIncrementsNonce() public {
        factory.create(admin, withdrawer, provider);
        assertEq(factory.nonce(admin, provider), 1);
    }

    function testDeployRevertsIfInstanceExists() public {
        factory.create(admin, withdrawer, provider);

        vm.expectRevert(abi.encodeWithSelector(BeneficiaryFactory.InstanceAlreadyExists.selector));
        factory.create(admin, withdrawer, provider);
    }

    function computeProxyAddress(address admin_, address withdrawer_, CommonTypes.FilActorId provider_, uint256 nonce)
        private
        view
        returns (address)
    {
        bytes memory initCode = abi.encodePacked(
            type(BeaconProxy).creationCode,
            abi.encode(
                address(factory.beacon()),
                abi.encodeCall(
                    Beneficiary.initialize,
                    (admin_, withdrawer_, provider_, SLAAllocator(slaAllocator), burnAddress, terminationOracle)
                )
            )
        );
        bytes32 salt = keccak256(abi.encode(admin, provider, nonce));
        bytes32 bytecodeHash = keccak256(initCode);
        return Create2.computeAddress(salt, bytecodeHash, address(factory));
    }

    function testAuthorizeUpgradeRevert() public {
        address newImpl = address(new BeneficiaryFactory());
        address unauthorized = vm.addr(999);
        bytes32 upgraderRole = factory.UPGRADER_ROLE();
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, unauthorized, upgraderRole)
        );
        factory.upgradeToAndCall(newImpl, "");
    }
}
