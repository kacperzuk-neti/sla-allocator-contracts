// SPDX-License-Identifier: MIT
// solhint-disable use-natspec
// solhint-disable gas-strict-inequalities
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {RateLimitedContract} from "./contracts/RateLimitedContract.sol";

import {RateLimited} from "../src/RateLimited.sol";

contract RateLimitedTest is Test {
    RateLimitedContract public testContract;

    address public user1 = vm.addr(0x123);
    address public user2 = vm.addr(0x456);

    function setUp() public {
        testContract = new RateLimitedContract();
    }

    function testInitialCallSuccess() public {
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);

        emit RateLimitedContract.ActionPerformed();
        testContract.performClientAction();
    }

    function testClientLimitExceeded() public {
        vm.prank(user1);
        testContract.performClientAction();

        uint256 expectedResetTime = block.timestamp + testContract.CLIENT_RATE_LIMIT_TIME() - 1 seconds;

        vm.expectRevert(abi.encodeWithSelector(RateLimited.ClientRateLimitExceeded.selector, user1, expectedResetTime));
        vm.prank(user1);
        testContract.performClientAction();
    }

    function testGlobalLimitExceeded() public {
        for (uint256 i = 1; i <= testContract.GLOBAL_RATE_LIMIT(); i++) {
            address user = vm.addr(i);
            vm.prank(user);
            testContract.performGlobalAction();
        }

        vm.expectRevert(abi.encodeWithSelector(RateLimited.GlobalRateLimitExceeded.selector, block.timestamp + 1 days));
        vm.prank(vm.addr(6));
        testContract.performGlobalAction();
    }

    function testClientResetAfterWindow() public {
        vm.prank(user1);
        testContract.performClientAction();

        vm.warp(block.timestamp + 1 weeks + 1);

        vm.prank(user1);
        testContract.performClientAction();
    }

    function testGlobalResetAfterWindow() public {
        for (uint256 i = 1; i <= testContract.GLOBAL_RATE_LIMIT(); i++) {
            address user = vm.addr(i);
            vm.prank(user);
            testContract.performGlobalAction();
        }

        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(vm.addr(6));
        testContract.performGlobalAction();
    }
}

