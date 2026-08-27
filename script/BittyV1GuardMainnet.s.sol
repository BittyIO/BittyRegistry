// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.34;

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

    uint8 internal constant STABLE_COIN_CATEGORY = 1;
    uint8 internal constant CRYPTO_CATEGORY = 2;

    bytes32 salt = 0x12ee2de7bf086388b1d560eb95e7191edfab9823addba4eeda01a000b0223d82;

    function deploy() public override {
        bytes memory initCode = type(BittyV1Guard).creationCode;

        address bittyGuardAddress = factory.safeCreate2(salt, initCode);
        BittyV1Guard bittyGuard = BittyV1Guard(bittyGuardAddress);

        address[] memory assets = new address[](5);
        uint8[] memory assetCategories = new uint8[](5);
        assets[0] = getAddress("WETH");
        assetCategories[0] = CRYPTO_CATEGORY;
        assets[1] = getAddress("WBTC");
        assetCategories[1] = CRYPTO_CATEGORY;
        assets[2] = getAddress("CRCLON");
        assetCategories[2] = CRYPTO_CATEGORY;
        assets[3] = getAddress("USDT");
        assetCategories[3] = STABLE_COIN_CATEGORY;
        assets[4] = getAddress("USDC");
        assetCategories[4] = STABLE_COIN_CATEGORY;

        bittyGuard.initialize(assets, assetCategories, new address[](0), new uint8[](0));

        console2.log("BittyV1Guard deployed at", address(bittyGuard));

        saveAddress("BITTY_GUARD", address(bittyGuard));
    }
}
