// SPDX-License-Identifier: MIT
// solhint-disable use-natspec
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SLIOracle} from "../src/SLIOracle.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SLIOracleTest is Test {
    SLIOracle public sliOracle;
    address public oracle = address(0x123);

    function setUp() public {
        SLIOracle impl = new SLIOracle();
        bytes memory initData = abi.encodeWithSignature("initialize(address,address)", address(this), oracle);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        sliOracle = SLIOracle(address(proxy));
    }

    function testIsAdminSet() public view {
        bytes32 adminRole = sliOracle.DEFAULT_ADMIN_ROLE();
        assertTrue(sliOracle.hasRole(adminRole, address(this)));
    }

    function testAuthorizeUpgradeRevert() public {
        address newImpl = address(new SLIOracle());
        address unauthorized = vm.addr(1);
        bytes32 upgraderRole = sliOracle.UPGRADER_ROLE();
        // solhint-disable-next-line gas-small-strings
        bytes4 sel = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));

        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(sel, unauthorized, upgraderRole));
        sliOracle.upgradeToAndCall(newImpl, "");
    }

    function testIsOracleRoleSet() public view {
        bytes32 oracleRole = sliOracle.ORACLE_ROLE();
        assertTrue(sliOracle.hasRole(oracleRole, oracle));
    }

    function testSLIAttestationEvent() public {
        address provider = address(0x123);
        SLIOracle.SLIAttestation memory slis = SLIOracle.SLIAttestation({
            lastUpdate: block.number, availability: 1, latency: 1, indexing: 1, retention: 1, bandwidth: 1, stability: 1
        });

        vm.expectEmit(true, true, false, false);
        emit SLIOracle.SLIAttestationUpdate(provider, slis);

        vm.prank(oracle);
        sliOracle.setSLI(provider, slis);

        (
            uint256 storedLastUpdate,
            uint16 storedAvailability,
            uint16 storedLatency,
            uint16 storedIndexing,
            uint16 storedRetention,
            uint16 storedBandwidth,
            uint16 storedStability
        ) = sliOracle.attestations(provider);

        // Compare lastUpdate is set correctly in storage
        assertEq(storedLastUpdate, slis.lastUpdate);
        // Compare that last update is set to current block number
        assertEq(storedLastUpdate, block.number);
        assertEq(storedAvailability, slis.availability);
        assertEq(storedLatency, slis.latency);
        assertEq(storedIndexing, slis.indexing);
        assertEq(storedRetention, slis.retention);
        assertEq(storedBandwidth, slis.bandwidth);
        assertEq(storedStability, slis.stability);
    }
}
