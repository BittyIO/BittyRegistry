// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.34;

import {ASSET_STABLE_COIN, ASSET_CRYPTO} from "../src/interfaces/IBittyV1Guard.sol";
import "forge-std/console.sol";
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

    bytes32 salt = 0x12ee2de7bf086388b1d560eb95e7191edfab98231b108a06257b200004f087f8;

    function deploy() public override {
        bytes memory initCode = type(BittyV1Guard).creationCode;

        address bittyGuardAddress = factory.safeCreate2(salt, initCode);
        BittyV1Guard bittyGuard = BittyV1Guard(bittyGuardAddress);

        address[] memory assets = new address[](6);
        uint8[] memory assetCategories = new uint8[](6);
        assets[0] = getAddress("WETH");
        assetCategories[0] = ASSET_CRYPTO;
        assets[1] = getAddress("WETH_AAVE");
        assetCategories[1] = ASSET_CRYPTO;
        assets[2] = getAddress("WETH_UNI");
        assetCategories[2] = ASSET_CRYPTO;
        assets[3] = getAddress("WBTC");
        assetCategories[3] = ASSET_CRYPTO;
        assets[4] = getAddress("USDT");
        assetCategories[4] = ASSET_STABLE_COIN;
        assets[5] = getAddress("USDC");
        assetCategories[5] = ASSET_STABLE_COIN;

        bittyGuard.initialize(assets, assetCategories, new address[](0), new uint8[](0));

        console2.log("BittyV1Guard deployed at", address(bittyGuard));

        saveAddress("BITTY_GUARD", address(bittyGuard));
    }
}
