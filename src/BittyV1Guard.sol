// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {
    AccessControlDefaultAdminRules
} from "openzeppelin-contracts/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {IBittyV1Guard} from "./interfaces/IBittyV1Guard.sol";
import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {ERC165Checker} from "openzeppelin-contracts/contracts/utils/introspection/ERC165Checker.sol";

/**
 * @title BittyV1Guard
 * @notice Guard of allowed assets and protocols for Bitty.
 * @dev Mutations are gated by {AccessControl} roles. `DEFAULT_ADMIN_ROLE` is assigned to `tx.origin`
 *      at deploy (not encoded in CREATE2 init code, so init code hash is stable for salt mining).
 *      Admin transfers use a 2-step flow with {DEFAULT_ADMIN_TRANSFER_DELAY}.
 *      Each category has its own manager role so operations can be split across addresses.
 */
contract BittyV1Guard is IBittyV1Guard, Initializable, AccessControlDefaultAdminRules {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Delay before a pending `DEFAULT_ADMIN_ROLE` transfer can be accepted.
    uint48 internal constant DEFAULT_ADMIN_TRANSFER_DELAY = 7 days;

    /// @notice Role allowed to add/remove assets.
    bytes32 public constant ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");
    /// @notice Role allowed to add/remove stable coins.
    bytes32 public constant STABLE_COIN_MANAGER_ROLE = keccak256("STABLE_COIN_MANAGER_ROLE");
    /// @notice Role allowed to add/deprecate lending protocols.
    bytes32 public constant LENDING_MANAGER_ROLE = keccak256("LENDING_MANAGER_ROLE");
    /// @notice Role allowed to add/deprecate staking protocols.
    bytes32 public constant STAKING_MANAGER_ROLE = keccak256("STAKING_MANAGER_ROLE");
    /// @notice Role allowed to add/deprecate AMM protocols.
    bytes32 public constant AMM_MANAGER_ROLE = keccak256("AMM_MANAGER_ROLE");
    /// @notice Role allowed to add/deprecate intent protocols.
    bytes32 public constant INTENT_MANAGER_ROLE = keccak256("INTENT_MANAGER_ROLE");

    /**
     * @notice ERC-165 ids for the four protocol categories, verified once here at registration.
     * @dev The vault no longer keeps a set per category — it asks a protocol what it is and checks
     *      that answer against these same ids. That only holds if a protocol's self-declared category
     *      is true, so this is where it gets established: a protocol is admitted to a category only
     *      if it declares the matching interface.
     *
     *      Hard-coded rather than derived via `type(I…).interfaceId` because the guard deliberately
     *      does not depend on protocol-store — protocol-store already declares an {IBittyV1Guard},
     *      so a dependency back would close a cycle between the two repos. The authoritative values
     *      are pinned by `InterfaceIds.t.sol` in protocol-store; change these only together with it.
     *
     *      INTENT equals the ERC-1271 magic value because {IBittyV1IntentProtocol} declares only
     *      `isValidSignature` — for an intent protocol the two claims are the same claim.
     */
    bytes4 internal constant LENDING_INTERFACE_ID = 0xb9f16a0c;
    bytes4 internal constant STAKING_INTERFACE_ID = 0xc8ada217;
    bytes4 internal constant AMM_INTERFACE_ID = 0x932722bd;
    bytes4 internal constant INTENT_INTERFACE_ID = 0x1626ba7e;

    /**
     * @notice Every registered protocol, in one set — the category is not part of the key.
     * @dev Nobody TELLS this contract a protocol's category any more: a protocol declares its own via
     *      ERC-165, and registration reads that declaration once and records it in {protocolCategory}.
     *      So a category stops being an argument threaded through every call and becomes a property
     *      of the protocol, which is the only place it was ever really known.
     */
    EnumerableSet.AddressSet internal _protocols;
    mapping(address => bool) public deprecatedProtocols;

    /**
     * @notice The category a protocol declared when it was registered, or 0 if it never was.
     * @dev Recorded rather than re-derived on each read, for two reasons. Reading it is a storage
     *      load instead of the three staticcalls an {ERC165Checker} probe costs, which matters
     *      because the vault consults it on every deposit and withdrawal. And it stays answerable if
     *      the protocol later stops responding — which is exactly when deprecating it matters most.
     */
    mapping(address => bytes4) public protocolCategory;

    EnumerableSet.AddressSet internal _assets;
    EnumerableSet.AddressSet internal _stableCoins;

    address public constant DEPLOYER = 0x12EE2de7BF086388B1D560eb95e7191Edfab9823;

    error NotDeployer();

    /// @notice The address declares none of the four Bitty protocol interfaces.
    error NotABittyProtocol(address protocol);

    /// @notice The protocol declares more than one category, so no single manager role governs it.
    error AmbiguousProtocolCategory(address protocol);

    constructor() AccessControlDefaultAdminRules(DEFAULT_ADMIN_TRANSFER_DELAY, DEPLOYER) {
        if (tx.origin != DEPLOYER) revert NotDeployer();
        _grantRole(ASSET_MANAGER_ROLE, DEPLOYER);
        _grantRole(STABLE_COIN_MANAGER_ROLE, DEPLOYER);
        _grantRole(LENDING_MANAGER_ROLE, DEPLOYER);
        _grantRole(STAKING_MANAGER_ROLE, DEPLOYER);
        _grantRole(AMM_MANAGER_ROLE, DEPLOYER);
        _grantRole(INTENT_MANAGER_ROLE, DEPLOYER);
    }

    function initialize(
        address[] memory assets_,
        address[] memory stableCoins_,
        address[] memory lendingProtocols_,
        address[] memory stakingProtocols_,
        address[] memory ammProtocols_,
        address[] memory intentProtocols_
    ) public initializer onlyRole(DEFAULT_ADMIN_ROLE) {
        _addAssets(assets_);
        _addStableCoins(stableCoins_);
        _addProtocols(lendingProtocols_);
        _addProtocols(stakingProtocols_);
        _addProtocols(ammProtocols_);
        _addProtocols(intentProtocols_);
    }

    function addAssets(address[] memory assetAddresses) external override onlyRole(ASSET_MANAGER_ROLE) {
        _addAssets(assetAddresses);
    }

    function _addAssets(address[] memory assetAddresses) internal {
        for (uint256 i = 0; i < assetAddresses.length; i++) {
            if (assetAddresses[i] != address(0)) {
                _assets.add(assetAddresses[i]);
            }
        }
    }

    function removeAssets(address[] memory assetAddresses) external override onlyRole(ASSET_MANAGER_ROLE) {
        for (uint256 i = 0; i < assetAddresses.length; i++) {
            if (assetAddresses[i] != address(0)) {
                _assets.remove(assetAddresses[i]);
            }
        }
    }

    function isAssetRegistered(address assetAddress) external view override returns (bool) {
        return _assets.contains(assetAddress);
    }

    function addStableCoins(address[] memory stableCoinAddresses) external override onlyRole(STABLE_COIN_MANAGER_ROLE) {
        _addStableCoins(stableCoinAddresses);
    }

    function _addStableCoins(address[] memory stableCoinAddresses) internal {
        for (uint256 i = 0; i < stableCoinAddresses.length; i++) {
            if (stableCoinAddresses[i] != address(0)) {
                _stableCoins.add(stableCoinAddresses[i]);
            }
        }
    }

    function removeStableCoins(address[] memory stableCoinAddresses)
        external
        override
        onlyRole(STABLE_COIN_MANAGER_ROLE)
    {
        for (uint256 i = 0; i < stableCoinAddresses.length; i++) {
            if (stableCoinAddresses[i] != address(0)) {
                _stableCoins.remove(stableCoinAddresses[i]);
            }
        }
    }

    function isStableCoinRegistered(address stableCoinAddress) external view override returns (bool) {
        return _stableCoins.contains(stableCoinAddress);
    }

    function _declaredCategory(address protocol) private view returns (bytes4 category) {
        bytes4[4] memory ids = [LENDING_INTERFACE_ID, STAKING_INTERFACE_ID, AMM_INTERFACE_ID, INTENT_INTERFACE_ID];
        for (uint256 i = 0; i < ids.length; i++) {
            if (ERC165Checker.supportsInterface(protocol, ids[i])) {
                if (category != bytes4(0)) revert AmbiguousProtocolCategory(protocol);
                category = ids[i];
            }
        }
        if (category == bytes4(0)) revert NotABittyProtocol(protocol);
    }

    function _categoryRole(bytes4 categoryInterfaceId) private pure returns (bytes32) {
        if (categoryInterfaceId == LENDING_INTERFACE_ID) return LENDING_MANAGER_ROLE;
        if (categoryInterfaceId == STAKING_INTERFACE_ID) return STAKING_MANAGER_ROLE;
        if (categoryInterfaceId == AMM_INTERFACE_ID) return AMM_MANAGER_ROLE;
        return INTENT_MANAGER_ROLE;
    }

    function addProtocols(address[] memory protocolAddresses) external override {
        _addProtocols(protocolAddresses);
    }

    function _addProtocols(address[] memory protocolAddresses) internal {
        for (uint256 i = 0; i < protocolAddresses.length; i++) {
            address protocol = protocolAddresses[i];
            if (protocol == address(0)) {
                continue;
            }
            bytes4 category = _declaredCategory(protocol);
            _checkRole(_categoryRole(category));
            _protocols.add(protocol);
            protocolCategory[protocol] = category;
            deprecatedProtocols[protocol] = false;
        }
    }

    function deprecateProtocols(address[] memory protocolAddresses) external override {
        for (uint256 i = 0; i < protocolAddresses.length; i++) {
            address protocol = protocolAddresses[i];
            if (protocol == address(0)) {
                continue;
            }
            bytes4 category = protocolCategory[protocol];
            if (category == bytes4(0)) {
                continue;
            }
            _checkRole(_categoryRole(category));
            if (_protocols.remove(protocol)) {
                deprecatedProtocols[protocol] = true;
            }
        }
    }

    function isProtocolRegistered(address protocolAddress) external view override returns (bool) {
        return _protocols.contains(protocolAddress);
    }

    function isProtocolDeprecated(address protocolAddress) external view override returns (bool) {
        return deprecatedProtocols[protocolAddress];
    }

    function getProtocols() external view override returns (address[] memory addresses) {
        return _protocols.values();
    }

    function getAssets() external view override returns (address[] memory addresses) {
        return _assets.values();
    }

    function getStableCoins() external view override returns (address[] memory addresses) {
        return _stableCoins.values();
    }
}
