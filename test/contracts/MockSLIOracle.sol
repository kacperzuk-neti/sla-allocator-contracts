// SPDX-License-Identifier: MIT
// solhint-disable use-natspec

pragma solidity ^0.8.24;

import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";
import {SLIOracle} from "../../src/SLIOracle.sol";

contract MockSLIOracle {
    uint256 public lastUpdate;
    uint32 public latency;
    uint16 public retention;
    uint16 public bandwidth;
    uint16 public stability;
    uint8 public availability;
    uint8 public indexing;

    function setLastUpdate(uint256 lastUpdate_) public {
        lastUpdate = lastUpdate_;
    }

    function setAttestations(
        uint256 lastUpdate_,
        uint32 latency_,
        uint16 retention_,
        uint16 bandwidth_,
        uint16 stability_,
        uint8 availability_,
        uint8 indexing_
    ) public {
        lastUpdate = lastUpdate_;
        latency = latency_;
        retention = retention_;
        bandwidth = bandwidth_;
        stability = stability_;
        availability = availability_;
        indexing = indexing_;
    }

    function attestations(CommonTypes.FilActorId) public view returns (SLIOracle.SLIAttestation memory ret) {
        ret.lastUpdate = lastUpdate;
        ret.latency = latency;
        ret.retention = retention;
        ret.bandwidth = bandwidth;
        ret.stability = stability;
        ret.availability = availability;
        ret.indexing = indexing;
    }
}
