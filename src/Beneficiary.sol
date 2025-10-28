// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {MinerTypes} from "filecoin-solidity/v0.8/types/MinerTypes.sol";
import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";
import {MinerAPI} from "filecoin-solidity/v0.8/MinerAPI.sol";

/**
 * @title Beneficiary
 * @notice Upgradeable contract for managing beneficiaries with role-based access control
 * @dev This contract is designed to be deployed as a proxy contract
 */
contract Beneficiary is Initializable, AccessControlUpgradeable {
    error ExitCodeError();

    /**
     * @notice Disabled constructor (proxy pattern)
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Contract initializator. Should be called during deployment
     * @param provider Address of the storage provider
     */
    function initialize(address provider) public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, provider);
    }

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
}
