// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.34;

import "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {BittyV1Guard} from "../src/BittyV1Guard.sol";
import {DeployScript} from "./BaseDeploy.sol";

interface ImmutableCreate2Factory {
    function safeCreate2(bytes32 salt, bytes calldata initCode) external payable returns (address deploymentAddress);
    function findCreate2Address(bytes32 salt, bytes calldata initCode) external view returns (address deploymentAddress);
    function findCreate2AddressViaHash(bytes32 salt, bytes32 initCodeHash)
        external
        view
        returns (address deploymentAddress);
}

contract Deploy is DeployScript {
    ImmutableCreate2Factory immutable factory = ImmutableCreate2Factory(0x0000000000FFe8B47B3e2130213B802212439497);

    bytes32 salt = 0x12ee2de7bf086388b1d560eb95e7191edfab98237d7f2344723a84008d3fddb0;

    function deploy() public override {
        bytes memory initCode = type(BittyV1Guard).creationCode;

        address bittyGuardAddress = factory.safeCreate2(salt, initCode);
        BittyV1Guard bittyGuard = BittyV1Guard(bittyGuardAddress);

        address[] memory assets = new address[](3);
        assets[0] = getAddress("WETH");
        assets[1] = getAddress("WBTC");
        assets[2] = getAddress("CRCLON");

        address[] memory stableCoins = new address[](2);
        stableCoins[0] = getAddress("USDT");
        stableCoins[1] = getAddress("USDC");

        bittyGuard.initialize(
            assets, stableCoins, new address[](0), new address[](0), new address[](0), new address[](0)
        );

        console2.log("BittyV1Guard deployed at", address(bittyGuard));

        saveAddress("BITTY_GUARD", address(bittyGuard));
    }
}
