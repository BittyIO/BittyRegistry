// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

error NotDeployer();
error LengthMismatch();
error NotRegisteredProtocol(address protocolAddress);
error CategoryZero();
error NotRegisteredProtocolCategory(uint8 category);

/**
 * @title Manage the registered assets and protocols (v1).
 * @dev Manage the registered assets and protocols by Bitty.
 */
interface IBittyV1Guard {
    event AssetAdded(address indexed assetAddress, uint8 indexed category);
    event AssetRemoved(address indexed assetAddress);
    event ProtocolAdded(address indexed protocolAddress, uint8 indexed category);
    event ProtocolDeprecated(address indexed protocolAddress);

    /**
     * @notice Add registered assets to Bitty.
     * @dev Each asset carries a category, the same way a protocol does. The guard does not interpret
     *      the value beyond rejecting zero; what each number means is a convention shared with the
     *      consumers that read it back from {assetCategory}.
     * @param assetAddresses The addresses of the assets.
     * @param categories The category of each asset, positionally matched.
     */
    function addAssets(address[] memory assetAddresses, uint8[] memory categories) external;

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
     * @notice The category an asset was registered under.
     * @param assetAddress The address of the asset.
     * @return uint8 The category, or 0 for an address that was never registered.
     */
    function assetCategory(address assetAddress) external view returns (uint8);

    /**
     * @notice Add protocols to Bitty.
     * @dev Add protocols to Bitty.
     * @param protocolAddresses The addresses of the protocols.
     */
    function addProtocols(address[] memory protocolAddresses, uint8[] memory categories) external;

    /**
     * @notice Deprecate protocols from Bitty.
     * @dev Deprecate protocols from Bitty.
     * @param protocolAddresses The addresses of the protocols.
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
     * @return uint8 The category interface id, or 0.
     */
    function protocolCategory(address protocolAddress) external view returns (uint8);
}
