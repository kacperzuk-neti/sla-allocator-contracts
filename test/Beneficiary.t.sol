// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Beneficiary} from "../src/Beneficiary.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BuiltinActorsMock} from "../test/contracts/BuiltinActorsMock.sol";
import {MockProxy} from "../test/contracts/MockProxy.sol";
import {MinerTypes} from "filecoin-solidity/v0.8/types/MinerTypes.sol";
import {SLARegistry} from "../src/SLARegistry.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {RevertingReceiver} from "../test/contracts/RevertingReceiver.sol";

contract BeneficiaryTest is Test {
    Beneficiary public beneficiary;
    BuiltinActorsMock public builtinActorsMock;

    address public provider = address(0x999);
    address public slaRegistry;
    address public constant CALL_ACTOR_ID = 0xfe00000000000000000000000000000000000005;

    uint64 SP1 = 10000;
    uint64 SP2 = 20000;
    uint64 SP3 = 30000;

    function setUp() public {
        builtinActorsMock = new BuiltinActorsMock();
        slaRegistry = address(new SLARegistry());
        address mockProxy = address(new MockProxy());

        vm.etch(CALL_ACTOR_ID, address(mockProxy).code);
        vm.etch(address(5555), address(builtinActorsMock).code);

        beneficiary = setupBeneficiary(address(this), provider, slaRegistry);
    }

    function setupBeneficiary(address _admin, address _provider, address _slaRegistry) public returns (Beneficiary) {
        Beneficiary impl = new Beneficiary();
        bytes memory initData =
            abi.encodeWithSignature("initialize(address,address,address)", _admin, _provider, _slaRegistry);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        return Beneficiary(address(proxy));
    }

    function testIsAdminSet() public view {
        bytes32 adminRole = beneficiary.DEFAULT_ADMIN_ROLE();
        assertTrue(beneficiary.hasRole(adminRole, address(this)));
    }

    function testIsManagerSet() public view {
        bytes32 managerRole = beneficiary.MANAGER_ROLE();
        assertTrue(beneficiary.hasRole(managerRole, provider));
    }

    function testIsWithdrawerSet() public view {
        bytes32 withdrawerRole = beneficiary.WITHDRAWER_ROLE();
        assertTrue(beneficiary.hasRole(withdrawerRole, provider));
    }

    function testIsManagerSetAsWithdrawerRoleAdmin() public view {
        bytes32 managerRole = beneficiary.MANAGER_ROLE();
        bytes32 withdrawerRole = beneficiary.WITHDRAWER_ROLE();
        assertTrue(beneficiary.getRoleAdmin(withdrawerRole) == managerRole);
    }

    function testSetSlashRecipient() public {
        beneficiary.setSlashRecipient(address(0x123));
        assertEq(beneficiary.slashRecipient(), address(0x123));
    }

    function testSetSlashRecipientEmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit Beneficiary.SlashRecipientUpdated(address(0x123));
        beneficiary.setSlashRecipient(address(0x123));
    }

    function testSetSlashRecipientRevert() public {
        address notAdmin = address(0x333);
        bytes32 expectedRole = beneficiary.DEFAULT_ADMIN_ROLE();
        vm.prank(notAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, notAdmin, expectedRole)
        );
        beneficiary.setSlashRecipient(address(0x123));
    }

    function testWithdrawForGreenBand() public {
        vm.deal(address(beneficiary), 10000);
        vm.startPrank(provider);
        vm.expectEmit(true, true, true, true);

        emit Beneficiary.Withdrawn(address(0x123), 10000, 0);
        beneficiary.withdraw(payable(address(0x123)));
        assertEq(address(beneficiary).balance, 0);
    }

    function testWithdrawForAmberBand() public {
        address providerWithAmberBandScore = address(0x123);
        beneficiary = setupBeneficiary(address(this), providerWithAmberBandScore, slaRegistry);
        vm.deal(address(beneficiary), 10000);
        vm.startPrank(providerWithAmberBandScore);
        vm.expectEmit(true, true, true, true);

        emit Beneficiary.Withdrawn(address(0x888), 9000, 1000);
        beneficiary.withdraw(payable(address(0x888)));
        assertEq(address(beneficiary).balance, 0);
    }

    function testWithdrawForRedBand() public {
        address providerWithRedBandScore = address(0x456);
        beneficiary = setupBeneficiary(address(this), providerWithRedBandScore, slaRegistry);
        vm.deal(address(beneficiary), 10000);
        vm.startPrank(providerWithRedBandScore);
        vm.expectEmit(true, true, true, true);

        emit Beneficiary.Withdrawn(address(0x888), 5000, 5000);
        beneficiary.withdraw(payable(address(0x888)));
        assertEq(address(beneficiary).balance, 0);
    }

    function testWithddrawRevertsWhenNotWithdrawer() public {
        address notWithdrawer = address(0x333);
        bytes32 expectedRole = beneficiary.WITHDRAWER_ROLE();
        vm.prank(notWithdrawer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, notWithdrawer, expectedRole
            )
        );
        beneficiary.withdraw(payable(address(0x123)));
    }

    function testRevertsWithdrawalFailed() public {
        address to = address(new RevertingReceiver());
        vm.deal(address(beneficiary), 10000);
        vm.startPrank(provider);
        vm.expectRevert(abi.encodeWithSelector(Beneficiary.WithdrawalFailed.selector));

        beneficiary.withdraw(payable(to));
        assertEq(address(beneficiary).balance, 10000);
    }

    function testSetWithdrawerRoleAndRevoke() public {
        bytes32 withdrawerRole = beneficiary.WITHDRAWER_ROLE();
        vm.startPrank(provider);

        beneficiary.grantRole(withdrawerRole, address(0x123));
        assertTrue(beneficiary.hasRole(withdrawerRole, address(0x123)));
        beneficiary.revokeRole(withdrawerRole, address(0x123));
        assertFalse(beneficiary.hasRole(withdrawerRole, address(0x123)));
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

    function testGetBeneficiaryForSP1() public {
        MinerTypes.GetBeneficiaryReturn memory result = beneficiary.getBeneficiary(SP1);
        assertEq(result.active.beneficiary.data, hex"00904E");
    }

    function testGetBeneficiaryForSP2() public {
        MinerTypes.GetBeneficiaryReturn memory result = beneficiary.getBeneficiary(SP2);
        assertEq(result.active.beneficiary.data, hex"00B8C101");
    }

    function testGetBeneficiaryForSP3() public {
        MinerTypes.GetBeneficiaryReturn memory result = beneficiary.getBeneficiary(SP3);
        assertEq(result.active.beneficiary.data, hex"00C2A101");
    }

    function testGetBeneficiaryPendingChangeForSP3() public {
        MinerTypes.GetBeneficiaryReturn memory result = beneficiary.getBeneficiary(SP3);
        assertEq(result.proposed.new_beneficiary.data, hex"00D4C101");
    }

    function testGetBeneficiaryExpectRevertExitCodeError() public {
        vm.expectRevert(abi.encodeWithSelector(Beneficiary.ExitCodeError.selector));
        beneficiary.getBeneficiary(12345);
    }
}
