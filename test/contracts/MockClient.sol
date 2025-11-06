// SPDX-License-Identifier: MIT
// solhint-disable use-natspec

pragma solidity ^0.8.24;

import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";

contract MockClient {
    // solhint-disable no-empty-blocks
    function increaseAllowance(address client, CommonTypes.FilActorId provider, uint256 amount) external pure {
        // noop
    }
}
