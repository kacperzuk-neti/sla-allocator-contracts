// solhint-disable use-natspec
// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

contract BuildInActorForTransferFunctionMock {
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
        if (target == 7 && methodNum == 80475954) {
            // datacap transfer failed
            return abi.encode(1, 0x00, "");
        }
        revert MethodNotFound();
    }
}
