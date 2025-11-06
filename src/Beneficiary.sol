// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {MinerTypes} from "filecoin-solidity/v0.8/types/MinerTypes.sol";
import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";
import {MinerAPI} from "filecoin-solidity/v0.8/MinerAPI.sol";
import {BigInts} from "filecoin-solidity/v0.8/utils/BigInts.sol";
import {SLARegistry} from "./SLARegistry.sol";
import {SLAAllocator} from "./SLAAllocator.sol";

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
     * @notice The ID of the storage provider.
     */
    CommonTypes.FilActorId public provider;

    /**
     * @notice The SLA Allocator contract.
     */
    SLAAllocator public slaAllocator;

    /**
     * @notice The address to set as the slash recipient.
     */
    address public slashRecipient;

    /**
     * @notice Emits a SlashRecipientUpdated event.
     * @param slashRecipient The address to set as the slash recipient.
     */
    event SlashRecipientUpdated(address indexed slashRecipient);

    // solhint-disable gas-indexed-events
    /**
     * @notice Emits a Withdrawn event.
     * @param to The address to withdraw the balance to.
     * @param amountToSP The amount to send to the storage provider.
     * @param amountToRedirected The amount to send to the redirected address.
     */
    event Withdrawn(address indexed to, uint256 amountToSP, uint256 amountToRedirected);
    // solhint-enable gas-indexed-events

    /**
     * @notice Emitted when changeBeneficiary proposal is approved
     * @param minerID The miner actor id to change the beneficiary for
     * @param newBeneficiary The Filecoin address of the new beneficiary
     * @param newQuota The new quota (FIL atto) value passed through
     * @param newExpirationChainEpoch The new expiration chain epoch
     */
    event BeneficiaryProposalSigned(
        CommonTypes.FilActorId indexed minerID,
        CommonTypes.FilAddress indexed newBeneficiary,
        uint256 newQuota,
        int64 newExpirationChainEpoch
    );

    /**
     * @notice Error thrown when the FVM call returns a non-zero exit code.
     * @param exitCode The exit code returned by the FVM call.
     */
    error ExitCodeError(int256 exitCode);

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
     * @param manager Address of the contract manager
     * @param provider_ Address of the storage provider
     * @param slaAllocator_ Address of the SLA registry contract
     */
    function initialize(address admin, address manager, CommonTypes.FilActorId provider_, SLAAllocator slaAllocator_)
        public
        initializer
    {
        __AccessControl_init();
        _setRoleAdmin(WITHDRAWER_ROLE, MANAGER_ROLE);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, manager);
        _grantRole(WITHDRAWER_ROLE, manager);

        provider = provider_;
        slaAllocator = slaAllocator_;
    }

    /**
     * @notice Emits a SlashRecipientUpdated event.
     * @param slashRecipient_ The address to set as the slash recipient.
     * @dev Only the admin can set the slash recipient.
     */
    function setSlashRecipient(address slashRecipient_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        slashRecipient = slashRecipient_;
        emit SlashRecipientUpdated(slashRecipient_);
    }

    /**
     * @notice Withdraws the balance of the contract to the specified address. Emits a Withdrawn event.
     * @dev The balance is split between the storage provider and the redirected address based on the score. but for now its always 100% to SP
     * @param to The address to withdraw the balance to.
     */
    function withdraw(address payable to) public onlyRole(WITHDRAWER_ROLE) {
        uint256 amount = address(this).balance;
        address client = slaAllocator.providerClients(provider);
        SLARegistry slaRegistry = SLARegistry(slaAllocator.slaContracts(client, provider));
        uint256 score = slaRegistry.score(client, provider);
        (uint256 amountToSP, uint256 amountToBeRedirected) = _slashByScore(amount, score);

        emit Withdrawn(to, amountToSP, amountToBeRedirected);
        (bool sent,) = to.call{value: amount}("");
        if (!sent) {
            revert WithdrawalFailed();
        }
    }

    // solhint-disable gas-strict-inequalities
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

    // solhint-enable gas-strict-inequalities

    /**
     * @notice Submit a change to the miner's beneficiary parameters by calling the Miner actor.
     * @dev Builds MinerTypes.ChangeBeneficiaryParams and calls MinerAPI.changeBeneficiary.
     *      Emits BeneficiaryChanged  and reverts with ExitCodeError if the actor call returns non-zero.
     *      Only callable by DEFAULT_ADMIN_ROLE.
     * @param minerID The miner actor id to change the beneficiary for
     * @param newBeneficiary The new beneficiary FilAddress
     * @param newQuota The new quota as uint256 (FIL atto)
     * @param newExpirationChainEpoch The new expiration chain epoch (int64)
     */
    function changeBeneficiary(
        CommonTypes.FilActorId minerID,
        CommonTypes.FilAddress calldata newBeneficiary,
        uint256 newQuota,
        int64 newExpirationChainEpoch
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        MinerTypes.ChangeBeneficiaryParams memory params =
            MinerTypes.ChangeBeneficiaryParams({
                new_beneficiary: newBeneficiary,
                new_quota: BigInts.fromUint256(newQuota),
                new_expiration: CommonTypes.ChainEpoch.wrap(newExpirationChainEpoch)
            });
        emit BeneficiaryProposalSigned(minerID, newBeneficiary, newQuota, newExpirationChainEpoch);
        int256 exitCode = MinerAPI.changeBeneficiary(minerID, params);
        if (exitCode != 0) {
            revert ExitCodeError(exitCode);
        }
    }

    // solhint-disable-next-line use-natspec
    receive() external payable {}
}
