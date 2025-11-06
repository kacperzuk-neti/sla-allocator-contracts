// SPDX-License-Identifier: MIT
// solhint-disable use-natspec

pragma solidity ^0.8.24;

import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";
import {SLIOracle} from "../../src/SLIOracle.sol";

contract MockSLIOracle {
    uint256 public lastUpdate;

    function setLastUpdate(uint256 lastUpdate_) public {
        lastUpdate = lastUpdate_;
    }

    function attestations(CommonTypes.FilActorId) public view returns (SLIOracle.SLIAttestation memory ret) {
        ret.lastUpdate = lastUpdate;
    }
}
