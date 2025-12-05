// solhint-disable use-natspec
// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

contract ResolveAddressPrecompileMock {
    mapping(address client => uint64 id) public addressToId;
    mapping(bytes32 filAddressData => uint64 id) public filAddressToId;

    function setId(address addr, uint64 id) external {
        addressToId[addr] = id;
    }

    function setAddress(bytes memory filAddressData, uint64 id) external {
        filAddressToId[keccak256(filAddressData)] = id;
    }

    // solhint-disable-next-line no-complex-fallback
    fallback(bytes calldata data) external returns (bytes memory) {
        // First check if it's a FilAddress (by checking the mapping)
        bytes32 dataHash = keccak256(data);
        uint64 id = filAddressToId[dataHash];

        // If not found in FilAddress mapping, try parsing as address
        if (id == 0) {
            address clientAddress;
            // solhint-disable-next-line no-inline-assembly
            assembly {
                let tmp := calldataload(add(data.offset, 2))
                clientAddress := shr(96, tmp)
            }
            id = addressToId[clientAddress];
        }

        return abi.encode(id);
    }
}
