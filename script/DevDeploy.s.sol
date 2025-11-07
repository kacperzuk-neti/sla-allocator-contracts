// SPDX-License-Identifier: UNLICENSED
// solhint-disable no-console
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {BeneficiaryFactory} from "../src/BeneficiaryFactory.sol";
import {Beneficiary} from "../src/Beneficiary.sol";
import {SLAAllocator} from "../src/SLAAllocator.sol";
import {SLARegistry} from "../src/SLARegistry.sol";
import {SLIOracle} from "../src/SLIOracle.sol";
import {Client} from "../src/Client.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DevDeploy is Script {
    function deployOracle() internal returns (SLIOracle) {
        address sliOracleImpl = address(new SLIOracle());
        return SLIOracle(
            address(new ERC1967Proxy(sliOracleImpl, abi.encodeCall(SLIOracle.initialize, (msg.sender, msg.sender))))
        );
    }

    function deployBeneficiaryFactory(SLAAllocator slaAllocator) internal returns (BeneficiaryFactory) {
        address beneficiaryImpl = address(new Beneficiary());
        address beneficiaryFactoryImpl = address(new BeneficiaryFactory());
        return BeneficiaryFactory(
            address(
                new ERC1967Proxy(
                    beneficiaryFactoryImpl,
                    abi.encodeCall(BeneficiaryFactory.initialize, (msg.sender, beneficiaryImpl, slaAllocator))
                )
            )
        );
    }

    function deploySLAAllocator() internal returns (SLAAllocator) {
        address slaAllocatorImpl = address(new SLAAllocator());
        return SLAAllocator(
            address(
                new ERC1967Proxy(slaAllocatorImpl, abi.encodeCall(SLAAllocator.initialize, (msg.sender, msg.sender)))
            )
        );
    }

    function deploySLARegistry(SLIOracle sliOracle) internal returns (SLARegistry) {
        address slaRegistryImpl = address(new SLARegistry());
        return SLARegistry(
            address(
                new ERC1967Proxy(
                    address(slaRegistryImpl), abi.encodeCall(SLARegistry.initialize, (msg.sender, sliOracle))
                )
            )
        );
    }

    function deployClient(SLAAllocator slaAllocator) internal returns (Client) {
        address clientImpl = address(new Client());
        return Client(
            address(
                new ERC1967Proxy(
                    address(clientImpl), abi.encodeCall(Client.initialize, (msg.sender, address(slaAllocator)))
                )
            )
        );
    }

    function run() public {
        vm.startBroadcast();

        SLAAllocator slaAllocator = deploySLAAllocator();

        Client client = deployClient(slaAllocator);

        BeneficiaryFactory beneficiaryFactory = deployBeneficiaryFactory(slaAllocator);

        SLIOracle sliOracle = deployOracle();

        SLARegistry slaRegistry = deploySLARegistry(sliOracle);

        slaAllocator.initialize2(client, beneficiaryFactory);

        console.log("BeneficiaryFactory: ", address(beneficiaryFactory));
        console.log("SLAAllocator: ", address(slaAllocator));
        console.log("SLARegistry: ", address(slaRegistry));
        console.log("SLIOracle: ", address(sliOracle));
        console.log("ClientSC: ", address(client));

        vm.stopBroadcast();
    }
}
