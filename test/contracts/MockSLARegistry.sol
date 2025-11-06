// SPDX-License-Identifier: MIT
// solhint-disable use-natspec

pragma solidity ^0.8.24;

import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";

contract MockSLARegistry {
    uint256 public ret;
    bool public shouldRevert;

    error Err();

    function setRevert(bool shouldRevert_) external {
        shouldRevert = shouldRevert_;
    }

    function setScore(uint256 score_) external {
        ret = score_;
    }

    function score(address, CommonTypes.FilActorId) external returns (uint256) {
        if (shouldRevert) revert Err();
        return ret;
    }
}
