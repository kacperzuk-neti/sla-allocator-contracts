// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MinerTypes} from "filecoin-solidity/v0.8/types/MinerTypes.sol";
import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";
import {MinerAPI} from "filecoin-solidity/v0.8/MinerAPI.sol";
import {Utils} from "./Utils.sol";
import {BeneficiaryFactory} from "../BeneficiaryFactory.sol";
import {FilAddressIdConverter} from "filecoin-solidity/v0.8/utils/FilAddressIdConverter.sol";
import {PrecompilesAPI} from "filecoin-solidity/v0.8/PrecompilesAPI.sol";

/**
 * @title MinerUtils
 * @notice Library for retrieving and validating Filecoin miner actor information
 */
library MinerUtils {
    error ExitCodeError();
    error NoBeneficiarySet();
    error NoNewBeneficiaryProposed();
    error QuotaCannotBeNegative();
    error ExpirationBelowFiveYears();
    error NewExpirationBelowActive();
    error NewQuotaBelowActive();
    error QuotaNotUnlimited();
    error InvalidBeneficiary(uint64 beneficiary, uint64 expectedBeneficiary);
    error InvalidNewBeneficiary(uint64 beneficiary, uint64 expectedBeneficiary);
    error BeneficiaryInstanceNonexistent();
    error FailedToGetActorID();
    /**
     * @notice Expiration time of 5 years in Filecoin epochs (assuming 30s epochs)
     * @dev 5 years = 5 * 365 * 24 * 60 * 60 seconds / 30 seconds per epoch = 5,256,000 epochs
     */
    int64 private constant EXPIRATION_5_YEARS = 5_256_000;

    /**
     * @notice Minimum beneficiary quota constant.
     */
    uint256 private constant MIN_BENEFICIARY_QUOTA = 195884047900000000000000000000;

    // Temporarily commented out to not break coverage CI
    // /**
    // * @notice Retrieves the owner information for a given miner actor ID.
    // * @dev Wraps the numeric minerID into a FilActorId and calls MinerAPI.getOwner.
    // *      Reverts with ExitCodeError if the FVM call returns a non-zero exit code.
    // * @param minerID The numeric Filecoin miner actor id.
    // * @return ownerData The MinerTypes.GetOwnerReturn struct returned by the actor call.
    // */
    //function getOwner(CommonTypes.FilActorId minerID) internal view returns (MinerTypes.GetOwnerReturn memory) {
    //    (int256 exitCode, MinerTypes.GetOwnerReturn memory ownerData) = MinerAPI.getOwner(minerID);
    //    if (exitCode != 0) {
    //        revert ExitCodeError();
    //    }
    //    return ownerData;
    //}

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
     * @param beneficiaryFactory The BeneficiaryFactory contract instance.
     * @param checkAddress If true, checks that the beneficiary address is set.
     * @param checkQuota If true, checks that the quota is not negative.
     * @param checkExpiration If true, checks that the expiration is at least 5 years.
     * @return beneficiaryData The MinerTypes.GetBeneficiaryReturn struct returned by the actor call.
     */
    function getBeneficiaryWithChecks(
        CommonTypes.FilActorId minerID,
        BeneficiaryFactory beneficiaryFactory,
        bool checkAddress,
        bool checkQuota,
        bool checkExpiration
    ) internal view returns (MinerTypes.GetBeneficiaryReturn memory) {
        MinerTypes.GetBeneficiaryReturn memory beneficiaryData = getBeneficiary(minerID);

        if (checkAddress) {
            if (beneficiaryData.active.beneficiary.data.length == 0) revert NoBeneficiarySet();
            address beneficiaryContractAddress = beneficiaryFactory.instances(minerID);
            if (beneficiaryContractAddress == address(0)) {
                revert BeneficiaryInstanceNonexistent();
            }
            (bool success, uint64 beneficiaryContractAddressInt) =
                FilAddressIdConverter.getActorID(beneficiaryContractAddress);
            if (!success) {
                revert FailedToGetActorID();
            }
            uint64 beneficiaryInt = PrecompilesAPI.resolveAddress(beneficiaryData.active.beneficiary);
            if (beneficiaryContractAddressInt != beneficiaryInt) {
                revert InvalidBeneficiary(beneficiaryInt, beneficiaryContractAddressInt);
            }
        }

        if (checkQuota) {
            if (beneficiaryData.active.term.quota.neg) revert QuotaCannotBeNegative();

            (uint256 quota,) = Utils.bigIntToUint256(beneficiaryData.active.term.quota);
            (uint256 usedQuota,) = Utils.bigIntToUint256(beneficiaryData.active.term.used_quota);

            if (quota - usedQuota < MIN_BENEFICIARY_QUOTA) revert QuotaNotUnlimited();
        }

        if (checkExpiration) {
            int64 currentEpoch = int64(uint64(block.number));
            int64 expirationEpoch = CommonTypes.ChainEpoch.unwrap(beneficiaryData.active.term.expiration);
            if (expirationEpoch < currentEpoch + EXPIRATION_5_YEARS) revert ExpirationBelowFiveYears();
        }

        return beneficiaryData;
    }

    /**
     * @notice Retrieves beneficiary info and validates a pending change for a specific contract address.
     * @dev Reverts if:
     *      - No pending beneficiary is set.
     *      - The proposed new beneficiary does not correspond to expectedBeneficiary.
     *      - The proposed quota is below MIN_BENEFICIARY_QUOTA.
     * @param minerID The Filecoin miner actor id.
     * @return beneficiaryData The MinerTypes.GetBeneficiaryReturn struct returned by the actor call.
     */
    function getBeneficiaryWithChecksForProposed(CommonTypes.FilActorId minerID)
        internal
        view
        returns (MinerTypes.GetBeneficiaryReturn memory)
    {
        MinerTypes.GetBeneficiaryReturn memory beneficiaryData = getBeneficiary(minerID);

        if (beneficiaryData.proposed.new_beneficiary.data.length == 0) revert NoNewBeneficiaryProposed();

        (bool success, uint64 expectedBeneficiaryActorID) = FilAddressIdConverter.getActorID(address(this));
        if (!success) {
            revert FailedToGetActorID();
        }

        uint64 newBeneficiaryActorID = PrecompilesAPI.resolveAddress(beneficiaryData.proposed.new_beneficiary);

        if (newBeneficiaryActorID != expectedBeneficiaryActorID) {
            revert InvalidNewBeneficiary(expectedBeneficiaryActorID, newBeneficiaryActorID);
        }

        (uint256 newQuota,) = Utils.bigIntToUint256(beneficiaryData.proposed.new_quota);
        (uint256 activeQuota,) = Utils.bigIntToUint256(beneficiaryData.active.term.quota);
        (uint256 activeUsedQuota,) = Utils.bigIntToUint256(beneficiaryData.active.term.used_quota);

        if (newQuota < MIN_BENEFICIARY_QUOTA) revert QuotaNotUnlimited();
        if (newQuota < activeQuota - activeUsedQuota) revert NewQuotaBelowActive();

        int64 activeExpirationEpoch = CommonTypes.ChainEpoch.unwrap(beneficiaryData.active.term.expiration);
        int64 proposedExpirationEpoch = CommonTypes.ChainEpoch.unwrap(beneficiaryData.proposed.new_expiration);
        if (proposedExpirationEpoch < activeExpirationEpoch) revert NewExpirationBelowActive();

        return beneficiaryData;
    }
}
