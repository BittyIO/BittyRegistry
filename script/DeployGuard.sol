// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.34;

import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {console2} from "forge-std/console2.sol";
import {BittyV1Guard} from "../src/BittyV1Guard.sol";
import {BittyV1GuardBootstrap} from "../src/BittyV1GuardBootstrap.sol";
import {DeployScript} from "./BaseDeploy.sol";

interface ImmutableCreate2Factory {
    function safeCreate2(bytes32 salt, bytes calldata initCode) external payable returns (address deploymentAddress);
}

/**
 * @title DeployGuard
 * @notice The one guard-deploying step, shared by the per-chain scripts.
 *
 * @dev The chain scripts differ only in WHICH assets and protocols they register - the deploy itself
 *      is identical everywhere, and must stay that way: the salt and the bootstrap are what put the
 *      guard at the same address on every chain, so a chain holding its own copy of either is a bug
 *      waiting to happen rather than a chain-specific choice. Keeping them here means a chain script
 *      states its registry and nothing else.
 *
 *      Every step is RE-RUNNABLE: create, upgrade and initialize are each skipped once done, so
 *      finishing an interrupted deploy is just running it again, and re-running a finished one
 *      reports that there is nothing left to do rather than reverting.
 */
abstract contract DeployGuard is DeployScript {
    ImmutableCreate2Factory internal constant IMMUTABLE_CREATE2 =
        ImmutableCreate2Factory(0x0000000000FFe8B47B3e2130213B802212439497);

    bytes32 internal constant GUARD_SALT = 0x12ee2de7bf086388b1d560eb95e7191edfab98239abf831f3b8910000e44b9e2;

    address[] private _assets;
    uint8[] private _assetCategories;
    address[] private _protocols;
    uint8[] private _protocolCategories;

    function _asset(string memory key, uint8 category) internal {
        _assets.push(getAddress(key));
        _assetCategories.push(category);
    }

    function _protocol(string memory key, uint8 category) internal {
        _protocols.push(getAddress(key));
        _protocolCategories.push(category);
    }

    function _deployGuard() internal {
        address guardImpl = deployAtSaltZero(type(BittyV1Guard).creationCode);

        address bootstrap = deployAtSaltZero(type(BittyV1GuardBootstrap).creationCode);
        bytes memory initCode = abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(bootstrap, bytes("")));
        console2.log("proxy initCode hash (mine the salt against this):");
        console2.logBytes32(keccak256(initCode));

        address guard = create2Address(address(IMMUTABLE_CREATE2), GUARD_SALT, initCode);
        if (guard.code.length == 0) IMMUTABLE_CREATE2.safeCreate2(GUARD_SALT, initCode);

        if (address(uint160(uint256(vm.load(guard, ERC1967Utils.IMPLEMENTATION_SLOT)))) != guardImpl) {
            UUPSUpgradeable(guard).upgradeToAndCall(guardImpl, "");
            console2.log("guard moved to implementation", guardImpl);
        }
        if (BittyV1Guard(guard).defaultAdmin() == address(0)) {
            BittyV1Guard(guard).initialize(_assets, _assetCategories, _protocols, _protocolCategories);
            console2.log("guard initialized with assets/protocols:", _assets.length, _protocols.length);
        }

        console2.log("guard implementation at ", guardImpl);
        console2.log("BittyV1Guard deployed at", guard);
        saveAddress("BITTY_GUARD", guard);
    }
}
