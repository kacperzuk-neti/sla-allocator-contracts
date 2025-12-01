// solhint-disable use-natspec
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {RateLimited} from "../../src/RateLimited.sol";

contract RateLimitedContract is RateLimited {
    event ActionPerformed();

    function performAction() external rateLimited {
        // solhint-disable-next-line
        msg.sender.call{value: 0}("");
        emit ActionPerformed();
    }
}
