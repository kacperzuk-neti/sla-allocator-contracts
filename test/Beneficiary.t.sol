// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Beneficiary} from "../src/Beneficiary.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BuiltinActorsMock} from "../test/contracts/BuiltinActorsMock.sol";
import {MockProxy} from "../test/contracts/MockProxy.sol";
import {MinerTypes} from "filecoin-solidity/v0.8/types/MinerTypes.sol";

contract BeneficiaryTest is Test {
    Beneficiary public beneficiary;
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

        Beneficiary impl = new Beneficiary();
        bytes memory initData = abi.encodeWithSignature("initialize(address)", address(this));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        beneficiary = Beneficiary(address(proxy));
    }

    function testIsAdminSet() public {
        bytes32 adminRole = beneficiary.DEFAULT_ADMIN_ROLE();
        assertTrue(beneficiary.hasRole(adminRole, address(this)));
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
