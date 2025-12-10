// solhint-disable use-natspec
// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

// solhint-disable-next-line max-states-count
// solhint-disable function-max-lines
contract ActorIdMock {
    bytes internal _getClaimsResult;

    error MethodNotFound();

    receive() external payable {}

    function setGetClaimsResult(bytes memory d) public {
        _getClaimsResult = d;
    }

    function handleGetBeneficiary(uint64 target) internal returns (bytes memory) {
        if (target == 10000) {
            return abi.encode(
                0, 0x51, hex"82824400C2A101834E0002863C1F5CDAE42F95400000004000854400D4C1014207D01A006ACFC0F5F4"
            );
        }
        if (target == 20000) {
            return abi.encode(
                0, 0x51, hex"82824400C2A101834E0002863C1F5CDAE42F9540000000401A005B8D80854400D4C1014207D01A006ACFC0F5F4"
            );
        }
        if (target == 30000) {
            return abi.encode(
                0,
                0x51,
                hex"82824400C2A101834E0002863C1F5CDAE42F95400000004D00A18F07D736B90BE5500000001A005B8D80854400D4C1014E000278EF7C9A6BF689E106F000011A006ACFC0F5F4"
            );
        }
        if (target == 40000) {
            return abi.encode(0, 0x51, hex"82824083404000F6");
        }
        if (target == 50000) {
            return abi.encode(0, 0x51, hex"82824400C2A101834201FF410A1A005B8D80854400D4C1014207D01A006ACFC0F5F4");
        }
        if (target == 60000) {
            return abi.encode(
                0,
                0x51,
                hex"82824400C2A101834E0002863C1F5CDAE42F95400000004D00A18F07D736B90BE5500000001A005B8D80854400D4C1014207D01A006ACFC0F5F4"
            );
        }
        if (target == 70000) {
            return
                abi.encode(0, 0x51, hex"82824300FE07834E0002863C1F5CDAE42F95400000004A0007DAB13E6B1EE374501A000F3E58F6");
        }
        if (target == 80000) {
            return abi.encode(
                0,
                0x51,
                hex"82824400C2A101834E0002863C1F5CDAE42F95400000004D00A18F07D736B90BE5500000001A005B8D80854400D4C1014E000278EF7C9A6BF689E106F000011A006ACFC0F5F4"
            );
        }
        if (target == 90000) {
            return abi.encode(
                0,
                0x51,
                hex"82824400C2A101834E0002863C1F5CDAE42F954000000042000A1A005B8D80854400D4C1014E000278EF7C9A6BF689E106F000011A006ACFC0F5F4"
            );
        }
        if (target == 100000) {
            return abi.encode(
                0,
                0x51,
                hex"82824400C2A101834E0002863C1F5CDAE42F95400000004E000278EF7C9A6BF689E106F000011A005B8D80854400D4C1014E000278EF7C9A6BF689E106FFFFFF1A004C4B40F5F4"
            );
        }
        if (target == 12345) {
            // Simulate error exit code
            return abi.encode(1, 0x51, hex"82824083404000F6");
        }
    }

    function handleChangeBeneficiary(uint64 target) internal returns (bytes memory) {
        if (target == 12345) {
            // Simulate error inside MienerAPI.changeBeneficiary
            return abi.encode(0, 0x51, hex"00");
        }
        if (target == 10000 || target == 80000) {
            // Simulate error exit code
            return abi.encode(1, 0x00, "");
        }
        if (target == 20000) {
            return abi.encode(0, 0x00, "");
        }
        if (target == 30000) {
            return abi.encode(0, 0x00, "");
        }
    }

    function handleAddVerifiedClient() internal pure returns (bytes memory) {
        // Success send
        return abi.encode(0, 0x00, "");
    }

    // solhint-disable-next-line no-complex-fallback
    fallback(bytes calldata data) external payable returns (bytes memory) {
        (uint256 methodNum,,,,, uint64 target) = abi.decode(data, (uint64, uint256, uint64, uint64, bytes, uint64));
        if (methodNum == 4158972569) {
            return handleGetBeneficiary(target);
        }
        if (methodNum == 1570634796) {
            return handleChangeBeneficiary(target);
        }
        if (methodNum == 3916220144) {
            return handleAddVerifiedClient();
        }
        if (target == 6 && methodNum == 2199871187) {
            // verifreg get claims
            return abi.encode(0, 0x51, _getClaimsResult);
        }
        if (target == 7 && methodNum == 80475954) {
            // datacap transfer
            return abi.encode(0, 0x51, hex"83410041004100");
        }
        // if (target == 321 && methodNum == 3275365574) {
        //     return abi.encode(0, 0x51, hex"824400A58B0140");
        // }
        if (target == 321 && methodNum == 3275365574) {
            return abi.encode(0, 0x51, hex"824300C10240");
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

// SP3 - 30000 - 82824400C2A101834E0002863C1F5CDAE42F95400000004D00A18F07D736B90BE5500000001A005B8D80854400D4C1014E000278EF7C9A6BF689E106F000011A006ACFC0F5F4
// GetBeneficiaryReturn {
//      ActiveBeneficiary active; beneficiary = f020674 term { quota: 1000, used_quota: 10, expiration: 6000000 }
//      PendingBeneficiaryChange proposed; = { beneficiary = f024788, new_quota: 195884047900000000000000000001, new_expiration: 7000000, approved_by_beneficiary: true, approved_by_nominee: false } }

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

//SP7 - 70000 - 82824300FE07834E0002863C1F5CDAE42F95400000004A0007DAB13E6B1EE374501A000F3E58F6
// GetBeneficiaryReturn {
//      ActiveBeneficiary active; beneficiary = f01022 term { quota: 200000000000000000000000000000, used_quota: 144885653716913583184, expiration: 999000 }
//      PendingBeneficiaryChange proposed; = null

// SP8 - 80000 - 82824400C2A101834E0002863C1F5CDAE42F95400000004D00A18F07D736B90BE5500000001A005B8D80854400D4C1014E000278EF7C9A6BF689E106F000011A006ACFC0F5F4
// GetBeneficiaryReturn {
//      ActiveBeneficiary active; beneficiary = f020674 term { quota: 1000, used_quota: 10, expiration: 6000000 }
//      PendingBeneficiaryChange proposed; = { beneficiary = f024788, new_quota: 195884047900000000000000000001, new_expiration: 7000000, approved_by_beneficiary: true, approved_by_nominee: false } }

// SP9 - 90000 - 82824400C2A101834E0002863C1F5CDAE42F954000000042000A1A005B8D80854400D4C1014E000278EF7C9A6BF689E106F000011A006ACFC0F5F4
// GetBeneficiaryReturn {
//      ActiveBeneficiary active; beneficiary = f020674 term { quota: 200000000000000000000000000000, used_quota: 10, expiration: 6000000 }
//      PendingBeneficiaryChange proposed; = { beneficiary = f024788, new_quota: 195884047900000000000000000001, new_expiration: 7000000, approved_by_beneficiary: true, approved_by_nominee: false } }

// SP10 - 100000 - 82824400C2A101834E0002863C1F5CDAE42F95400000004E000278EF7C9A6BF689E106F000011A005B8D80854400D4C1014E000278EF7C9A6BF689E106FFFFFF1A004C4B40F5F4
// GetBeneficiaryReturn {
//      ActiveBeneficiary active; beneficiary = f020674 term { quota: 200000000000000000000000000000, used_quota: 195884047900000000000000000001, expiration: 6000000 }
//      PendingBeneficiaryChange proposed; = { beneficiary = f024788, new_quota: 200000000000000000000268435455, new_expiration: 5000000, approved_by_beneficiary: true, approved_by_nominee: false } }
