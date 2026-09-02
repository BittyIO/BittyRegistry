// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    AccessControlDefaultAdminRulesUpgradeable
} from "openzeppelin-contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {
    IBittyV1Guard,
    NotDeployer,
    LengthMismatch,
    NotRegisteredProtocol,
    NotRegisteredImplementation,
    AddressZero
} from "./interfaces/IBittyV1Guard.sol";
import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title BittyV1Guard
 * @notice Guard of allowed assets and protocols for Bitty.
 */
contract BittyV1Guard is IBittyV1Guard, Initializable, AccessControlDefaultAdminRulesUpgradeable, UUPSUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint48 internal constant DEFAULT_ADMIN_TRANSFER_DELAY = 7 days;

    bytes32 public constant ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");
    bytes32 public constant PROTOCOL_MANAGER_ROLE = keccak256("PROTOCOL_MANAGER_ROLE");
    bytes32 public constant IMPLEMENTATION_MANAGER_ROLE = keccak256("IMPLEMENTATION_MANAGER_ROLE");

    EnumerableSet.AddressSet internal _protocols;

    EnumerableSet.AddressSet internal _deprecatedProtocols;

    mapping(address => uint8) public protocolCategory;

    mapping(address => bool) internal _assets;

    mapping(address => uint8) public assetCategory;

    mapping(uint8 category => address) public latestImplementation;

    mapping(uint8 category => EnumerableSet.AddressSet) internal _pastImplementations;

    address public constant DEPLOYER = 0x12EE2de7BF086388B1D560eb95e7191Edfab9823;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address[] memory assets_,
        uint8[] memory assetCategories_,
        address[] memory protocols_,
        uint8[] memory protocolCategories_
    ) public initializer {
        if (tx.origin != DEPLOYER) revert NotDeployer();
        __AccessControlDefaultAdminRules_init(DEFAULT_ADMIN_TRANSFER_DELAY, DEPLOYER);
        __UUPSUpgradeable_init();
        _grantRole(ASSET_MANAGER_ROLE, DEPLOYER);
        _grantRole(PROTOCOL_MANAGER_ROLE, DEPLOYER);
        _grantRole(IMPLEMENTATION_MANAGER_ROLE, DEPLOYER);
        _addAssets(assets_, assetCategories_);
        _addProtocols(protocols_, protocolCategories_);
    }

    function _authorizeUpgrade(address) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function addAssets(address[] memory assetAddresses, uint8[] memory categories)
        external
        override
        onlyRole(ASSET_MANAGER_ROLE)
    {
        _addAssets(assetAddresses, categories);
    }

    function _addAssets(address[] memory assetAddresses, uint8[] memory categories) internal {
        if (assetAddresses.length != categories.length) {
            revert LengthMismatch();
        }
        for (uint256 i = 0; i < assetAddresses.length; i++) {
            address asset = assetAddresses[i];
            if (asset == address(0) || categories[i] == 0) {
                continue;
            }
            if (_assets[asset] && assetCategory[asset] == categories[i]) {
                continue;
            }
            _assets[asset] = true;
            assetCategory[asset] = categories[i];
            emit AssetAdded(asset, categories[i]);
        }
    }

    function removeAssets(address[] memory assetAddresses) external override onlyRole(ASSET_MANAGER_ROLE) {
        for (uint256 i = 0; i < assetAddresses.length; i++) {
            address asset = assetAddresses[i];
            if (_assets[asset]) {
                _assets[asset] = false;
                assetCategory[asset] = 0;
                emit AssetRemoved(asset);
            }
        }
    }

    function isAssetRegistered(address assetAddress) external view override returns (bool) {
        return _assets[assetAddress];
    }

    function addProtocols(address[] memory protocolAddresses, uint8[] memory categories)
        external
        override
        onlyRole(PROTOCOL_MANAGER_ROLE)
    {
        _addProtocols(protocolAddresses, categories);
    }

    function _addProtocols(address[] memory protocolAddresses, uint8[] memory categories) internal {
        if (protocolAddresses.length != categories.length) {
            revert LengthMismatch();
        }
        for (uint256 i = 0; i < protocolAddresses.length; i++) {
            address protocol = protocolAddresses[i];
            if (protocol == address(0) || categories[i] == 0) {
                continue;
            }
            if (_protocols.contains(protocol) && protocolCategory[protocol] == categories[i]) {
                continue;
            }
            _protocols.add(protocol);
            protocolCategory[protocol] = categories[i];
            _deprecatedProtocols.remove(protocol);
            emit ProtocolAdded(protocol, categories[i]);
        }
    }

    function deprecateProtocols(address[] memory protocolAddresses) external override onlyRole(PROTOCOL_MANAGER_ROLE) {
        for (uint256 i = 0; i < protocolAddresses.length; i++) {
            address protocol = protocolAddresses[i];
            if (!_protocols.remove(protocol)) {
                revert NotRegisteredProtocol(protocol);
            }
            _deprecatedProtocols.add(protocol);
            emit ProtocolDeprecated(protocol);
        }
    }

    function isProtocolRegistered(address protocolAddress) external view override returns (bool) {
        return _protocols.contains(protocolAddress);
    }

    function getProtocols() external view override returns (address[] memory addresses) {
        return _protocols.values();
    }

    function getDeprecatedProtocols() external view override returns (address[] memory addresses) {
        return _deprecatedProtocols.values();
    }

    function isProtocolDeprecated(address protocolAddress) external view override returns (bool) {
        return _deprecatedProtocols.contains(protocolAddress);
    }

    function setImplementation(address implementation, uint8 category)
        external
        override
        onlyRole(IMPLEMENTATION_MANAGER_ROLE)
    {
        if (category == 0 || implementation == address(0)) revert AddressZero();
        address current = latestImplementation[category];
        if (current == implementation) return;
        if (current != address(0)) _pastImplementations[category].add(current);
        _pastImplementations[category].remove(implementation);
        latestImplementation[category] = implementation;
        emit ImplementationRegistered(implementation);
    }

    function retireImplementations(address[] memory implementations, uint8 category)
        external
        override
        onlyRole(IMPLEMENTATION_MANAGER_ROLE)
    {
        for (uint256 i = 0; i < implementations.length; i++) {
            address implementation = implementations[i];
            if (!_pastImplementations[category].remove(implementation)) {
                revert NotRegisteredImplementation(implementation);
            }
            emit ImplementationUnregistered(implementation);
        }
    }

    function isImplementationRegisteredFor(address implementation, uint8 category)
        external
        view
        override
        returns (bool)
    {
        return implementation == latestImplementation[category]
            || _pastImplementations[category].contains(implementation);
    }

    function getPastImplementations(uint8 category) external view override returns (address[] memory) {
        return _pastImplementations[category].values();
    }
}
