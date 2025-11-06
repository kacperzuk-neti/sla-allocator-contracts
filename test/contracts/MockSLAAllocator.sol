// SPDX-License-Identifier: MIT
// solhint-disable use-natspec

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";

contract MockSLAAllocator is Test {
    function providerClients(CommonTypes.FilActorId) public pure returns (address client) {
        return vm.addr(1000);
    }

    function slaContracts(address, CommonTypes.FilActorId) public view returns (address slaRegistry) {
        return address(this);
    }

    function score(address, CommonTypes.FilActorId provider) public pure returns (uint256) {
        if (CommonTypes.FilActorId.unwrap(provider) == 0x123) {
            return 75;
        } else if (CommonTypes.FilActorId.unwrap(provider) == 0x456) {
            return 35;
        }
        return 95;
    }
}
