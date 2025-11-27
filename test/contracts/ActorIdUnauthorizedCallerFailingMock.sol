// solhint-disable use-natspec
// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

// solhint-disable-next-line max-states-count
contract ActorIdUnauthorizedCallerFailingMock {
    error MethodNotFound();

    // solhint-disable-next-line no-complex-fallback
    fallback(bytes calldata data) external payable returns (bytes memory) {
        (uint256 methodNum,,,,, uint64 target) = abi.decode(data, (uint64, uint256, uint64, uint64, bytes, uint64));
        if (target == 321 && methodNum == 3275365574) {
            return abi.encode(0, 0x51, hex"824400A58B0140");
        }
        revert MethodNotFound();
    }
}
