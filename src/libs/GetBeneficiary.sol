// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MinerTypes} from "filecoin-solidity/v0.8/types/MinerTypes.sol";
import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";
import {MinerAPI} from "filecoin-solidity/v0.8/MinerAPI.sol";

/**
 * @title GetBeneficiary
 * @notice Library for retrieving beneficiary information from Filecoin miner actors
 */
library GetBeneficiary {
    error ExitCodeError();
    error QuotaCannotBeNegative();
    error ExpirationBelowFiveYears();

    /**
     * @notice Expiration time of 5 years in Filecoin epochs (assuming 30s epochs)
     * @dev 5 years = 5 * 365 * 24 * 60 * 60 seconds / 30 seconds per epoch = 5,256,000 epochs
     */
    int64 private constant EXPIRATION_5_YEARS = 5_256_000;

    /**
     * @notice Retrieves the beneficiary information for a given miner actor ID.
     * @dev Wraps the numeric minerID into a FilActorId and calls MinerAPI.getBeneficiary.
     *      Reverts with ExitCodeError if the FVM call returns a non-zero exit code.
     * @param minerID The numeric Filecoin miner actor id (uint64).
     * @return beneficiaryData The MinerTypes.GetBeneficiaryReturn struct returned by the actor call.
     */
    function getBeneficiary(uint64 minerID) public view returns (MinerTypes.GetBeneficiaryReturn memory) {
        (int256 exitCode, MinerTypes.GetBeneficiaryReturn memory beneficiaryData) =
            MinerAPI.getBeneficiary(CommonTypes.FilActorId.wrap(minerID));
        if (exitCode != 0) {
            revert ExitCodeError();
        }
        return beneficiaryData;
    }

    /**
     * @notice Validates that the quota of the beneficiary associated with the given minerID is non-negative.
     * @param minerID The numeric Filecoin miner actor id (uint64).
     */
    function validateQuota(uint64 minerID) public view {
        MinerTypes.GetBeneficiaryReturn memory beneficiaryData = getBeneficiary(minerID);
        if (beneficiaryData.active.term.quota.neg) {
            revert QuotaCannotBeNegative();
        }
    }

    /**
     * @notice Validates that the expiration term of the beneficiary associated with the given minerID is at least 5 years.
     * @param minerID The numeric Filecoin miner actor id (uint64).
     */
    function validateExpiration(uint64 minerID) public view {
        MinerTypes.GetBeneficiaryReturn memory beneficiaryData = getBeneficiary(minerID);
        int64 expirationEpoch = CommonTypes.ChainEpoch.unwrap(beneficiaryData.active.term.expiration);
        if (expirationEpoch < EXPIRATION_5_YEARS) {
            revert ExpirationBelowFiveYears();
        }
    }
}
