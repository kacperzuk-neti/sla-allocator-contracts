// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Client} from "../src/Client.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";

contract ClientTest is Test {
    Client public client;
    address public allocator;
    CommonTypes.FilActorId public providerFilActorId;
    address public clientAddress;

    function setUp() public {
        Client impl = new Client();
        allocator = address(0x123);
        providerFilActorId = CommonTypes.FilActorId.wrap(7);
        clientAddress = address(0x789);
        bytes memory initData = abi.encodeWithSignature("initialize(address,address)", address(this), allocator);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        client = Client(address(proxy));
    }

    function testIsAdminSet() public view {
        bytes32 adminRole = client.DEFAULT_ADMIN_ROLE();
        assertTrue(client.hasRole(adminRole, address(this)));
    }

    function testIsAllocatorSet() public view {
        bytes32 allocatorRole = client.ALLOCATOR_ROLE();
        assertTrue(client.hasRole(allocatorRole, allocator));
    }

    function testIncreaseAndDecreaseAllowance() public {
        uint256 amount = 100;
        vm.prank(allocator);
        client.increaseAllowance(clientAddress, providerFilActorId, amount);
        assertEq(client.allowances(clientAddress, providerFilActorId), amount);

        vm.prank(allocator);
        client.decreaseAllowance(clientAddress, providerFilActorId, amount);
        assertEq(client.allowances(clientAddress, providerFilActorId), 0);
    }

    function testAllowanceChangedEventEmittedForIncreaseAllowance() public {
        uint256 amount = 100;
        vm.prank(allocator);
        vm.expectEmit(true, true, true, true);

        emit Client.AllowanceChanged(clientAddress, providerFilActorId, 0, amount);
        client.increaseAllowance(clientAddress, providerFilActorId, amount);
    }

    function testAllowanceChangedEventEmittedForDecreaseAllowance() public {
        uint256 initialAllowance = 200;
        uint256 amount = 100;
        vm.prank(allocator);
        client.increaseAllowance(clientAddress, providerFilActorId, initialAllowance);

        vm.prank(allocator);
        vm.expectEmit(true, true, true, true);

        emit Client.AllowanceChanged(clientAddress, providerFilActorId, initialAllowance, initialAllowance - amount);
        client.decreaseAllowance(clientAddress, providerFilActorId, amount);
    }

    function testDecreaseAllowanceShouldSetAllowanceToZero() public {
        uint256 initialAllowance = 100;
        uint256 amount = 200;
        vm.prank(allocator);
        client.increaseAllowance(clientAddress, providerFilActorId, initialAllowance);

        vm.prank(allocator);
        client.decreaseAllowance(clientAddress, providerFilActorId, amount);
        assertEq(client.allowances(clientAddress, providerFilActorId), 0);
    }

    function testRevertsWhenAmountIsZeroForIncreaseAllowance() public {
        vm.prank(allocator);
        vm.expectRevert(Client.AmountEqualsZero.selector);
        client.increaseAllowance(clientAddress, providerFilActorId, 0);
    }

    function testRevertsWhenAmountIsZeroForDecreaseAllowance() public {
        vm.prank(allocator);
        vm.expectRevert(Client.AmountEqualsZero.selector);
        client.decreaseAllowance(clientAddress, providerFilActorId, 0);
    }

    function testRevertsWhenAllowanceIsZeroForDecreaseAllowance() public {
        vm.prank(allocator);
        vm.expectRevert(Client.AlreadyZero.selector);
        client.decreaseAllowance(clientAddress, providerFilActorId, 100);
    }

    function testAuthorizeUpgradeRevert() public {
        address newImpl = address(new Client());
        address unauthorized = vm.addr(1);
        bytes32 adminRole = client.DEFAULT_ADMIN_ROLE();
        bytes4 sel = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));

        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(sel, unauthorized, adminRole));
        client.upgradeToAndCall(newImpl, "");
    }
}
