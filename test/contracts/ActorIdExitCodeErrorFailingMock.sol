// solhint-disable use-natspec
// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

contract ActorIdExitCodeErrorFailingMock {
    receive() external payable {}

    // solhint-disable-next-line no-complex-fallback
    fallback(bytes calldata) external payable returns (bytes memory) {
        // Exit Code Error
        return abi.encode(1, 0x00, "");
    }
}
