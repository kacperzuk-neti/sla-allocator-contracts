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
     * @notice Emits a SlashRecipientUpdated event.
     * @param slashRecipient The address to set as the slash recipient.
     */
    event SlashRecipientUpdated(address indexed slashRecipient);

    /**
     * @notice Emits a Withdrawn event.
     * @param to The address to withdraw the balance to.
     * @param amountToSP The amount to send to the storage provider.
     * @param amountToRedirected The amount to send to the redirected address.
     */
    event Withdrawn(address indexed to, uint256 amountToSP, uint256 amountToRedirected);

    /**
     * @notice Error thrown when the exit code is not zero.
     */
    error ExitCodeError();

    /**
     * @notice Error thrown when the withdrawal fails.
     */
    error WithdrawalFailed();

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
        _setRoleAdmin(WITHDRAWER_ROLE, MANAGER_ROLE);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, _provider);
        _grantRole(WITHDRAWER_ROLE, _provider);

        provider = _provider;
        slaRegistry = SLARegistry(_slaRegistry);
    }

    /**
     * @notice Emits a SlashRecipientUpdated event.
     * @param _slashRecipient The address to set as the slash recipient.
     * @dev Only the admin can set the slash recipient.
     */
    function setSlashRecipient(address _slashRecipient) public onlyRole(DEFAULT_ADMIN_ROLE) {
        slashRecipient = _slashRecipient;
        emit SlashRecipientUpdated(_slashRecipient);
    }

    /**
     * @notice Withdraws the balance of the contract to the specified address. Emits a Withdrawn event.
     * @dev The balance is split between the storage provider and the redirected address based on the score. but for now its always 100% to SP
     * @param _to The address to withdraw the balance to.
     */
    function withdraw(address payable _to) public onlyRole(WITHDRAWER_ROLE) {
        uint256 amount = address(this).balance;
        uint256 score = slaRegistry.score(provider);
        (uint256 amountToSP, uint256 amountToBeRedirected) = _slashByScore(amount, score);

        emit Withdrawn(_to, amountToSP, amountToBeRedirected);
        (bool sent,) = _to.call{value: amount}("");
        if (!sent) {
            revert WithdrawalFailed();
        }
    }

    /**
     * @notice Slashes the amount by the given score.
     * @dev The amount is slashed by the score.
     * @param amount The amount to slash.
     * @param score The score to slash by.
     * @return amountToSP The amount to send to the storage provider.
     * @return amountToBeRedirected The amount to send to the slash recipient address.
     */
    function _slashByScore(uint256 amount, uint256 score)
        private
        pure
        returns (uint256 amountToSP, uint256 amountToBeRedirected)
    {
        if (score >= 80) {
            return (amount, 0);
        } else if (score >= 40 && score < 80) {
            uint256 amountSlashed = amount / 10;
            return (amount - amountSlashed, amountSlashed);
        } else {
            uint256 amountSlashed = amount / 2;
            return (amount - amountSlashed, amountSlashed);
        }
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
