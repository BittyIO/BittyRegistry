// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "lib/forge-std/src/Test.sol";
import {BittyV1Guard} from "../../src/BittyV1Guard.sol";

contract ImplRegistryTest is Test {
    BittyV1Guard guard;
    address deployAdmin = 0x12EE2de7BF086388B1D560eb95e7191Edfab9823;
    address implManager = makeAddr("implManager"); // stands in for the governance TimelockController
    address impl = makeAddr("impl");

    function setUp() public {
        vm.prank(deployAdmin, deployAdmin);
        guard = new BittyV1Guard();
        bytes32 implRole = guard.IMPLEMENTATION_MANAGER_ROLE();
        vm.prank(deployAdmin);
        guard.grantRole(implRole, implManager);
    }

    function _one(address a) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }

    function test_registerThenUnregister() public {
        assertFalse(guard.isImplementationRegistered(impl), "unknown impl");

        vm.prank(implManager);
        guard.registerImplementations(_one(impl));
        assertTrue(guard.isImplementationRegistered(impl), "registered");

        vm.prank(implManager);
        guard.unregisterImplementations(_one(impl));
        assertFalse(guard.isImplementationRegistered(impl), "unregistered");
    }

    function test_strangerCannotRegister() public {
        vm.prank(makeAddr("stranger"));
        vm.expectRevert();
        guard.registerImplementations(_one(impl));
    }

    function test_protocolManagerCannotRegister() public {
        address protocolMgr = makeAddr("protocolMgr");
        bytes32 protocolRole = guard.PROTOCOL_MANAGER_ROLE();
        vm.prank(deployAdmin);
        guard.grantRole(protocolRole, protocolMgr);

        assertTrue(guard.hasRole(protocolRole, protocolMgr), "is protocol manager");
        assertFalse(guard.hasRole(guard.IMPLEMENTATION_MANAGER_ROLE(), protocolMgr), "is not impl manager");
        vm.prank(protocolMgr);
        vm.expectRevert();
        guard.registerImplementations(_one(impl));
    }

    function test_deployerCanRegisterAtLaunch() public {
        assertTrue(guard.hasRole(guard.IMPLEMENTATION_MANAGER_ROLE(), deployAdmin), "deployer bootstrapped");
        vm.prank(deployAdmin);
        guard.registerImplementations(_one(impl));
        assertTrue(guard.isImplementationRegistered(impl), "registered by deployer");
    }
}
