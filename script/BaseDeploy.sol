// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Script} from "forge-std/Script.sol";
import {Config} from "forge-std/Config.sol";
import {console2} from "forge-std/console2.sol";

abstract contract DeployScript is Script, Config {
    string[] private _savedKeys;
    address[] private _savedValues;

    function deploy(string memory chainName) public {
        console2.log("Forking chain", chainName);
        vm.createSelectFork(chainName);
        string memory configPath = string.concat("./deployments/", chainName, ".toml");
        _loadConfig(configPath, true);
        vm.startBroadcast();
        deploy();
        vm.stopBroadcast();
        _flushSavedAddresses();
    }

    function run() public {
        deploy(vm.getChain(block.chainid).name);
    }

    address internal constant SIMPLE_CREATE2 = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /**
     * @dev CREATE2 through the standard deployer at salt 0: the same address on every chain for the
     *      same bytecode, and idempotent - a re-run finds the code already there and returns it rather
     *      than reverting, so a half-finished deploy can simply be run again.
     */
    function deployAtSaltZero(bytes memory code) internal returns (address deployed) {
        deployed = create2Address(SIMPLE_CREATE2, bytes32(0), code);
        if (deployed.code.length > 0) return deployed;
        (bool ok, bytes memory ret) = SIMPLE_CREATE2.call(abi.encodePacked(bytes32(0), code));
        require(ok && ret.length == 20 && address(bytes20(ret)) == deployed, "CREATE2 at salt 0 failed");
    }

    function create2Address(address deployer, bytes32 salt, bytes memory code) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, keccak256(code))))));
    }

    function getAddress(string memory key) public view returns (address) {
        address value = config.get(key).toAddress();
        require(value != address(0), string.concat("Address for key ", key, " not found"));
        return value;
    }

    /**
     * @dev Buffered rather than written straight through, because {Config-set} is an external call to
     *      StdConfig - a helper forge-std deploys INSIDE the simulation to hold the parsed TOML, at an
     *      address that exists nowhere on the target chain.
     *
     *      Inside the broadcast window forge records every such call as a transaction to be sent, so a
     *      real broadcast emits one pointless ~21k-gas send per key, to an address with no code, each
     *      preceded by "Script contains a transaction to 0x... which does not contain any code". They
     *      do nothing on-chain and they bury the real deployment transactions in the run log.
     *
     *      Pushing to this contract's own storage is an internal write, so nothing is recorded; the
     *      buffer is flushed once the broadcast has closed and writes exactly the same TOML.
     */
    function saveAddress(string memory key, address value) public {
        require(value != address(0), string.concat("Address for key ", key, " is 0x0"));
        _savedKeys.push(key);
        _savedValues.push(value);
    }

    /// @dev Runs after {vm-stopBroadcast}, so these calls are plain simulation and emit no transaction.
    function _flushSavedAddresses() private {
        for (uint256 i = 0; i < _savedKeys.length; i++) {
            config.set(_savedKeys[i], _savedValues[i]);
        }
        delete _savedKeys;
        delete _savedValues;
    }

    function deploy() public virtual {}
}
