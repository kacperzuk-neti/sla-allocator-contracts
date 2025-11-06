// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";
import {BigInts} from "filecoin-solidity/v0.8/utils/BigInts.sol";

/**
 * @title Utils
 * @notice Library for various utility functions
 */
library Utils {
    /**
     * @notice Converts a Filecoin CommonTypes.BigInt to uint256.
     * @dev Returns (0, false) if val.val.length == 0, otherwise uses BigInts.toUint256.
     * @param val The CommonTypes.BigInt value to convert.
     * @return value The uint256 representation.
     * @return error True if conversion failed, false otherwise.
     */
    function bigIntToUint256(CommonTypes.BigInt memory val) internal view returns (uint256 value, bool error) {
        if (val.val.length == 0) {
            return (0, false);
        }
        (uint256 v, bool err) = BigInts.toUint256(val);
        return (v, err);
    }
}
