// SPDX-License-Identifier: MIT
// solhint-disable use-natspec

pragma solidity ^0.8.24;

import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {Client} from "../../src/Client.sol";

contract MockClientContract is Client {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    function addClientAllocationIds(CommonTypes.FilActorId provider, address client, uint64 allocationId) external {
        clientAllocationIdsPerProvider[provider][client].push(allocationId);
    }

    function setSpClients(CommonTypes.FilActorId provider, address client, uint256 allocationSize) external {
        _spClients[provider].set(client, allocationSize);
    }
}
