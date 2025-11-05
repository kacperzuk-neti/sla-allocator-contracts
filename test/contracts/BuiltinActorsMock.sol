// solhint-disable use-natspec
// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

contract BuiltinActorsMock {
    error MethodNotFound();

    receive() external payable {}

    // solhint-disable-next-line no-complex-fallback
    fallback(bytes calldata data) external payable returns (bytes memory) {
        (uint256 methodNum,,,,, uint64 target) = abi.decode(data, (uint64, uint256, uint64, uint64, bytes, uint64));
        if (methodNum == 4158972569 && target == 10000) {
            return abi.encode(0, 0x51, hex"82824300904E83404000F6");
        }
        if (methodNum == 4158972569 && target == 20000) {
            return abi.encode(0, 0x51, hex"82824400B8C101834203E8410A1A005B8D80F6");
        }
        if (methodNum == 4158972569 && target == 30000) {
            return abi.encode(0, 0x51, hex"82824400C2A101834203E8410A1A005B8D80854400D4C1014207D01A006ACFC0F5F4");
        }
        if (methodNum == 4158972569 && target == 12345) {
            // Simulate error exit code
            return abi.encode(1, 0x51, hex"82824083404000F6");
        }
        revert MethodNotFound();
    }
}

// SP1 - 10000 - 82824400a58b0183404000f6 - same as owner
// GetBeneficiaryReturn {
//      ActiveBeneficiary active; beneficiary = f010000 term { quota: 0, used_quota: 0, expiration: 0 }
//      PendingBeneficiaryChange proposed; = null

// SP2 - 20000 - 82824400B8C101834203E8410A1A005B8D80F6
// GetBeneficiaryReturn {
//      ActiveBeneficiary active; beneficiary = f024760 term { quota: 1000, used_quota: 10, expiration: 6000000 }
//      PendingBeneficiaryChange proposed; = null

// SP3 - 30000 - 82824400C2A101834203E8410A1A005B8D80854400D4C1014207D01A006ACFC0F5F4
// GetBeneficiaryReturn {
//      ActiveBeneficiary active; beneficiary = f020674 term { quota: 1000, used_quota: 10, expiration: 6000000 }
//      PendingBeneficiaryChange proposed; = { beneficiary = f024788, new_quota: 2000, new_expiration: 7000000, approved_by_beneficiary: true, approved_by_nominee: false } }
