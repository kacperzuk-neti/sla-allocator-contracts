// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";
import {DataCapAPI} from "filecoin-solidity/v0.8/DataCapAPI.sol";
import {BigInts} from "filecoin-solidity/v0.8/utils/BigInts.sol";
import {DataCapTypes} from "filecoin-solidity/v0.8/types/DataCapTypes.sol";
import {VerifRegTypes} from "filecoin-solidity/v0.8/types/VerifRegTypes.sol";
import {CBORDecoder} from "filecoin-solidity/v0.8/utils/CborDecode.sol";
import {VerifRegAPI} from "filecoin-solidity/v0.8/VerifRegAPI.sol";
import {UtilsHandlers} from "filecoin-solidity/v0.8/utils/UtilsHandlers.sol";
import {GetBeneficiary} from "./libs/GetBeneficiary.sol";
import {BeneficiaryFactory} from "./BeneficiaryFactory.sol";

/**
 * @title Client
 * @notice Upgradeable contract for managing client allowances with role-based access control
 */
contract Client is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    /**
     * @notice Allocator role which allows for increasing and decreasing allowances
     */
    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");
    uint32 private constant _FRC46_TOKEN_TYPE = 2233613279; // method_hash!("FRC46") as u32;
    address private constant _DATACAP_ADDRESS = address(0xfF00000000000000000000000000000000000007);

    /**
     * @notice Address of the BeneficiaryFactory contract
     */
    BeneficiaryFactory public beneficiaryFactory;

    /**
     * @notice Mapping of allowances for clients and providers using FilActorId
     */
    mapping(address client => mapping(CommonTypes.FilActorId provider => uint256 amount)) public allowances;

    /**
     * @notice  Precision factor for DataCap tokens (1e18)
     */
    uint256 public constant TOKEN_PRECISION = 1e18;

    /**
     * @notice Event emitted when an allowance is changed
     * @param client Client address
     * @param provider Provider fil actor id
     * @param allowanceBefore Allowance before the change
     * @param allowanceAfter Allowance after the change
     */
    event AllowanceChanged(
        address indexed client, CommonTypes.FilActorId indexed provider, uint256 allowanceBefore, uint256 allowanceAfter
    );

    // solhint-disable gas-indexed-events
    /**
     * @notice Emitted when DataCap is allocated to a SP.
     * @param client The address of the client.
     * @param amount The amount of DataCap allocated.
     */
    event DatacapSpent(address indexed client, uint256 amount);
    // solhint-enable gas-indexed-events

    /**
     * @notice Error emitted when the amount is zero
     */
    error AmountEqualsZero();

    /**
     * @notice Error emitted when the allowance is zero
     */
    error AlreadyZero();

    /**
     * @notice Error thrown when amount is invalid
     */
    error InvalidAmount();

    /**
     * @notice Error thrown when senders balance is less than his allowance
     */
    error InsufficientAllowance();

    /**
     * @notice Datacap transfer failed
     */
    error TransferFailed(int256 exitCode);

    /**
     * @notice Error thrown when claim extension request length is invalid
     */
    error InvalidClaimExtensionRequest();

    /**
     * @notice Error thrown when allocation request length is invalid
     */
    error InvalidAllocationRequest();

    /**
     * @notice GetClaims call to VerifReg faile
     */
    error GetClaimsCallFailed();

    /**
     * @notice Error thrown when operator_data length is invalid
     */
    error InvalidOperatorData();

    /**
     * @notice Thrown if trying to receive invalid token
     */
    error InvalidTokenReceived();

    /**
     * @notice Thrown if trying to receive unsupported token type
     */
    error UnsupportedType();

    /**
     * @notice Thrown if caller is invalid
     */
    error InvalidCaller(address caller, address expectedCaller);

    /**
     * @notice Thrown if beneficiary contract address doesn't match the one registered in BeneficiaryFactory
     */
    error InvalidBeneficiary(address beneficiary, address expectedBeneficiary);

    struct ProviderAllocation {
        CommonTypes.FilActorId provider;
        uint64 size;
    }

    struct ProviderClaim {
        CommonTypes.FilActorId provider;
        CommonTypes.FilActorId claim;
    }

    /**
     * @notice Disabled constructor (proxy pattern)
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Contract initializator. Should be called during deployment
     * @param admin Contract owner
     * @param allocator Address of the allocator contract that can increase and decrease allowances
     * @param beneficiaryFactory_ Instance of BeneficiaryFactory
     */
    function initialize(address admin, address allocator, BeneficiaryFactory beneficiaryFactory_) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ALLOCATOR_ROLE, allocator);
        beneficiaryFactory = beneficiaryFactory_;
    }

    /**
     * @notice Increases the allowance for a given client and provider
     * @param client Address of the client
     * @param provider Address of the provider
     * @param amount Amount to increase the allowance by
     * Emits an AllowanceChanged event
     */
    function increaseAllowance(address client, CommonTypes.FilActorId provider, uint256 amount)
        external
        onlyRole(ALLOCATOR_ROLE)
    {
        if (amount == 0) revert AmountEqualsZero();
        uint256 allowanceBefore = allowances[client][provider];
        allowances[client][provider] += amount;
        emit AllowanceChanged(client, provider, allowanceBefore, allowances[client][provider]);
    }

    /**
     * @notice Decreases the allowance for a given client and provider
     * @param client Address of the client
     * @param provider Address of the provider
     * @param amount Amount to decrease the allowance by
     * @dev If the amount is greater than the allowance, the allowance is set to 0
     * Emits an AllowanceChanged event
     */
    function decreaseAllowance(address client, CommonTypes.FilActorId provider, uint256 amount)
        external
        onlyRole(ALLOCATOR_ROLE)
    {
        if (amount == 0) revert AmountEqualsZero();
        uint256 allowanceBefore = allowances[client][provider];
        if (allowanceBefore == 0) {
            revert AlreadyZero();
        }
        if (allowanceBefore < amount) {
            amount = allowanceBefore;
        }
        allowances[client][provider] -= amount;
        emit AllowanceChanged(client, provider, allowanceBefore, allowances[client][provider]);
    }

    /**
     * @notice This function transfers DataCap tokens from the client to the storage provider
     * @dev This function can only be called by the client
     * @param params The parameters for the transfer
     * @dev Reverts with InsufficientAllowance if caller doesn't have sufficient allowance
     * @dev Reverts with InvalidAmount when parsing amount from BigInt to uint256 failed
     */
    function transfer(DataCapTypes.TransferParams calldata params) external {
        int256 exitCode;
        (uint256 tokenAmount, bool failed) = BigInts.toUint256(params.amount);
        if (failed) revert InvalidAmount();
        uint256 datacapAmount = tokenAmount / TOKEN_PRECISION;

        (ProviderAllocation[] memory allocations, ProviderClaim[] memory claimExtensions) =
            _deserializeVerifregOperatorData(params.operator_data);

        _verifyAndRegisterAllocations(allocations);
        _verifyAndRegisterClaimExtensions(claimExtensions);
        emit DatacapSpent(msg.sender, datacapAmount);
        /// @custom:oz-upgrades-unsafe-allow-reachable delegatecall
        (exitCode,) = DataCapAPI.transfer(params);
        if (exitCode != 0) {
            revert TransferFailed(exitCode);
        }
    }

    /**
     * @notice Verifies and registers allocations.
     * @param allocations The array of provider allocations.
     */
    function _verifyAndRegisterAllocations(ProviderAllocation[] memory allocations) internal {
        for (uint256 i = 0; i < allocations.length; i++) {
            ProviderAllocation memory alloc = allocations[i];
            GetBeneficiary.getBeneficiaryWithChecks(alloc.provider, beneficiaryFactory, true, true, true);
            uint256 size = alloc.size;
            if (allowances[msg.sender][alloc.provider] < size) {
                revert InsufficientAllowance();
            }
            allowances[msg.sender][alloc.provider] -= size;
        }
    }

    // solhint-disable function-max-lines
    /**
     * @notice Verifies and registers claim extensions.
     * @param claimExtensions The array of provider claims.
     */
    function _verifyAndRegisterClaimExtensions(ProviderClaim[] memory claimExtensions) internal {
        int256 exitCode;
        uint256 claimProvidersCount = 0;
        CommonTypes.FilActorId[] memory claimProviders = new CommonTypes.FilActorId[](claimExtensions.length);

        // get providers list with no duplicates
        for (uint256 i = 0; i < claimExtensions.length; i++) {
            ProviderClaim memory claim = claimExtensions[i];
            bool alreadyExists = false;
            for (uint256 j = 0; j < claimProvidersCount; j++) {
                if (CommonTypes.FilActorId.unwrap(claimProviders[j]) == CommonTypes.FilActorId.unwrap(claim.provider)) {
                    alreadyExists = true;
                    break;
                }
            }
            if (!alreadyExists) {
                claimProviders[claimProvidersCount++] = claim.provider;
            }
        }

        CommonTypes.FilActorId[] memory claims = new CommonTypes.FilActorId[](claimExtensions.length);
        for (uint256 providerIdx = 0; providerIdx < claimProvidersCount; providerIdx++) {
            // for each provider, find all claims for this provider
            uint256 claimCount = 0;
            CommonTypes.FilActorId provider = claimProviders[providerIdx];
            GetBeneficiary.getBeneficiaryWithChecks(provider, beneficiaryFactory, true, true, true);
            for (uint256 i = 0; i < claimExtensions.length; i++) {
                ProviderClaim memory claim = claimExtensions[i];
                if (CommonTypes.FilActorId.unwrap(claim.provider) == CommonTypes.FilActorId.unwrap(provider)) {
                    claims[claimCount++] = claim.claim;
                }
            }
            // solhint-disable-next-line no-inline-assembly
            assembly {
                mstore(claims, claimCount)
            }

            // get details of claims of this provider
            VerifRegTypes.GetClaimsParams memory getClaimsParams =
                VerifRegTypes.GetClaimsParams({provider: provider, claim_ids: claims});
            VerifRegTypes.GetClaimsReturn memory claimsDetails;
            (exitCode, claimsDetails) = VerifRegAPI.getClaims(getClaimsParams);
            if (exitCode != 0 || claimsDetails.batch_info.success_count != claims.length) {
                revert GetClaimsCallFailed();
            }

            // calculate total size of claims (a.k.a. how much datacap is going to this single SP)
            uint256 size = 0;
            for (uint256 i = 0; i < claimsDetails.claims.length; i++) {
                VerifRegTypes.Claim memory claim = claimsDetails.claims[i];
                size += claim.size;
            }
            if (allowances[msg.sender][provider] < size) {
                revert InsufficientAllowance();
            }
            allowances[msg.sender][provider] -= size;
        }
    }

    // solhint-disable function-max-lines
    /**
     * @notice Deserialize Verifreg Operator Data.
     * @param cborData The cbor encoded operator data.
     * @return allocations Array of provider allocations.
     * @return claimExtensions Array of provider claims.
     */
    function _deserializeVerifregOperatorData(bytes memory cborData)
        internal
        pure
        returns (ProviderAllocation[] memory allocations, ProviderClaim[] memory claimExtensions)
    {
        uint256 operatorDataLength;
        uint256 allocationRequestsLength;
        uint256 claimExtensionRequestsLength;
        uint64 provider;
        uint64 claimId;
        uint64 size;
        uint256 byteIdx = 0;

        (operatorDataLength, byteIdx) = CBORDecoder.readFixedArray(cborData, byteIdx);
        if (operatorDataLength != 2) revert InvalidOperatorData();

        (allocationRequestsLength, byteIdx) = CBORDecoder.readFixedArray(cborData, byteIdx);
        allocations = new ProviderAllocation[](allocationRequestsLength);
        for (uint256 i = 0; i < allocationRequestsLength; i++) {
            uint256 allocationRequestLength;
            (allocationRequestLength, byteIdx) = CBORDecoder.readFixedArray(cborData, byteIdx);

            if (allocationRequestLength != 6) {
                revert InvalidAllocationRequest();
            }

            (provider, byteIdx) = CBORDecoder.readUInt64(cborData, byteIdx);
            // slither-disable-start unused-return
            (, byteIdx) = CBORDecoder.readBytes(cborData, byteIdx); // data (CID)
            (size, byteIdx) = CBORDecoder.readUInt64(cborData, byteIdx);
            (, byteIdx) = CBORDecoder.readInt64(cborData, byteIdx); // termMin
            (, byteIdx) = CBORDecoder.readInt64(cborData, byteIdx); // termMax
            (, byteIdx) = CBORDecoder.readInt64(cborData, byteIdx); // expiration
            // slither-disable-end unused-return

            allocations[i].provider = CommonTypes.FilActorId.wrap(provider);
            allocations[i].size = size;
        }

        (claimExtensionRequestsLength, byteIdx) = CBORDecoder.readFixedArray(cborData, byteIdx);
        claimExtensions = new ProviderClaim[](claimExtensionRequestsLength);
        for (uint256 i = 0; i < claimExtensionRequestsLength; i++) {
            uint256 claimExtensionRequestLength;
            (claimExtensionRequestLength, byteIdx) = CBORDecoder.readFixedArray(cborData, byteIdx);

            if (claimExtensionRequestLength != 3) {
                revert InvalidClaimExtensionRequest();
            }

            (provider, byteIdx) = CBORDecoder.readUInt64(cborData, byteIdx);
            (claimId, byteIdx) = CBORDecoder.readUInt64(cborData, byteIdx);
            // slither-disable-start unused-return
            (, byteIdx) = CBORDecoder.readInt64(cborData, byteIdx); // termMax
            // slither-disable-end unused-return

            claimExtensions[i].provider = CommonTypes.FilActorId.wrap(provider);
            claimExtensions[i].claim = CommonTypes.FilActorId.wrap(claimId);
        }
    }

    // solhint-disable func-name-mixedcase
    /**
     * @notice The handle_filecoin_method function is a universal entry point for calls
     * coming from built-in Filecoin actors. Datacap is an FRC-46 Token. Receiving FRC46
     * tokens requires implementing a Receiver Hook:
     * https://github.com/filecoin-project/FIPs/blob/master/FRCs/frc-0046.md#receiver-hook.
     * We use handle_filecoin_method to handle the receiver hook and make sure that the token
     * sent to our contract is freshly minted Datacap and reject all other calls and transfers.
     * @param method Method number
     * @param inputCodec Codec of the payload
     * @param params Params of the call
     * @return exitCode The exit code of the operation
     * @return codec The codec used for the response
     * @return data The response data
     * @dev Reverts if trying to send a unsupported token type
     * @dev Reverts if trying to receive invalid token
     */
    function handle_filecoin_method(uint64 method, uint64 inputCodec, bytes calldata params)
        external
        view
        returns (uint32 exitCode, uint64 codec, bytes memory data)
    {
        if (msg.sender != _DATACAP_ADDRESS) revert InvalidCaller(msg.sender, _DATACAP_ADDRESS);
        CommonTypes.UniversalReceiverParams memory receiverParams =
            UtilsHandlers.handleFilecoinMethod(method, inputCodec, params);
        if (receiverParams.type_ != _FRC46_TOKEN_TYPE) revert UnsupportedType();
        (uint256 tokenReceivedLength,) = CBORDecoder.readFixedArray(receiverParams.payload, 0);
        if (tokenReceivedLength != 6) revert InvalidTokenReceived();
        exitCode = 0;
        codec = 0;
        data = "";
    }

    // solhint-enable func-name-mixedcase

    /**
     * @notice Sets the address of the beneficiary registry used by this contract
     * @dev Restricted to callers possessing the ADMIN_ROLE
     * @param newBeneficiaryFactory Instance of BeneficiaryFactory
     */
    function setBeneficiaryFactory(BeneficiaryFactory newBeneficiaryFactory) external onlyRole(DEFAULT_ADMIN_ROLE) {
        beneficiaryFactory = newBeneficiaryFactory;
    }

    // solhint-disable no-empty-blocks
    /**
     * @notice Internal function used to implement new logic and check if upgrade is authorized
     * @dev Will revert (reject upgrade) if upgrade isn't called by DEFAULT_ADMIN_ROLE
     * @param newImplementation Address of new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
    // solhint-enable no-empty-blocks
}
