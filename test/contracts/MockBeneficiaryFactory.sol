// SPDX-License-Identifier: MIT
// solhint-disable use-natspec

pragma solidity 0.8.25;

import {BeneficiaryFactory} from "../../src/BeneficiaryFactory.sol";
import {CommonTypes} from "filecoin-solidity/v0.8/types/CommonTypes.sol";

contract MockBeneficiaryFactory is BeneficiaryFactory {
    function setInstance(CommonTypes.FilActorId provider, address contractAddress) public {
        instances[provider] = contractAddress;
    }
}
