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
import {SendAPI} from "filecoin-solidity/v0.8/SendAPI.sol";
import {MinerUtils} from "./libs/MinerUtils.sol";
import {Client} from "./Client.sol";

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
     * @notice The role to set terminated claims.
     */
    bytes32 public constant TERMINATION_ORACLE = keccak256("TERMINATION_ORACLE");
    /**
     * @notice The ID of the storage provider.
     */
    CommonTypes.FilActorId public provider;

    /**
     * @notice The SLA Allocator contract.
     */
    SLAAllocator public slaAllocator;

    /**
     * @notice The Client contract.
     */
    Client public clientContract;

    /**
     * @notice The address to set as the burn address.
     */
    address public burnAddress;

    /**
     * @notice Emits a BurnAddressUpdated event.
     * @param burnAddress The address to set as the burn address.
     */
    event BurnAddressUpdated(address indexed burnAddress);

    /**
     * @notice Emits a SLAAllocatorUpdated event.
     * @param newSLAAllocator The SLA allocator to set.
     */
    event SLAAllocatorUpdated(SLAAllocator newSLAAllocator);

    // solhint-disable gas-indexed-events
    /**
     * @notice Emits a Withdrawn event.
     * @param recipient The FilAddress to withdraw the balance to.
     * @param amountToSP The amount to send to the storage provider.
     * @param amountToRedirected The amount to send to the redirected address.
     */
    event Withdrawn(CommonTypes.FilAddress indexed recipient, uint256 amountToSP, uint256 amountToRedirected);
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
     * @notice Emitted when beneficiary is accepted
     * @param minerID The miner actor id to accept the beneficiary for
     * @param newBeneficiary The new beneficiary FilAddress
     */
    event BeneficiaryAccepted(CommonTypes.FilActorId indexed minerID, CommonTypes.FilAddress indexed newBeneficiary);

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
     * @param burnAddress_ Address of the burn address
     * @param clientContract_ Address of the Client contract
     */
    function initialize(
        address admin,
        address manager,
        CommonTypes.FilActorId provider_,
        SLAAllocator slaAllocator_,
        address burnAddress_,
        Client clientContract_
    ) external initializer {
        __AccessControl_init();
        _setRoleAdmin(WITHDRAWER_ROLE, MANAGER_ROLE);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, manager);
        _grantRole(WITHDRAWER_ROLE, manager);

        provider = provider_;
        slaAllocator = slaAllocator_;
        burnAddress = burnAddress_;
        clientContract = clientContract_;
    }

    /**
     * @notice Emits a BurnAddressUpdated event.
     * @param newBurnAddress The address to set as the burn address.
     * @dev Only the admin can set the burn address.
     */
    function setBurnAddress(address newBurnAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        burnAddress = newBurnAddress;
        emit BurnAddressUpdated(newBurnAddress);
    }

    /**
     * @notice Sets the SLA allocator.
     * @param newSLAAllocator The SLA allocator to set.
     * @dev Only the admin can set the SLA allocator.
     */
    function setSLAAllocator(SLAAllocator newSLAAllocator) public onlyRole(DEFAULT_ADMIN_ROLE) {
        slaAllocator = newSLAAllocator;
        emit SLAAllocatorUpdated(newSLAAllocator);
    }

    /**
     * @notice Withdraws the balance of the contract to the specified address. Emits a Withdrawn event.
     * @dev The balance is split between the storage provider and the redirected address based on the score. but for now its always 100% to SP
     *      Reverts with WithdrawalFailed if the SendAPI.send method returns a non-zero exit code.
     * @param recipient The FilAddress to withdraw the balance to.
     */
    function withdraw(CommonTypes.FilAddress calldata recipient) external onlyRole(WITHDRAWER_ROLE) {
        uint256 amount = address(this).balance;
        address[] memory spClients = clientContract.getSPClients(provider);
        uint256 totalSize = 0;
        uint256[] memory sizePerClient = new uint256[](spClients.length);
        uint256[] memory scorePerClient = new uint256[](spClients.length);
        for (uint256 i = 0; i < spClients.length; i++) {
            SLARegistry slaRegistry = SLARegistry(slaAllocator.slaContracts(spClients[i], provider));
            scorePerClient[i] = slaRegistry.score(spClients[i], provider);
            sizePerClient[i] = clientContract.getClientSpActiveDataSize(spClients[i], provider);
            totalSize += sizePerClient[i];
        }
        uint256 finalScore = 0;
        if (totalSize == 0) {
            finalScore = 100;
        } else {
            for (uint256 i = 0; i < spClients.length; i++) {
                uint256 weight = (sizePerClient[i] * 1e18) / totalSize;
                finalScore += (weight * scorePerClient[i]) / 1e18;
            }
        }
        (uint256 amountToSP, uint256 amountToBeRedirected) = _slashByScore(amount, finalScore);
        emit Withdrawn(recipient, amountToSP, amountToBeRedirected);
        // solhint-disable-next-line check-send-result
        int256 exitCode = SendAPI.send(recipient, amount);
        if (exitCode != 0) {
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
        if (score < 50) {
            uint256 amountSlashed = amount * 9 / 10;
            return (amount - amountSlashed, amountSlashed);
        } else if (score < 80) {
            uint256 amountSlashed = amount / 2;
            return (amount - amountSlashed, amountSlashed);
        } else {
            return (amount, 0);
        }
    }

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

    /**
     * @notice Marks the given claims as terminated early.
     * @dev Only callable by TERMINATION_ORACLE role.
     * @param claims An array of claim IDs to mark as terminated.
     */
    function claimsTerminatedEarly(uint64[] calldata claims) external onlyRole(TERMINATION_ORACLE) {
        for (uint256 i = 0; i < claims.length; i++) {
            terminatedClaims[claims[i]] = true;
        }
    }

    /**
     * @notice Accepts a pending beneficiary change proposal for this contract on the miner actor.
     * @param minerId The miner actor id to accept the beneficiary change for
     * @dev Anyone can call this function. It:
     *      - Uses MinerUtils to fetch and validate the current pending beneficiary proposal for `minerId`.
     *      - Calls MinerAPI.changeBeneficiary with the proposed parameters to accept the change.
     *      - Reverts with ExitCodeError if the actor call returns a non-zero exit code.
     */
    function acceptBeneficiary(CommonTypes.FilActorId minerId) external {
        MinerTypes.GetBeneficiaryReturn memory pendingBeneficiary =
            MinerUtils.getBeneficiaryWithChecksForProposed(minerId);

        emit BeneficiaryAccepted(minerId, pendingBeneficiary.proposed.new_beneficiary);
        int256 exitCode = MinerAPI.changeBeneficiary(
            minerId,
            MinerTypes.ChangeBeneficiaryParams({
                new_beneficiary: pendingBeneficiary.proposed.new_beneficiary,
                new_quota: pendingBeneficiary.proposed.new_quota,
                new_expiration: pendingBeneficiary.proposed.new_expiration
            })
        );
        if (exitCode != 0) {
            revert ExitCodeError(exitCode);
        }
    }

    // solhint-disable-next-line use-natspec
    receive() external payable {}
}
