// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";

/**
 * @title FilecoinConverter
 * @notice Utility library for converting Filecoin allocation identifiers to the claim identifier type.
 * @dev Provides pure, in-memory conversion helpers that preserve the order and length of the input arrays.
 *      The library uses CommonTypes.FilActorId.wrap(uint64) to perform the conversion.
 */
library FilecoinConverter {
    /**
     * @notice Convert an array of Filecoin allocation IDs into claim IDs used by the contract.
     * @dev This internal pure function:
     *      - Allocates a new memory array of CommonTypes.FilActorId with the same length as allocationIds.
     *      - Iterates over allocationIds and converts each uint64 into a CommonTypes.FilActorId by calling
     *        CommonTypes.FilActorId.wrap(allocationIds[i]).
     *      - Preserves the original order and length of the input array.
     *      Note: callers should be mindful of gas costs when passing large arrays.
     * @param allocationIds An array of Filecoin allocation IDs (uint64) to convert.
     * @return claimIds A memory array of CommonTypes.FilActorId values corresponding to the input allocation IDs.
     */
    function allocationIdsToClaimIds(uint64[] memory allocationIds)
        internal
        pure
        returns (CommonTypes.FilActorId[] memory claimIds)
    {
        claimIds = new CommonTypes.FilActorId[](allocationIds.length);
        for (uint256 i = 0; i < allocationIds.length; i++) {
            claimIds[i] = CommonTypes.FilActorId.wrap(allocationIds[i]);
        }
    }
}
