// solhint-disable use-natspec
// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;
import {FilAddresses} from "filecoin-solidity/v0.8/utils/FilAddresses.sol";

contract ActorAddressMock {
    error MethodNotFound();

    receive() external payable {}

    // solhint-disable-next-line no-complex-fallback
    fallback(bytes calldata data) external payable returns (bytes memory) {
        (uint256 methodNum,,,,, bytes memory actorAddr) =
            abi.decode(data, (uint64, uint256, uint64, uint64, bytes, bytes));

        if (methodNum == 0 && keccak256(actorAddr) == keccak256(FilAddresses.fromActorID(10000).data)) {
            return abi.encode(0, 0x00, "");
        }
        if (methodNum == 0 && keccak256(actorAddr) == keccak256(FilAddresses.fromActorID(20000).data)) {
            return abi.encode(1, 0x00, "");
        }
        if (methodNum == 0 && keccak256(actorAddr) == keccak256(FilAddresses.fromActorID(30000).data)) {
            return abi.encode(0, 0x51, hex"");
        }

        revert MethodNotFound();
    }
}
