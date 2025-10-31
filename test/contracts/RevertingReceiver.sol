// solhint-disable use-natspec
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract RevertingReceiver {
    error NoFunds();

    receive() external payable {
        revert NoFunds();
    }
}
