// solhint-disable use-natspec
// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

contract ResolveAddressPrecompileFailingMock {
    fallback(bytes calldata data) external payable returns (bytes memory) {
        return abi.encode(data);
    }
}
