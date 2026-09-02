// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.34;

import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
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

    bytes32 salt = 0x12ee2de7bf086388b1d560eb95e7191edfab982397dc7287bca0000000122737;

    function deploy() public override {
        // Deterministic and chain-independent; the vanity salt is spent on the PROXY below, which is
        // the address BITTY_GUARD names and every vault compiles in.
        address guardImpl = _deployImplementation();

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
        address[] memory protocols = new address[](4);
        uint8[] memory protocolCategories = new uint8[](4);
        protocols[0] = getAddress("AAVE");
        protocolCategories[0] = 1;
        protocols[1] = getAddress("UNI");
        protocolCategories[1] = 3;
        protocols[2] = getAddress("COW");
        protocolCategories[2] = 4;
        protocols[3] = getAddress("LIDO");
        protocolCategories[3] = 2;

        bytes memory initCode = abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(guardImpl, bytes("")));
        address predicted = factory.findCreate2Address(salt, initCode);
        BittyV1Guard bittyGuard =
            BittyV1Guard(predicted.code.length > 0 ? predicted : factory.safeCreate2(salt, initCode));
        if (bittyGuard.defaultAdmin() == address(0)) {
            bittyGuard.initialize(assets, assetCategories, protocols, protocolCategories);
        }

        console2.log("guard implementation at ", guardImpl);
        console2.log("proxy initCode hash (mine the salt against this):");
        console2.logBytes32(keccak256(initCode));

        console2.log("BittyV1Guard deployed at", address(bittyGuard));

        saveAddress("BITTY_GUARD", address(bittyGuard));
    }

    address constant SIMPLE_CREATE2 = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function _deployImplementation() private returns (address impl) {
        bytes memory code = type(BittyV1Guard).creationCode;
        impl = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), SIMPLE_CREATE2, bytes32(0), keccak256(code)))))
        );
        if (impl.code.length > 0) return impl;
        (bool ok, bytes memory ret) = SIMPLE_CREATE2.call(abi.encodePacked(bytes32(0), code));
        require(ok && ret.length == 20 && address(bytes20(ret)) == impl, "guard impl CREATE2 failed");
    }
}
