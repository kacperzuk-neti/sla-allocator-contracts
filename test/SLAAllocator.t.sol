// SPDX-License-Identifier: MIT
// solhint-disable use-natspec
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SLAAllocator} from "../src/SLAAllocator.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BuiltinActorsMock} from "../test/contracts/BuiltinActorsMock.sol";
import {MockProxy} from "../test/contracts/MockProxy.sol";
import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";
import {GetBeneficiary} from "../src/libs/GetBeneficiary.sol";

contract SLAAllocatorTest is Test {
    SLAAllocator public slaAllocator;
    BuiltinActorsMock public builtinActorsMock;
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
        builtinActorsMock = new BuiltinActorsMock();
        address mockProxy = address(new MockProxy());
        vm.etch(CALL_ACTOR_ID, address(mockProxy).code);
        vm.etch(address(5555), address(builtinActorsMock).code);

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

    function testGrantDataCapExpirationBelowFiveYearsRevert() public {
        vm.expectRevert(abi.encodeWithSelector(GetBeneficiary.ExpirationBelowFiveYears.selector));
        slaAllocator.grantDataCap(client, SP1, 1);
    }

    function testGrantDataCapNoBeneficiarySetRevert() public {
        vm.expectRevert(abi.encodeWithSelector(GetBeneficiary.NoBeneficiarySet.selector));
        slaAllocator.grantDataCap(client, SP4, 1);
    }

    function testGrantDataCapQuotaCannotBeNegativeRevert() public {
        vm.expectRevert(abi.encodeWithSelector(GetBeneficiary.QuotaCannotBeNegative.selector));
        slaAllocator.grantDataCap(client, SP5, 1);
    }

    function testGrantDataCapSucceed() public view {
        slaAllocator.grantDataCap(client, SP2, 1);
    }

    function testGetBeneficiaryExpectRevertExitCodeError() public {
        vm.expectRevert(abi.encodeWithSelector(GetBeneficiary.ExitCodeError.selector));
        slaAllocator.grantDataCap(client, CommonTypes.FilActorId.wrap(uint64(12345)), 1);
    }

    function testGrantDataCapQuotaNotUnlimitedRevert() public {
        vm.expectRevert(abi.encodeWithSelector(GetBeneficiary.QuotaNotUnlimited.selector));
        slaAllocator.grantDataCap(client, SP6, 1);
    }
}
