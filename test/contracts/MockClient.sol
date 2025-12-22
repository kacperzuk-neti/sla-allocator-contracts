// SPDX-License-Identifier: MIT
// solhint-disable use-natspec

pragma solidity ^0.8.24;

import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";
import {Test} from "forge-std/Test.sol";

contract MockClient is Test {
    function getSPClients(CommonTypes.FilActorId provider) external returns (address[] memory) {
        address[] memory clients = new address[](1);
        if (CommonTypes.FilActorId.unwrap(provider) == 0x123 || CommonTypes.FilActorId.unwrap(provider) == 0x456) {
            clients[0] = vm.addr(1);
        } else {
            clients[0] = vm.addr(2);
        }
        return clients;
    }

    // solhint-disable no-unused-vars
    function getClientSpActiveDataSize(address client, CommonTypes.FilActorId provider) external returns (uint256) {
        if (client == vm.addr(1)) {
            return 1024;
        }
        return 0;
    }

    // solhint-disable no-empty-blocks
    function increaseAllowance(address client, CommonTypes.FilActorId provider, uint256 amount) external pure {
        // noop
    }
}
