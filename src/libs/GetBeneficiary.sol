// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MinerTypes} from "filecoin-solidity/v0.8/types/MinerTypes.sol";
import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";
import {MinerAPI} from "filecoin-solidity/v0.8/MinerAPI.sol";
import {Utils} from "./Utils.sol";

/**
 * @title GetBeneficiary
 * @notice Library for retrieving beneficiary information from Filecoin miner actors
 */
library GetBeneficiary {
    error ExitCodeError();
    error NoBeneficiarySet();
    error QuotaCannotBeNegative();
    error ExpirationBelowFiveYears();
    error QuotaNotUnlimited();

    /**
     * @notice Expiration time of 5 years in Filecoin epochs (assuming 30s epochs)
     * @dev 5 years = 5 * 365 * 24 * 60 * 60 seconds / 30 seconds per epoch = 5,256,000 epochs
     */
    int64 private constant EXPIRATION_5_YEARS = 5_256_000;

    /**
     * @notice Minimum beneficiary quota constant.
     */
    uint256 private constant MIN_BENEFICIARY_QUOTA = 195884047900000000000000000000;

    /**
     * @notice Retrieves the beneficiary information for a given miner actor ID.
     * @dev Wraps the numeric minerID into a FilActorId and calls MinerAPI.getBeneficiary.
     *      Reverts with ExitCodeError if the FVM call returns a non-zero exit code.
     * @param minerID The numeric Filecoin miner actor id.
     * @return beneficiaryData The MinerTypes.GetBeneficiaryReturn struct returned by the actor call.
     */
    function getBeneficiary(CommonTypes.FilActorId minerID)
        internal
        view
        returns (MinerTypes.GetBeneficiaryReturn memory)
    {
        (int256 exitCode, MinerTypes.GetBeneficiaryReturn memory beneficiaryData) = MinerAPI.getBeneficiary(minerID);
        if (exitCode != 0) {
            revert ExitCodeError();
        }
        return beneficiaryData;
    }

    /**
     * @notice Retrieves the beneficiary information for a given miner actor ID with additional checks.
     * @dev Performs optional checks on the beneficiary address, quota, and expiration.
     *      Reverts with specific errors if any checks fail.
     * @param minerID The Filecoin miner actor id.
     * @param checkAddress If true, checks that the beneficiary address is set.
     * @param checkQuota If true, checks that the quota is not negative.
     * @param checkExpiration If true, checks that the expiration is at least 5 years.
     * @return beneficiaryData The MinerTypes.GetBeneficiaryReturn struct returned by the actor call.
     */
    function getBeneficiaryWithChecks(
        CommonTypes.FilActorId minerID,
        bool checkAddress,
        bool checkQuota,
        bool checkExpiration
    ) internal view returns (MinerTypes.GetBeneficiaryReturn memory) {
        MinerTypes.GetBeneficiaryReturn memory beneficiaryData = getBeneficiary(minerID);

        if (checkAddress) {
            if (beneficiaryData.active.beneficiary.data.length == 0) revert NoBeneficiarySet();
        }

        if (checkQuota) {
            if (beneficiaryData.active.term.quota.neg) revert QuotaCannotBeNegative();

            (uint256 quota,) = Utils.bigIntToUint256(beneficiaryData.active.term.quota);
            (uint256 usedQuota,) = Utils.bigIntToUint256(beneficiaryData.active.term.used_quota);

            if (quota - usedQuota < MIN_BENEFICIARY_QUOTA) revert QuotaNotUnlimited();
        }

        if (checkExpiration) {
            int64 currentEpoch = int64(uint64(block.timestamp / 30));
            int64 expirationEpoch = CommonTypes.ChainEpoch.unwrap(beneficiaryData.active.term.expiration);
            if (expirationEpoch < currentEpoch + EXPIRATION_5_YEARS) revert ExpirationBelowFiveYears();
        }

        return beneficiaryData;
    }
}
