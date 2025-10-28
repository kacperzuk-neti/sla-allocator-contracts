// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Beneficiary} from "../src/Beneficiary.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract BeneficiaryTest is Test {
    Beneficiary public beneficiary;

    function setUp() public {
        Beneficiary impl = new Beneficiary();
        bytes memory initData = abi.encodeWithSignature("initialize(address)", address(this));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        beneficiary = Beneficiary(address(proxy));
    }

    function testIsAdminSet() public {
        bytes32 adminRole = beneficiary.DEFAULT_ADMIN_ROLE();
        assertTrue(beneficiary.hasRole(adminRole, address(this)));
    }
}
