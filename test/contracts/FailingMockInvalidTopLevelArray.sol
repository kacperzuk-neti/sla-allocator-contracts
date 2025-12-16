// solhint-disable use-natspec
// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

contract FailingMockInvalidTopLevelArray {
    error MethodNotFound();

    receive() external payable {}

    // solhint-disable-next-line no-complex-fallback
    fallback(bytes calldata data) external payable returns (bytes memory) {
        (uint256 methodNum,,,,, uint64 target) = abi.decode(data, (uint64, uint256, uint64, uint64, bytes, uint64));
        if (methodNum == 4158972569 && target == 20000) {
            return abi.encode(
                0, 0x51, hex"82824400C2A101834E0002863C1F5CDAE42F9540000000401A005B8D80854400D4C1014207D01A006ACFC0F5F4"
            );
        }
        if (target == 6 && methodNum == 2199871187) {
            // verifreg get claims
            return abi.encode(
                0,
                0x51,
                hex"8282018081881903E81866D82A5828000181E203922020071E414627E89D421B3BAFCCB24CBA13DDE9B6F388706AC8B1D48E58935C76381908001A003815911A005034D60000"
            );
        }
        if (target == 7 && methodNum == 80475954) {
            return abi.encode(0, 0x51, hex"83410041004A84808201808200808101");
        }
        revert MethodNotFound();
    }
}
