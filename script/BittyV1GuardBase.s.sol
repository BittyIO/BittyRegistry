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

/**
 * @notice Base (chain 8453). Same contract, same salt, same deployer as the other chains, so the
 *         guard lands on the SAME address here that it holds elsewhere — the guard takes no
 *         constructor arguments, so its init code is bytecode alone and CREATE2 is chain-independent.
 *         ImmutableCreate2Factory is deployed at the usual address on Base, and its containsCaller
 *         check means this DEPLOYER-prefixed salt is unusable by anyone else.
 *
 *         The registry differs from mainnet's because Base's tokens do. BTC here is cbBTC, NOT the
 *         bridged WBTC: that token exists on Base (0x0555E30d...) but held ~64 BTC against cbBTC's
 *         ~44,700, so registering it would offer vaults a market too thin to fill them. USDbC (the
 *         older bridged USDC) is left out for the same reason — new vaults should hold native USDC.
 */
contract Deploy is DeployScript {
    ImmutableCreate2Factory immutable factory = ImmutableCreate2Factory(0x0000000000FFe8B47B3e2130213B802212439497);

    bytes32 salt = 0x12ee2de7bf086388b1d560eb95e7191edfab98236fbb93574cf1e0001f15ca91;

    function deploy() public override {
        bytes memory initCode = type(BittyV1Guard).creationCode;

        address bittyGuardAddress = factory.safeCreate2(salt, initCode);
        BittyV1Guard bittyGuard = BittyV1Guard(bittyGuardAddress);

        address[] memory assets = new address[](2);
        assets[0] = getAddress("WETH");
        assets[1] = getAddress("CBBTC");

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
