// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {NotDeployer} from "./interfaces/IBittyV1Guard.sol";

/**
 * @title BittyV1GuardBootstrap
 * @notice The implementation the guard proxy is BORN with, and leaves in the same transaction.
 *
 *         The guard's address is CREATE2 over the proxy's init code, and that init code embeds the
 *         implementation. Pointing the proxy straight at the current build therefore moved the guard's
 *         address every time the guard itself changed - which is the one address that must never move,
 *         because every vault compiles it in as a constant. It also made a new chain unreproducible:
 *         matching an existing chain's address meant rebuilding the exact implementation that chain's
 *         proxy was born with, from the commit that produced it, forever.
 *
 *         Being born on a CONSTANT implementation takes the build out of the hash. The proxy's init
 *         code is now the same on every chain at every version, so any future chain reaches the same
 *         guard address by running the deploy script, and the guard can be upgraded any number of
 *         times without its address moving again.
 *
 *         The same reasoning as BittyV1VaultBootstrap in the vault repo, one layer up: that one keeps
 *         each vault's address independent of the vault build, this one keeps the guard's address
 *         independent of the guard build.
 */
contract BittyV1GuardBootstrap is UUPSUpgradeable {
    address private constant DEPLOYER = 0x12EE2de7BF086388B1D560eb95e7191Edfab9823;

    /**
     * @dev The deployer, by tx.origin, for the same reason the guard's own initialize uses it: the
     *      proxy address is reproducible on every chain, so anyone could otherwise race the deploy on
     *      a chain Bitty has not reached yet and hand the guard an implementation of their own. The
     *      real guard's DEFAULT_ADMIN_ROLE takes over the moment this contract stops being the
     *      implementation, which is one call later.
     */
    function _authorizeUpgrade(address) internal view override {
        if (tx.origin != DEPLOYER) revert NotDeployer();
    }
}
