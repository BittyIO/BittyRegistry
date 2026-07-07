// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {
    AccessControlDefaultAdminRules
} from "openzeppelin-contracts/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {IBittyV1Guard} from "./interfaces/IBittyV1Guard.sol";
import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

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

    mapping(address => bool) public deprecatedLendingProtocols;
    mapping(address => bool) public deprecatedStakingProtocols;
    mapping(address => bool) public deprecatedAMMProtocols;
    mapping(address => bool) public deprecatedIntentProtocols;

    EnumerableSet.AddressSet internal _assets;
    EnumerableSet.AddressSet internal _stableCoins;
    EnumerableSet.AddressSet internal _lendingProtocols;
    EnumerableSet.AddressSet internal _stakingProtocols;
    EnumerableSet.AddressSet internal _ammProtocols;
    EnumerableSet.AddressSet internal _intentProtocols;

    constructor() AccessControlDefaultAdminRules(DEFAULT_ADMIN_TRANSFER_DELAY, tx.origin) {
        _grantRole(ASSET_MANAGER_ROLE, tx.origin);
        _grantRole(STABLE_COIN_MANAGER_ROLE, tx.origin);
        _grantRole(LENDING_MANAGER_ROLE, tx.origin);
        _grantRole(STAKING_MANAGER_ROLE, tx.origin);
        _grantRole(AMM_MANAGER_ROLE, tx.origin);
        _grantRole(INTENT_MANAGER_ROLE, tx.origin);
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
        _addLendingProtocols(lendingProtocols_);
        _addStakingProtocols(stakingProtocols_);
        _addAMMProtocols(ammProtocols_);
        _addIntentProtocols(intentProtocols_);
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

    function addLendingProtocols(address[] memory lendingProtocolAddresses)
        external
        override
        onlyRole(LENDING_MANAGER_ROLE)
    {
        _addLendingProtocols(lendingProtocolAddresses);
    }

    function _addLendingProtocols(address[] memory lendingProtocolAddresses) internal {
        for (uint256 i = 0; i < lendingProtocolAddresses.length; i++) {
            if (lendingProtocolAddresses[i] != address(0)) {
                _lendingProtocols.add(lendingProtocolAddresses[i]);
                deprecatedLendingProtocols[lendingProtocolAddresses[i]] = false;
            }
        }
    }

    function deprecateLendingProtocols(address[] memory lendingProtocolAddresses)
        external
        override
        onlyRole(LENDING_MANAGER_ROLE)
    {
        for (uint256 i = 0; i < lendingProtocolAddresses.length; i++) {
            if (lendingProtocolAddresses[i] != address(0) && _lendingProtocols.remove(lendingProtocolAddresses[i])) {
                deprecatedLendingProtocols[lendingProtocolAddresses[i]] = true;
            }
        }
    }

    function isLendingProtocolRegistered(address lendingProtocolAddress) external view override returns (bool) {
        return _lendingProtocols.contains(lendingProtocolAddress);
    }

    function isLendingProtocolDeprecated(address lendingProtocolAddress) external view override returns (bool) {
        return deprecatedLendingProtocols[lendingProtocolAddress];
    }

    function addStakingProtocols(address[] memory stakingProtocolAddresses)
        external
        override
        onlyRole(STAKING_MANAGER_ROLE)
    {
        _addStakingProtocols(stakingProtocolAddresses);
    }

    function _addStakingProtocols(address[] memory stakingProtocolAddresses) internal {
        for (uint256 i = 0; i < stakingProtocolAddresses.length; i++) {
            if (stakingProtocolAddresses[i] != address(0)) {
                _stakingProtocols.add(stakingProtocolAddresses[i]);
                deprecatedStakingProtocols[stakingProtocolAddresses[i]] = false;
            }
        }
    }

    function isStakingProtocolRegistered(address stakingProtocolAddress) external view override returns (bool) {
        return _stakingProtocols.contains(stakingProtocolAddress);
    }

    function isStakingProtocolDeprecated(address stakingProtocolAddress) external view override returns (bool) {
        return deprecatedStakingProtocols[stakingProtocolAddress];
    }

    function deprecateStakingProtocols(address[] memory stakingProtocolAddress)
        external
        override
        onlyRole(STAKING_MANAGER_ROLE)
    {
        for (uint256 i = 0; i < stakingProtocolAddress.length; i++) {
            if (stakingProtocolAddress[i] != address(0) && _stakingProtocols.remove(stakingProtocolAddress[i])) {
                deprecatedStakingProtocols[stakingProtocolAddress[i]] = true;
            }
        }
    }

    function addAMMProtocols(address[] memory ammProtocolAddresses) external override onlyRole(AMM_MANAGER_ROLE) {
        _addAMMProtocols(ammProtocolAddresses);
    }

    function _addAMMProtocols(address[] memory ammProtocolAddresses) internal {
        for (uint256 i = 0; i < ammProtocolAddresses.length; i++) {
            if (ammProtocolAddresses[i] != address(0)) {
                _ammProtocols.add(ammProtocolAddresses[i]);
                deprecatedAMMProtocols[ammProtocolAddresses[i]] = false;
            }
        }
    }

    function deprecateAMMProtocols(address[] memory ammProtocolAddresses) external override onlyRole(AMM_MANAGER_ROLE) {
        for (uint256 i = 0; i < ammProtocolAddresses.length; i++) {
            if (ammProtocolAddresses[i] != address(0) && _ammProtocols.remove(ammProtocolAddresses[i])) {
                deprecatedAMMProtocols[ammProtocolAddresses[i]] = true;
            }
        }
    }

    function isAMMProtocolRegistered(address ammProtocolAddress) external view override returns (bool) {
        return _ammProtocols.contains(ammProtocolAddress);
    }

    function isAMMProtocolDeprecated(address ammProtocolAddress) external view override returns (bool) {
        return deprecatedAMMProtocols[ammProtocolAddress];
    }

    function addIntentProtocols(address[] memory intentProtocolAddresses)
        external
        override
        onlyRole(INTENT_MANAGER_ROLE)
    {
        _addIntentProtocols(intentProtocolAddresses);
    }

    function _addIntentProtocols(address[] memory intentProtocolAddresses) internal {
        for (uint256 i = 0; i < intentProtocolAddresses.length; i++) {
            if (intentProtocolAddresses[i] != address(0)) {
                _intentProtocols.add(intentProtocolAddresses[i]);
                deprecatedIntentProtocols[intentProtocolAddresses[i]] = false;
            }
        }
    }

    function isIntentProtocolRegistered(address intentProtocolAddress) external view override returns (bool) {
        return _intentProtocols.contains(intentProtocolAddress);
    }

    function deprecateIntentProtocols(address[] memory intentProtocolAddresses)
        external
        override
        onlyRole(INTENT_MANAGER_ROLE)
    {
        for (uint256 i = 0; i < intentProtocolAddresses.length; i++) {
            if (intentProtocolAddresses[i] != address(0) && _intentProtocols.remove(intentProtocolAddresses[i])) {
                deprecatedIntentProtocols[intentProtocolAddresses[i]] = true;
            }
        }
    }

    function _activeAddresses(EnumerableSet.AddressSet storage set, mapping(address => bool) storage deprecatedMap)
        private
        view
        returns (address[] memory active)
    {
        address[] memory all = set.values();
        uint256 activeCount;
        for (uint256 i = 0; i < all.length; i++) {
            if (!deprecatedMap[all[i]]) {
                activeCount++;
            }
        }
        active = new address[](activeCount);
        uint256 j;
        for (uint256 i = 0; i < all.length; i++) {
            if (!deprecatedMap[all[i]]) {
                active[j++] = all[i];
            }
        }
    }

    function isIntentProtocolDeprecated(address intentProtocolAddress) external view override returns (bool) {
        return deprecatedIntentProtocols[intentProtocolAddress];
    }

    function getAssets() external view override returns (address[] memory addresses) {
        return _assets.values();
    }

    function getStableCoins() external view override returns (address[] memory addresses) {
        return _stableCoins.values();
    }

    function getLendingProtocols() external view override returns (address[] memory addresses) {
        return _activeAddresses(_lendingProtocols, deprecatedLendingProtocols);
    }

    function getStakingProtocols() external view override returns (address[] memory addresses) {
        return _activeAddresses(_stakingProtocols, deprecatedStakingProtocols);
    }

    function getAMMProtocols() external view override returns (address[] memory addresses) {
        return _activeAddresses(_ammProtocols, deprecatedAMMProtocols);
    }

    function getIntentProtocols() external view override returns (address[] memory addresses) {
        return _activeAddresses(_intentProtocols, deprecatedIntentProtocols);
    }
}
