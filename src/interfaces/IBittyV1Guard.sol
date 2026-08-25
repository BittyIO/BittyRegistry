// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

error NotRegistered();
error Deprecated();

/**
 * @title Manage the registered assets and protocols (v1).
 * @dev Manage the registered assets and protocols by Bitty.
 */
interface IBittyV1Guard {
    /**
     * @notice Add a registered asset to Bitty.
     * @dev Add a registered asset to Bitty.
     * @param assetAddresses The addresses of the assets.
     */
    function addAssets(address[] memory assetAddresses) external;

    /**
     * @notice Remove a registered asset from Bitty.
     * @dev Remove a registered asset from Bitty.
     *      A removed asset can only be sold instead of being bought.
     * @param assetAddresses The addresses of the assets.
     */
    function removeAssets(address[] memory assetAddresses) external;

    /**
     * @notice Check if an asset is registered.
     * @dev Check if an asset is registered.
     * @param assetAddress The address of the asset.
     * @return bool True if the asset is registered, false otherwise.
     */
    function isAssetRegistered(address assetAddress) external view returns (bool);

    /**
     * @notice Add a stable coin to Bitty.
     * @dev Add a stable coin to Bitty.
     * @param stableCoinAddresses The addresses of the stable coins.
     */
    function addStableCoins(address[] memory stableCoinAddresses) external;

    /**
     * @notice Remove a stable coin from Bitty.
     * @dev Remove a stable coin from Bitty.
     *      A removed stable coin can only be sold, can not be bought anymore.
     * @param stableCoinAddresses The addresses of the stable coins.
     */
    function removeStableCoins(address[] memory stableCoinAddresses) external;

    /**
     * @notice Check if a stable coin is registered.
     * @dev Check if a stable coin is registered.
     * @param stableCoinAddress The address of the stable coin.
     * @return bool True if the stable coin is registered, false otherwise.
     */
    function isStableCoinRegistered(address stableCoinAddress) external view returns (bool);

    /**
     * @notice Register protocols. Each one's category comes from the protocol itself.
     * @dev Nothing here names a category. A protocol declares one of the four Bitty protocol
     *      interfaces via ERC-165, and this reads that declaration rather than taking the caller's
     *      word for it — so a category cannot be misdeclared at the registry, only by the protocol
     *      about itself, and a protocol that declares nothing recognisable cannot be listed at all.
     *
     *      Exactly one category is required. One declaring two would be admissible by the manager of
     *      either and usable as the other, which routes around the split between manager roles.
     *
     *      The caller must hold the manager role for the category each protocol declares, checked per
     *      protocol — so a batch spanning categories needs a caller holding all of them.
     *
     *      Re-registering a deprecated protocol clears its deprecation.
     * @param protocolAddresses The addresses of the protocols. Zero addresses are skipped.
     */
    function addProtocols(address[] memory protocolAddresses) external;

    /**
     * @notice Deprecate protocols.
     * @dev A deprecated protocol is only good for getting OUT — existing positions can still be
     *      withdrawn or unstaked, but nothing new may enter it. It leaves the registered set and is
     *      remembered as deprecated, which is why this is not the same as removal.
     *
     *      Authority comes from the category recorded at registration, not a fresh probe of the
     *      protocol: this is the lever you reach for when a protocol has misbehaved, and it must not
     *      stop working because that protocol stopped answering.
     * @param protocolAddresses The addresses of the protocols. Ones that were never registered are
     *        skipped rather than marked, so this is not a way to record an unknown address.
     */
    function deprecateProtocols(address[] memory protocolAddresses) external;

    /**
     * @notice Is this protocol registered and not deprecated?
     * @dev Says nothing about WHICH category — read {protocolCategory} for that. The two questions
     *      are separate because callers ask them separately: the vault checks that a protocol is
     *      permitted at all, then that it is the kind of protocol this particular call needs.
     * @param protocolAddress The address of the protocol.
     * @return bool True if registered.
     */
    function isProtocolRegistered(address protocolAddress) external view returns (bool);

    /**
     * @notice Is this protocol deprecated?
     * @dev Deliberately separate from {isProtocolRegistered}: the two directions differ. Entering a
     *      deprecated protocol should fail, while exiting one must keep working, or positions would
     *      be stranded. Callers layer the rule they need rather than getting one baked in here.
     * @param protocolAddress The address of the protocol.
     * @return bool True if deprecated.
     */
    function isProtocolDeprecated(address protocolAddress) external view returns (bool);

    /**
     * @notice The category a protocol declared when it was registered.
     * @dev The ERC-165 id of one of the four Bitty protocol interfaces, or 0 for an address that was
     *      never registered. Recorded at registration rather than re-derived, so reading it costs a
     *      storage load instead of an ERC-165 probe.
     * @param protocolAddress The address of the protocol.
     * @return bytes4 The category interface id, or 0.
     */
    function protocolCategory(address protocolAddress) external view returns (bytes4);

    /**
     * @notice Every ACTIVE protocol — registered and not deprecated, across all categories.
     * @dev Deprecated entries are absent because a user should not be offered a protocol they can
     *      only exit; {isProtocolDeprecated} still answers for a position someone already holds.
     *      Callers wanting one category filter on {protocolCategory}.
     * @return addresses The active protocols.
     */
    function getProtocols() external view returns (address[] memory addresses);

    /**
     * @notice Get the registered assets.
     * @dev Get the registered assets.
     * @return addresses The addresses of the registered assets.
     */
    function getAssets() external view returns (address[] memory addresses);

    /**
     * @notice Get the registered stable coins.
     * @dev Get the registered stable coins.
     * @return addresses The addresses of the registered stable coins.
     */
    function getStableCoins() external view returns (address[] memory addresses);
}
