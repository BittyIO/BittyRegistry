// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {
    AccessControlDefaultAdminRules
} from "openzeppelin-contracts/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {IBittyV1Guard, NotDeployer, LengthMismatch, NotRegisteredProtocol} from "./interfaces/IBittyV1Guard.sol";
import {ERC165Checker} from "openzeppelin-contracts/contracts/utils/introspection/ERC165Checker.sol";

/**
 * @title BittyV1Guard
 * @notice Guard of allowed assets and protocols for Bitty.
 */
contract BittyV1Guard is IBittyV1Guard, Initializable, AccessControlDefaultAdminRules {
    uint48 internal constant DEFAULT_ADMIN_TRANSFER_DELAY = 7 days;

    bytes32 public constant ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");
    bytes32 public constant PROTOCOL_MANAGER_ROLE = keccak256("PROTOCOL_MANAGER_ROLE");

    mapping(address => bool) internal _protocols;
    mapping(address => bool) public deprecatedProtocols;

    mapping(address => uint8) public protocolCategory;

    mapping(address => bool) internal _assets;

    mapping(address => uint8) public assetCategory;

    address public constant DEPLOYER = 0x12EE2de7BF086388B1D560eb95e7191Edfab9823;

    constructor() AccessControlDefaultAdminRules(DEFAULT_ADMIN_TRANSFER_DELAY, DEPLOYER) {
        if (tx.origin != DEPLOYER) revert NotDeployer();
        _grantRole(ASSET_MANAGER_ROLE, DEPLOYER);
        _grantRole(PROTOCOL_MANAGER_ROLE, DEPLOYER);
    }

    function initialize(
        address[] memory assets_,
        uint8[] memory assetCategories_,
        address[] memory protocols_,
        uint8[] memory protocolCategories_
    ) public initializer onlyRole(DEFAULT_ADMIN_ROLE) {
        _addAssets(assets_, assetCategories_);
        _addProtocols(protocols_, protocolCategories_);
    }

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
            _protocols[protocol] = true;
            protocolCategory[protocol] = categories[i];
            if (deprecatedProtocols[protocol]) {
                deprecatedProtocols[protocol] = false;
            }
            emit ProtocolAdded(protocol, categories[i]);
        }
    }

    function deprecateProtocols(address[] memory protocolAddresses) external override onlyRole(PROTOCOL_MANAGER_ROLE) {
        for (uint256 i = 0; i < protocolAddresses.length; i++) {
            address protocol = protocolAddresses[i];
            if (!_protocols[protocol]) {
                revert NotRegisteredProtocol(protocol);
            }
            _protocols[protocol] = false;
            deprecatedProtocols[protocol] = true;
            emit ProtocolDeprecated(protocol);
        }
    }

    function isProtocolRegistered(address protocolAddress) external view override returns (bool) {
        return _protocols[protocolAddress];
    }

    function isProtocolDeprecated(address protocolAddress) external view override returns (bool) {
        return deprecatedProtocols[protocolAddress];
    }
}
