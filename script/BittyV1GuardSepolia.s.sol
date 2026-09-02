// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.34;

import {
    ASSET_STABLE_COIN,
    ASSET_CRYPTO,
    PROTOCOL_LENDING,
    PROTOCOL_STAKING,
    PROTOCOL_AMM,
    PROTOCOL_INTENT
} from "../src/interfaces/IBittyV1Guard.sol";
import {DeployGuard} from "./DeployGuard.sol";

contract Deploy is DeployGuard {
    function deploy() public override {
        _asset("WETH", ASSET_CRYPTO);
        _asset("WETH_AAVE", ASSET_CRYPTO);
        _asset("WETH_UNI", ASSET_CRYPTO);
        _asset("WBTC", ASSET_CRYPTO);
        _asset("USDT", ASSET_STABLE_COIN);
        _asset("USDC", ASSET_STABLE_COIN);

        _protocol("AAVE", PROTOCOL_LENDING);
        _protocol("UNI", PROTOCOL_AMM);
        _protocol("COW", PROTOCOL_INTENT);
        _protocol("LIDO", PROTOCOL_STAKING);

        _deployGuard();
    }
}
