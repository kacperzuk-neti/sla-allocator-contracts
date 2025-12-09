// solhint-disable use-natspec
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {RateLimited} from "../../src/RateLimited.sol";

contract RateLimitedContract is RateLimited {
    event ActionPerformed();

    function performClientAction() external clientRateLimited {
        // solhint-disable-next-line
        msg.sender.call{value: 0}("");
        emit ActionPerformed();
    }

    function performGlobalAction() external globallyRateLimited {
        // solhint-disable-next-line
        msg.sender.call{value: 0}("");
        emit ActionPerformed();
    }
}
