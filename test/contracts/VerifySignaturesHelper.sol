// SPDX-License-Identifier: MIT
// solhint-disable use-natspec

pragma solidity ^0.8.24;

import {SLAAllocator} from "../../src/SLAAllocator.sol";

contract VerifySignaturesHelper is SLAAllocator {
    function digestToSignExt(bytes32 structHash) external view returns (bytes32) {
        return _hashTypedDataV4(structHash);
    }

    function hashPassportExt(Passport calldata passport) external pure returns (bytes32) {
        return _hashPassport(passport);
    }

    function hashManualAttestationExt(ManualAttestation calldata attestation) external pure returns (bytes32) {
        return _hashManualAttestation(attestation);
    }

    function hashPaymentTransactionExt(PaymentTransaction calldata txn) external pure returns (bytes32) {
        return _hashPaymentTransaction(txn);
    }

    function recoverFromSigExt(bytes32 structHash, bytes calldata signature) external view returns (address) {
        return _recoverFromSig(structHash, signature);
    }

    function verifyPassportSignedExt(PassportSigned calldata passport) external view returns (bool) {
        return verifyPassportSigned(passport);
    }

    function verifyPaymentTransactionSignedExt(PaymentTransactionSigned calldata txn) external view returns (bool) {
        return verifyPaymentTransactionSigned(txn);
    }

    function verifyManualAttestationSignedExt(ManualAttestationSigned calldata attestation)
        external
        view
        returns (bool)
    {
        return verifyManualAttestationSigned(attestation);
    }

    function domainSeparatorExt() external view returns (bytes32) {
        return _domainSeparatorV4();
    }
}
