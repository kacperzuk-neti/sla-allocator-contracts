// solhint-disable use-natspec
// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

contract ActorIdMock {
    error MethodNotFound();

    receive() external payable {}

    // solhint-disable-next-line no-complex-fallback
    fallback(bytes calldata data) external payable returns (bytes memory) {
        (uint256 methodNum,,,,, uint64 target) = abi.decode(data, (uint64, uint256, uint64, uint64, bytes, uint64));
        if (methodNum == 4158972569 && target == 10000) {
            return abi.encode(
                0, 0x51, hex"82824400C2A101834E0002863C1F5CDAE42F95400000004000854400D4C1014207D01A006ACFC0F5F4"
            );
        }
        if (methodNum == 4158972569 && target == 20000) {
            return abi.encode(
                0, 0x51, hex"82824400C2A101834E0002863C1F5CDAE42F9540000000401A005B8D80854400D4C1014207D01A006ACFC0F5F4"
            );
        }
        if (methodNum == 4158972569 && target == 30000) {
            return abi.encode(0, 0x51, hex"82824400C2A101834203E8410A1A005B8D80854400D4C1014207D01A006ACFC0F5F4");
        }
        if (methodNum == 4158972569 && target == 40000) {
            return abi.encode(0, 0x51, hex"82824083404000F6");
        }
        if (methodNum == 4158972569 && target == 50000) {
            return abi.encode(0, 0x51, hex"82824400C2A101834201FF410A1A005B8D80854400D4C1014207D01A006ACFC0F5F4");
        }
        if (methodNum == 4158972569 && target == 60000) {
            return abi.encode(
                0,
                0x51,
                hex"82824400C2A101834E0002863C1F5CDAE42F95400000004D00A18F07D736B90BE5500000001A005B8D80854400D4C1014207D01A006ACFC0F5F4"
            );
        }
        if (methodNum == 4158972569 && target == 12345) {
            // Simulate error exit code
            return abi.encode(1, 0x51, hex"82824083404000F6");
        }
        if (methodNum == 1570634796 && target == 12345) {
            // Simulate error inside MienerAPI.changeBeneficiary
            return abi.encode(0, 0x51, hex"00");
        }
        if (methodNum == 1570634796 && target == 10000) {
            // Simulate error exit code
            return abi.encode(1, 0x00, "");
        }
        if (methodNum == 1570634796 && target == 20000) {
            return abi.encode(0, 0x00, "");
        }
        if (methodNum == 3916220144) {
            // Success send
            return abi.encode(0, 0x00, "");
        }

        revert MethodNotFound();
    }
}

// SP1 - 10000 - 82824400a58b0183404000f6 - same as owner
// GetBeneficiaryReturn {
//      ActiveBeneficiary active; beneficiary = f010000 term { quota: 200000000000000000000000000000, used_quota: 0, expiration: 0 }
//      PendingBeneficiaryChange proposed; = null

// SP2 - 20000 - 82824400B8C101834203E8410A1A005B8D80F6
// GetBeneficiaryReturn {
//      ActiveBeneficiary active; beneficiary = f024760 term { quota: 200000000000000000000000000000, used_quota: 10, expiration: 6000000 }
//      PendingBeneficiaryChange proposed; = null

// SP3 - 30000 - 82824400C2A101834203E8410A1A005B8D80854400D4C1014207D01A006ACFC0F5F4
// GetBeneficiaryReturn {
//      ActiveBeneficiary active; beneficiary = f020674 term { quota: 1000, used_quota: 10, expiration: 6000000 }
//      PendingBeneficiaryChange proposed; = { beneficiary = f024788, new_quota: 2000, new_expiration: 7000000, approved_by_beneficiary: true, approved_by_nominee: false } }

// SP4 - 40000 - 82824083404000f6
// GetBeneficiaryReturn {
//      ActiveBeneficiary active; beneficiary = null term { quota: 0, used_quota: 0, expiration: 0 }
//      PendingBeneficiaryChange proposed; = null

// SP5 - 50000 - 82824400C2A101834201FF410A1A005B8D80854400D4C1014207D01A006ACFC0F5F4
// GetBeneficiaryReturn {
//      ActiveBeneficiary active; beneficiary = f023551 term { quota: -255, used_quota: 10, expiration: 6000000 }
//      PendingBeneficiaryChange proposed; = { beneficiary = f024788, new_quota: 2000, new_expiration: 7000000, approved_by_beneficiary: true, approved_by_nominee: false } }

//SP6 - 60000 - 82824400C2A101834E0002863C1F5CDAE42F95400000004D00A18F07D736B90BE5500000001A005B8D80854400D4C1014207D01A006ACFC0F5F4
// GetBeneficiaryReturn {
//      ActiveBeneficiary active; beneficiary = f010000 term { quota: 200000000000000000000000000000, used_quota: 50000000000000000000000000000, expiration: 2000000 }
//      PendingBeneficiaryChange proposed; = { beneficiary = f024760, new_quota: 13943041, new_expiration: 2000, approved_by_beneficiary: true, approved_by_nominee: false } }
