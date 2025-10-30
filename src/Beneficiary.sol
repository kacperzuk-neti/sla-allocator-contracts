// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {MinerTypes} from "filecoin-solidity/v0.8/types/MinerTypes.sol";
import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";
import {MinerAPI} from "filecoin-solidity/v0.8/MinerAPI.sol";
import {SLARegistry} from "./SLARegistry.sol";

/**
 * @title Beneficiary
 * @notice Upgradeable contract for managing beneficiaries with role-based access control
 * @dev This contract is designed to be deployed as a proxy contract
 */

contract Beneficiary is Initializable, AccessControlUpgradeable {
    /**
     * @notice The role to manage the withdrawer role.
     */
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /**
     * @notice The role to withdraw funds from the contract.
     */
    bytes32 public constant WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");

    /**
     * @notice The address of the storage provider.
     */
    address public provider;

    /**
     * @notice The address to set as the slash recipient.
     */
    address public slashRecipient;

    /**
     * @notice The SLA registry contract.
     */
    SLARegistry public slaRegistry;

    /**
     * @notice Emits a SlashReciptentUpdated event.
     * @param slashRecipient The address to set as the slash recipient.
     */
    event SlashReciptentUpdated(address indexed slashRecipient);

    /**
     * @notice Emits a Withdrawn event.
     * @param amountToSP The amount to send to the storage provider.
     * @param amountToRedirected The amount to send to the redirected address.
     */
    event Withdrawn(uint256 indexed amountToSP, uint256 indexed amountToRedirected);

    /**
     * @notice Error thrown when the exit code is not zero.
     */
    error ExitCodeError();

    /**
     * @notice Disabled constructor (proxy pattern)
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Contract initializator. Should be called during deployment
     * @param admin Address of the contract admin
     * @param _provider Address of the storage provider
     * @param _slaRegistry Address of the SLA registry contract
     */
    function initialize(address admin, address _provider, address _slaRegistry) public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, _provider);
        _grantRole(WITHDRAWER_ROLE, _provider);
        provider = _provider;
        slaRegistry = SLARegistry(_slaRegistry);
    }

    /**
     * @notice Emits a SlashReciptentUpdated event.
     * @param _slashRecipient The address to set as the slash recipient.
     * @dev Only the admin can set the slash recipient.
     */
    function setSlashRecipient(address _slashRecipient) public onlyRole(DEFAULT_ADMIN_ROLE) {
        slashRecipient = _slashRecipient;
        emit SlashReciptentUpdated(_slashRecipient);
    }

    /**
     * @notice Revokes the withdrawer role for a given address.
     * @param _withdrawer The address to revoke the withdrawer role from.
     * @dev Only the manager can revoke the withdrawer role.
     */
    function revokeWithdrawerRole(address _withdrawer) public onlyRole(MANAGER_ROLE) {
        _revokeRole(WITHDRAWER_ROLE, _withdrawer);
    }

    /**
     * @notice Grants the withdrawer role for a given address.
     * @param _withdrawer The address to grant the withdrawer role to.
     * @dev Only the manager can grant the withdrawer role.
     */
    function grantWithdrawerRole(address _withdrawer) public onlyRole(MANAGER_ROLE) {
        _grantRole(WITHDRAWER_ROLE, _withdrawer);
    }

    /**
     * @notice Withdraws the balance of the contract to the specified address. Emits a Withdrawn event.
     * @dev The balance is split between the storage provider and the redirected address based on the score. but for now its always 100% to SP
     * @param to The address to withdraw the balance to.
     */
    function withdraw(address to) public onlyRole(WITHDRAWER_ROLE) {
        uint256 score = slaRegistry.score(provider);
        uint256 amount = address(this).balance;
        uint256 amountToSP = 0;
        uint256 amountToBeRedirected = 0;

        if (score >= 90) {
            amountToSP = amount;
        } else if (score > 80 && score < 90) {
            amountToSP = amount * score / 100;
            amountToBeRedirected = amount - amountToSP;
        } else {
            amountToSP = 0;
            amountToBeRedirected = amount;
        }

        payable(to).transfer(amount);
        emit Withdrawn(amountToSP, amountToBeRedirected);
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

