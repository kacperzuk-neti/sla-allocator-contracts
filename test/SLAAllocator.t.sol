// SPDX-License-Identifier: MIT
// solhint-disable use-natspec
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SLAAllocator} from "../src/SLAAllocator.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BuiltinActorsMock} from "../test/contracts/BuiltinActorsMock.sol";
import {MockProxy} from "../test/contracts/MockProxy.sol";
import {MinerTypes} from "filecoin-solidity/v0.8/types/MinerTypes.sol";
import {GetBeneficiary} from "../src/libs/GetBeneficiary.sol";

contract SLAAllocatorTest is Test {
    SLAAllocator public slaAllocator;
    BuiltinActorsMock public builtinActorsMock;
    address public constant CALL_ACTOR_ID = 0xfe00000000000000000000000000000000000005;

    uint64 SP1 = 10000;
    uint64 SP2 = 20000;
    uint64 SP3 = 30000;

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

    function testGrantDataCapRevert() public {
        vm.expectRevert(abi.encodeWithSelector(GetBeneficiary.ExpirationBelowFiveYears.selector));
        slaAllocator.grantDataCap(SP1);
    }

    function testGrantDataCapSucceed() public view {
        slaAllocator.grantDataCap(SP2);
        assertTrue(true);
    }
}
