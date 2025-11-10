// solhint-disable use-natspec
// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

contract ResolveAddressPrecompileMock {
    uint64 public id;

    function setId(uint64 id_) external {
        id = id_;
    }

    fallback(bytes calldata) external returns (bytes memory) {
        return abi.encode(id);
    }
}
