// SPDX-License-Identifier: MIT
// solhint-disable use-natspec
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/RateLimited.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract TestContract is RateLimited {
    event ActionPerformed();

    function performAction() external rateLimited {
        (bool success,) = msg.sender.call("");
        emit ActionPerformed();
    }
}

contract RateLimitedTest is Test {
    TestContract public testContract;

    address public user1 = address(0x123);
    address public user2 = address(0x456);

    function setUp() public {
        testContract = new TestContract();
    }

    function testInitialCallSuccess() public {
        vm.prank(user1);
        testContract.performAction();
    }

    function testClientLimitExceeded() public {
        vm.prank(user1);
        testContract.performAction();

        uint256 expectedResetTime = block.timestamp + testContract.CLIENT_RATE_LIMIT_TIME();

        vm.expectRevert(abi.encodeWithSelector(RateLimited.ClientRateLimitExceeded.selector, user1, expectedResetTime));
        vm.prank(user1);
        testContract.performAction();
    }

    function testGlobalLimitExceeded() public {
        for (uint256 i = 1; i <= testContract.GLOBAL_RATE_LIMIT(); i++) {
            address user = address(uint160(i));
            vm.prank(user);
            testContract.performAction();
        }

        vm.expectRevert(abi.encodeWithSelector(RateLimited.GlobalRateLimitExceeded.selector, block.timestamp + 1 days));
        vm.prank(address(6));
        testContract.performAction();
    }

    function testClientResetAfterWindow() public {
        vm.prank(user1);
        testContract.performAction();

        vm.warp(block.timestamp + 1 weeks + 1);

        vm.prank(user1);
        testContract.performAction();
    }

    function testGlobalResetAfterWindow() public {
        for (uint256 i = 1; i <= testContract.GLOBAL_RATE_LIMIT(); i++) {
            address user = address(uint160(i));
            vm.prank(user);
            testContract.performAction();
        }

        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(address(6));
        testContract.performAction();
    }

    function testReentrancyAttackShouldRevertWithLimitExceeded() public {
        ReentryAttacker attacker = new ReentryAttacker(address(testContract));

        vm.prank(address(attacker));
        vm.expectRevert(
            abi.encodeWithSelector(
                RateLimited.ClientRateLimitExceeded.selector, address(attacker), block.timestamp + 1 weeks
            )
        );
        testContract.performAction();
    }
}

contract ReentryAttacker {
    TestContract public target;

    constructor(address _target) {
        target = TestContract(_target);
    }

    fallback() external {
        target.performAction();
    }
}
