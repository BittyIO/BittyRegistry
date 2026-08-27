// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import "forge-std/console.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {BittyV1Guard} from "../../src/BittyV1Guard.sol";
import {
    IBittyV1Guard,
    NotDeployer,
    LengthMismatch,
    NotRegisteredProtocol
} from "../../src/interfaces/IBittyV1Guard.sol";
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";

contract BittyV1GuardTest is Test {
    uint8 internal constant LENDING_ID = 1;
    uint8 internal constant STAKING_ID = 2;
    uint8 internal constant AMM_ID = 3;
    uint8 internal constant INTENT_ID = 4;

    BittyV1Guard public bittyGuard;
    address public deployAdmin;
    address public protocolOwner;
    address public ammProtocol;
    address public lendingProtocol;
    address public stakingProtocol;
    address public intentProtocol;
    MockERC20 public mockWETH;
    MockERC20 public mockWBTC;
    MockERC20 public mockUSDT;
    MockERC20 public mockUSDC;
    address[] public assets;
    address[] public stableCoins;
    address[] public lendingProtocols;
    address[] public stakingProtocols;
    address[] public ammProtocols;
    address[] public intentProtocols;

    function setUp() public {
        protocolOwner = makeAddr("protocolOwner");
        ammProtocol = makeAddr("ammProtocol");
        lendingProtocol = makeAddr("lendingProtocol");
        stakingProtocol = makeAddr("stakingProtocol");
        intentProtocol = makeAddr("intentProtocol");
        mockWETH = new MockERC20("WETH", "WETH", 18);
        mockWBTC = new MockERC20("WBTC", "WBTC", 8);
        mockUSDT = new MockERC20("USDT", "USDT", 6);
        mockUSDC = new MockERC20("USDC", "USDC", 6);
        deployAdmin = 0x12EE2de7BF086388B1D560eb95e7191Edfab9823;
        vm.prank(deployAdmin, deployAdmin);
        bittyGuard = new BittyV1Guard();
        vm.startPrank(deployAdmin);
        bittyGuard.grantRole(bittyGuard.ASSET_MANAGER_ROLE(), protocolOwner);
        bittyGuard.grantRole(bittyGuard.PROTOCOL_MANAGER_ROLE(), protocolOwner);
        vm.stopPrank();
        assets = new address[](2);
        assets[0] = address(mockWETH);
        assets[1] = address(mockWBTC);
        stableCoins = new address[](2);
        stableCoins[0] = address(mockUSDT);
        stableCoins[1] = address(mockUSDC);
        lendingProtocols = new address[](1);
        lendingProtocols[0] = lendingProtocol;
        stakingProtocols = new address[](1);
        stakingProtocols[0] = stakingProtocol;
        ammProtocols = new address[](1);
        ammProtocols[0] = ammProtocol;
        intentProtocols = new address[](1);
        intentProtocols[0] = intentProtocol;
    }

    function test_OnlyDeployerCanDeployGuard() public {
        address randomDeployer = makeAddr("randomDeployer");
        vm.prank(randomDeployer, randomDeployer);
        vm.expectRevert(NotDeployer.selector);
        new BittyV1Guard();

        address deployer = bittyGuard.DEPLOYER();
        vm.prank(deployer, deployer);
        BittyV1Guard g = new BittyV1Guard();
        assertTrue(g.hasRole(g.DEFAULT_ADMIN_ROLE(), deployer));
        assertFalse(g.hasRole(g.DEFAULT_ADMIN_ROLE(), randomDeployer));
    }

    function test_AddRegisteredAssets() public {
        vm.prank(protocolOwner);
        bittyGuard.addAssets(assets, _cats(assets.length, CRYPTO_CAT));
        assertTrue(bittyGuard.isAssetRegistered(address(mockWETH)));
        assertTrue(bittyGuard.isAssetRegistered(address(mockWBTC)));
    }

    function test_RemoveAssets() public {
        vm.prank(protocolOwner);
        bittyGuard.removeAssets(assets);
        assertFalse(bittyGuard.isAssetRegistered(address(mockWETH)));
        assertFalse(bittyGuard.isAssetRegistered(address(mockWBTC)));
    }

    function test_AddStableCoins() public {
        vm.prank(protocolOwner);
        bittyGuard.addAssets(stableCoins, _cats(stableCoins.length, STABLE_CAT));
        assertTrue(_isStable(address(mockUSDT)));
        assertTrue(_isStable(address(mockUSDC)));
    }

    function test_RemoveStableCoins() public {
        vm.prank(protocolOwner);
        bittyGuard.removeAssets(stableCoins);
        assertFalse(_isStable(address(mockUSDT)));
        assertFalse(_isStable(address(mockUSDC)));
    }

    function test_AddLendingProtocols() public {
        _addProtocols(lendingProtocols, LENDING_ID);
        assertTrue(bittyGuard.isProtocolRegistered(lendingProtocol));
    }

    function test_DeprecateLendingProtocols() public {
        _addProtocols(lendingProtocols, LENDING_ID);
        assertTrue(bittyGuard.isProtocolRegistered(lendingProtocol));
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(lendingProtocols);
        assertFalse(bittyGuard.isProtocolRegistered(lendingProtocol));
        assertTrue(bittyGuard.isProtocolDeprecated(lendingProtocol));
        _assertProtocolsAre(new address[](0));
    }

    function test_DeprecateUnregistered_reverts() public {
        address unreg = makeAddr("unregistered");
        address[] memory addrs = new address[](1);
        addrs[0] = unreg;

        vm.prank(protocolOwner);
        vm.expectRevert(abi.encodeWithSelector(NotRegisteredProtocol.selector, unreg));
        bittyGuard.deprecateProtocols(addrs);
    }

    function test_AddStakingProtocols() public {
        _addProtocols(stakingProtocols, STAKING_ID);
        assertTrue(bittyGuard.isProtocolRegistered(stakingProtocol));
        assertFalse(bittyGuard.isProtocolDeprecated(stakingProtocol));
    }

    function test_DeprecateStakingProtocols() public {
        _addProtocols(stakingProtocols, STAKING_ID);
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(stakingProtocols);
        assertFalse(bittyGuard.isProtocolRegistered(stakingProtocol));
        assertTrue(bittyGuard.isProtocolDeprecated(stakingProtocol));
        _assertProtocolsAre(new address[](0));
    }

    function test_AddAMMProtocols() public {
        _addProtocols(ammProtocols, AMM_ID);
        assertTrue(bittyGuard.isProtocolRegistered(ammProtocol));
        assertFalse(bittyGuard.isProtocolDeprecated(ammProtocol));
    }

    function test_DeprecateAMMProtocols() public {
        _addProtocols(ammProtocols, AMM_ID);
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(ammProtocols);
        assertFalse(bittyGuard.isProtocolRegistered(ammProtocol));
        assertTrue(bittyGuard.isProtocolDeprecated(ammProtocol));
        _assertProtocolsAre(new address[](0));
    }

    function test_DeprecateAMMProtocolsAllowsAllDeprecated() public {
        address[] memory ammProtocolAddresses = new address[](1);
        ammProtocolAddresses[0] = ammProtocol;
        _addProtocols(ammProtocolAddresses, AMM_ID);
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(ammProtocolAddresses);
        assertFalse(bittyGuard.isProtocolRegistered(ammProtocol));
        assertTrue(bittyGuard.isProtocolDeprecated(ammProtocol));
    }

    function test_AddAMMProtocolsClearsDeprecatedFlag() public {
        _addProtocols(ammProtocols, AMM_ID);
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(ammProtocols);
        _addProtocols(ammProtocols, AMM_ID);
        assertTrue(bittyGuard.isProtocolRegistered(ammProtocol));
        assertFalse(bittyGuard.isProtocolDeprecated(ammProtocol));
    }

    function test_AddRegisteredNeedToRemoveDeprecated() public {
        _addProtocols(lendingProtocols, LENDING_ID);
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(lendingProtocols);
        _addProtocols(lendingProtocols, LENDING_ID);
        assertTrue(bittyGuard.isProtocolRegistered(lendingProtocol));
        assertFalse(bittyGuard.isProtocolDeprecated(lendingProtocol));
    }

    function test_AddIntentProtocols() public {
        _addProtocols(intentProtocols, INTENT_ID);
        assertTrue(bittyGuard.isProtocolRegistered(intentProtocol));
    }

    function test_DeprecateIntentProtocols() public {
        _addProtocols(intentProtocols, INTENT_ID);
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(intentProtocols);
        assertFalse(bittyGuard.isProtocolRegistered(intentProtocol));
        assertTrue(bittyGuard.isProtocolDeprecated(intentProtocol));
        _assertProtocolsAre(new address[](0));
    }

    function test_AddIntentProtocolsClearsDeprecatedFlag() public {
        _addProtocols(intentProtocols, INTENT_ID);
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(intentProtocols);
        _addProtocols(intentProtocols, INTENT_ID);
        assertTrue(bittyGuard.isProtocolRegistered(intentProtocol));
        assertFalse(bittyGuard.isProtocolDeprecated(intentProtocol));
    }

    function test_GetAssets() public {
        vm.prank(protocolOwner);
        bittyGuard.addAssets(assets, _cats(assets.length, CRYPTO_CAT));
        _assertAssetsAre(assets);
    }

    function test_GetAssetsAfterRemove() public {
        vm.prank(protocolOwner);
        bittyGuard.addAssets(assets, _cats(assets.length, CRYPTO_CAT));
        address[] memory toRemove = new address[](1);
        toRemove[0] = address(mockWETH);
        vm.prank(protocolOwner);
        bittyGuard.removeAssets(toRemove);
        address[] memory expected = new address[](1);
        expected[0] = address(mockWBTC);
        _assertAssetsAre(expected);
    }

    function test_GetStableCoins() public {
        vm.prank(protocolOwner);
        bittyGuard.addAssets(stableCoins, _cats(stableCoins.length, STABLE_CAT));
        _assertStableCoinsAre(stableCoins);
    }

    function test_GetStableCoinsAfterRemove() public {
        vm.prank(protocolOwner);
        bittyGuard.addAssets(stableCoins, _cats(stableCoins.length, STABLE_CAT));
        address[] memory toRemove = new address[](1);
        toRemove[0] = address(mockUSDT);
        vm.prank(protocolOwner);
        bittyGuard.removeAssets(toRemove);
        address[] memory expected = new address[](1);
        expected[0] = address(mockUSDC);
        _assertStableCoinsAre(expected);
    }

    function test_GetAMMProtocols() public {
        _addProtocols(ammProtocols, AMM_ID);
        _assertProtocolsAre(ammProtocols);
    }

    function test_GetAMMProtocolsAfterPartialDeprecate() public {
        address extraAmm = makeAddr("extraAmm");
        address[] memory twoAmms = new address[](2);
        twoAmms[0] = ammProtocol;
        twoAmms[1] = extraAmm;
        _addProtocols(twoAmms, AMM_ID);
        address[] memory toDeprecate = new address[](1);
        toDeprecate[0] = extraAmm;
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(toDeprecate);
        address[] memory expected = new address[](1);
        expected[0] = ammProtocol;
        _assertProtocolsAre(expected);
        assertTrue(bittyGuard.isProtocolDeprecated(extraAmm));
        assertFalse(bittyGuard.isProtocolRegistered(extraAmm));
    }

    function test_GetLendingProtocolsExcludesDeprecated() public {
        address lendingProtocolB = makeAddr("lendingProtocolB");
        address[] memory twoProtocols = new address[](2);
        twoProtocols[0] = lendingProtocol;
        twoProtocols[1] = lendingProtocolB;
        _addProtocols(twoProtocols, LENDING_ID);
        address[] memory toDeprecate = new address[](1);
        toDeprecate[0] = lendingProtocol;
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(toDeprecate);
        address[] memory expected = new address[](1);
        expected[0] = lendingProtocolB;
        _assertProtocolsAre(expected);
        assertTrue(bittyGuard.isProtocolDeprecated(lendingProtocol));
        assertFalse(bittyGuard.isProtocolRegistered(lendingProtocol));
        assertTrue(bittyGuard.isProtocolRegistered(lendingProtocolB));
    }

    function test_GetLendingProtocolsReaddAfterDeprecate() public {
        _addProtocols(lendingProtocols, LENDING_ID);
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(lendingProtocols);
        _assertProtocolsAre(new address[](0));
        _addProtocols(lendingProtocols, LENDING_ID);
        _assertProtocolsAre(lendingProtocols);
    }

    function test_GetStakingProtocolsExcludesDeprecated() public {
        address stakingProtocolB = makeAddr("stakingProtocolB");
        address[] memory twoProtocols = new address[](2);
        twoProtocols[0] = stakingProtocol;
        twoProtocols[1] = stakingProtocolB;
        _addProtocols(twoProtocols, STAKING_ID);
        address[] memory toDeprecate = new address[](1);
        toDeprecate[0] = stakingProtocol;
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(toDeprecate);
        address[] memory expected = new address[](1);
        expected[0] = stakingProtocolB;
        _assertProtocolsAre(expected);
    }

    function test_GetIntentProtocolsExcludesDeprecated() public {
        address intentProtocolB = makeAddr("intentProtocolB");
        address[] memory twoProtocols = new address[](2);
        twoProtocols[0] = intentProtocol;
        twoProtocols[1] = intentProtocolB;
        _addProtocols(twoProtocols, INTENT_ID);
        address[] memory toDeprecate = new address[](1);
        toDeprecate[0] = intentProtocol;
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(toDeprecate);
        address[] memory expected = new address[](1);
        expected[0] = intentProtocolB;
        _assertProtocolsAre(expected);
    }

    function test_InitializeSeedsEveryRegistry() public {
        vm.startPrank(deployAdmin, deployAdmin);
        BittyV1Guard guard = new BittyV1Guard();
        address[] memory allProtocols_ = new address[](4);
        allProtocols_[0] = lendingProtocol;
        allProtocols_[1] = stakingProtocol;
        allProtocols_[2] = ammProtocol;
        allProtocols_[3] = intentProtocol;
        uint8[] memory categories = new uint8[](4);
        categories[0] = LENDING_ID;
        categories[1] = STAKING_ID;
        categories[2] = AMM_ID;
        categories[3] = INTENT_ID;
        // Assets and stable coins seed through ONE list now, told apart by category.
        address[] memory seedAssets = new address[](assets.length + stableCoins.length);
        uint8[] memory seedCategories = new uint8[](seedAssets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            seedAssets[i] = assets[i];
            seedCategories[i] = CRYPTO_CAT;
        }
        for (uint256 i = 0; i < stableCoins.length; i++) {
            seedAssets[assets.length + i] = stableCoins[i];
            seedCategories[assets.length + i] = STABLE_CAT;
        }
        guard.initialize(seedAssets, seedCategories, allProtocols_, categories);
        vm.stopPrank();

        for (uint256 i = 0; i < assets.length; i++) {
            assertTrue(guard.isAssetRegistered(assets[i]), "seeded asset missing");
        }
        for (uint256 i = 0; i < stableCoins.length; i++) {
            assertTrue(
                (guard.isAssetRegistered(stableCoins[i]) && guard.assetCategory(stableCoins[i]) == STABLE_CAT),
                "seeded stable coin missing"
            );
        }
        assertTrue(guard.isProtocolRegistered(lendingProtocol));
        assertTrue(guard.isProtocolRegistered(stakingProtocol));
        assertTrue(guard.isProtocolRegistered(ammProtocol));
        assertTrue(guard.isProtocolRegistered(intentProtocol));
        assertEq(guard.protocolCategory(lendingProtocol), LENDING_ID);
        assertEq(guard.protocolCategory(stakingProtocol), STAKING_ID);
        assertEq(guard.protocolCategory(ammProtocol), AMM_ID);
        assertEq(guard.protocolCategory(intentProtocol), INTENT_ID);
    }

    function test_DefaultAdminTransferDelay() public view {
        assertEq(bittyGuard.defaultAdminDelay(), 7 days);
        assertEq(bittyGuard.owner(), deployAdmin);
    }

    function test_CannotGrantDefaultAdminRoleDirectly() public {
        address newAdmin = makeAddr("newAdmin");
        bytes32 defaultAdminRole = bittyGuard.DEFAULT_ADMIN_ROLE();
        vm.startPrank(deployAdmin);
        vm.expectRevert();
        bittyGuard.grantRole(defaultAdminRole, newAdmin);
        vm.stopPrank();
    }

    function test_DefaultAdminTransferSucceedsAfterDelay() public {
        address newAdmin = makeAddr("newAdmin");
        vm.prank(deployAdmin);
        bittyGuard.beginDefaultAdminTransfer(newAdmin);

        (, uint48 schedule) = bittyGuard.pendingDefaultAdmin();
        vm.warp(schedule + 1);
        vm.prank(newAdmin);
        bittyGuard.acceptDefaultAdminTransfer();

        assertEq(bittyGuard.owner(), newAdmin);
        assertTrue(bittyGuard.hasRole(bittyGuard.DEFAULT_ADMIN_ROLE(), newAdmin));
        assertFalse(bittyGuard.hasRole(bittyGuard.DEFAULT_ADMIN_ROLE(), deployAdmin));
    }

    function test_DefaultAdminTransferCanBeCancelled() public {
        address newAdmin = makeAddr("newAdmin");
        vm.prank(deployAdmin);
        bittyGuard.beginDefaultAdminTransfer(newAdmin);

        vm.prank(deployAdmin);
        bittyGuard.cancelDefaultAdminTransfer();

        vm.warp(block.timestamp + 7 days);
        vm.prank(newAdmin);
        vm.expectRevert();
        bittyGuard.acceptDefaultAdminTransfer();

        assertEq(bittyGuard.owner(), deployAdmin);
    }

    function test_AddProtocol_acceptsEachCategory() public {
        _addProtocols(lendingProtocols, LENDING_ID);
        _addProtocols(stakingProtocols, STAKING_ID);
        _addProtocols(ammProtocols, AMM_ID);
        _addProtocols(intentProtocols, INTENT_ID);

        assertTrue(bittyGuard.isProtocolRegistered(lendingProtocol));
        assertTrue(bittyGuard.isProtocolRegistered(stakingProtocol));
        assertTrue(bittyGuard.isProtocolRegistered(ammProtocol));
        assertTrue(bittyGuard.isProtocolRegistered(intentProtocol));
    }

    function test_IsProtocolRegistered_falseAfterDeprecate() public {
        _addProtocols(lendingProtocols, LENDING_ID);
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(lendingProtocols);
        assertFalse(bittyGuard.isProtocolRegistered(lendingProtocol));
    }

    function test_AddProtocols_oneRoleCoversEveryCategory() public {
        address manager = makeAddr("protocolManager");
        bytes32 role = bittyGuard.PROTOCOL_MANAGER_ROLE();
        vm.prank(deployAdmin);
        bittyGuard.grantRole(role, manager);

        address[] memory mixed = new address[](2);
        mixed[0] = lendingProtocol;
        mixed[1] = stakingProtocol;
        uint8[] memory categories = new uint8[](2);
        categories[0] = LENDING_ID;
        categories[1] = STAKING_ID;

        vm.prank(manager);
        bittyGuard.addProtocols(mixed, categories);

        assertTrue(bittyGuard.isProtocolRegistered(lendingProtocol));
        assertTrue(bittyGuard.isProtocolRegistered(stakingProtocol));
        assertEq(bittyGuard.protocolCategory(lendingProtocol), LENDING_ID);
        assertEq(bittyGuard.protocolCategory(stakingProtocol), STAKING_ID);
    }

    function test_DeprecatedProtocolIsNoLongerRegistered() public {
        _addProtocols(lendingProtocols, LENDING_ID);
        _addProtocols(stakingProtocols, STAKING_ID);
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(lendingProtocols);

        address[] memory remaining = new address[](1);
        remaining[0] = stakingProtocol;
        _assertProtocolsAre(remaining);
        assertTrue(bittyGuard.isProtocolDeprecated(lendingProtocol));
        assertFalse(bittyGuard.isProtocolDeprecated(stakingProtocol));
        assertEq(bittyGuard.protocolCategory(lendingProtocol), LENDING_ID);
    }

    function test_AddProtocols_reRegisteringClearsDeprecation() public {
        _addProtocols(lendingProtocols, LENDING_ID);
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(lendingProtocols);
        _addProtocols(lendingProtocols, LENDING_ID);
        assertFalse(bittyGuard.isProtocolDeprecated(lendingProtocol));
        assertTrue(bittyGuard.isProtocolRegistered(lendingProtocol));
    }

    function test_AddProtocols_recordsSuppliedCategory() public {
        _addProtocols(lendingProtocols, LENDING_ID);
        _addProtocols(stakingProtocols, STAKING_ID);
        _addProtocols(ammProtocols, AMM_ID);
        _addProtocols(intentProtocols, INTENT_ID);

        assertEq(bittyGuard.protocolCategory(lendingProtocol), LENDING_ID);
        assertEq(bittyGuard.protocolCategory(stakingProtocol), STAKING_ID);
        assertEq(bittyGuard.protocolCategory(ammProtocol), AMM_ID);
        assertEq(bittyGuard.protocolCategory(intentProtocol), INTENT_ID);
    }

    function test_ProtocolCategory_isZeroForUnregistered() public {
        assertEq(bittyGuard.protocolCategory(makeAddr("nobody")), 0);
    }

    function test_TheTwoRolesDoNotReachEachOther() public {
        address assetOnly = makeAddr("assetOnly");
        address protocolOnly = makeAddr("protocolOnly");
        bytes32 assetRole = bittyGuard.ASSET_MANAGER_ROLE();
        bytes32 protocolRole = bittyGuard.PROTOCOL_MANAGER_ROLE();
        vm.startPrank(deployAdmin);
        bittyGuard.grantRole(assetRole, assetOnly);
        bittyGuard.grantRole(protocolRole, protocolOnly);
        vm.stopPrank();

        vm.prank(assetOnly);
        vm.expectRevert();
        bittyGuard.addProtocols(lendingProtocols, _fillCategories(LENDING_ID, 1));

        vm.prank(protocolOnly);
        vm.expectRevert();
        bittyGuard.addAssets(assets, _cats(assets.length, CRYPTO_CAT));

        vm.prank(protocolOnly);
        bittyGuard.addProtocols(lendingProtocols, _fillCategories(LENDING_ID, 1));
        vm.prank(assetOnly);
        bittyGuard.addAssets(assets, _cats(assets.length, CRYPTO_CAT));
        assertTrue(bittyGuard.isProtocolRegistered(lendingProtocol));
        assertTrue(bittyGuard.isAssetRegistered(address(mockWETH)));
    }

    function test_AssetRoleCoversStableCoins() public {
        address assetOnly = makeAddr("assetOnlyForCoins");
        bytes32 assetRole = bittyGuard.ASSET_MANAGER_ROLE();
        vm.prank(deployAdmin);
        bittyGuard.grantRole(assetRole, assetOnly);

        vm.prank(assetOnly);
        bittyGuard.addAssets(stableCoins, _cats(stableCoins.length, STABLE_CAT));
        assertTrue(_isStable(address(mockUSDC)));

        vm.prank(assetOnly);
        bittyGuard.removeAssets(stableCoins);
        assertFalse(_isStable(address(mockUSDC)));
    }

    function test_DeprecateProtocols_worksWhenProtocolHasNoCode() public {
        _addProtocols(lendingProtocols, LENDING_ID);
        vm.etch(lendingProtocol, "");

        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(lendingProtocols);

        assertTrue(bittyGuard.isProtocolDeprecated(lendingProtocol));
        assertFalse(bittyGuard.isProtocolRegistered(lendingProtocol));
    }

    function test_AddProtocols_revertsLengthMismatch() public {
        vm.prank(protocolOwner);
        vm.expectRevert(LengthMismatch.selector);
        bittyGuard.addProtocols(lendingProtocols, new uint8[](0));
    }

    function test_AddProtocols_skipsZeroAddressAndZeroCategory() public {
        address[] memory protocols = new address[](2);
        protocols[0] = address(0);
        protocols[1] = lendingProtocol;
        uint8[] memory categories = new uint8[](2);
        categories[0] = LENDING_ID;
        categories[1] = 0;

        vm.prank(protocolOwner);
        bittyGuard.addProtocols(protocols, categories);

        assertFalse(bittyGuard.isProtocolRegistered(address(0)));
        assertFalse(bittyGuard.isProtocolRegistered(lendingProtocol));
    }

    function test_AddAssets_emitsOncePerNewEntry() public {
        address[] memory one = new address[](1);
        one[0] = address(mockWETH);
        vm.expectEmit(true, false, false, true, address(bittyGuard));
        emit IBittyV1Guard.AssetAdded(address(mockWETH), CRYPTO_CAT);
        vm.prank(protocolOwner);
        bittyGuard.addAssets(one, _cats(one.length, CRYPTO_CAT));
    }

    function test_AddAssets_emitsNothingWhenAlreadyRegistered() public {
        address[] memory one = new address[](1);
        one[0] = address(mockWETH);
        vm.startPrank(protocolOwner);
        bittyGuard.addAssets(one, _cats(one.length, CRYPTO_CAT));
        vm.recordLogs();
        bittyGuard.addAssets(one, _cats(one.length, CRYPTO_CAT));
        vm.stopPrank();
        assertEq(vm.getRecordedLogs().length, 0, "re-adding emitted a log");
    }

    function test_RemoveAssets_emitsOnlyWhenSomethingWasUnlinked() public {
        address[] memory one = new address[](1);
        one[0] = address(mockWETH);
        vm.startPrank(protocolOwner);
        bittyGuard.addAssets(one, _cats(one.length, CRYPTO_CAT));
        vm.expectEmit(true, false, false, true, address(bittyGuard));
        emit IBittyV1Guard.AssetRemoved(address(mockWETH));
        bittyGuard.removeAssets(one);

        vm.recordLogs();
        bittyGuard.removeAssets(one);
        vm.stopPrank();
        assertEq(vm.getRecordedLogs().length, 0, "removing an absent asset emitted a log");
    }

    function test_StableCoinIsAnAssetCategory() public {
        address[] memory one = new address[](1);
        one[0] = address(mockUSDC);
        vm.startPrank(protocolOwner);
        vm.expectEmit(true, true, false, true, address(bittyGuard));
        emit IBittyV1Guard.AssetAdded(address(mockUSDC), STABLE_CAT);
        bittyGuard.addAssets(one, _cats(one.length, STABLE_CAT));
        assertTrue(_isStable(address(mockUSDC)));
        vm.expectEmit(true, false, false, true, address(bittyGuard));
        emit IBittyV1Guard.AssetRemoved(address(mockUSDC));
        bittyGuard.removeAssets(one);
        assertFalse(_isStable(address(mockUSDC)));
        vm.stopPrank();
    }

    function test_Protocol_eventsCarryCategoryOnAdd() public {
        vm.startPrank(protocolOwner);
        vm.expectEmit(true, true, false, true, address(bittyGuard));
        emit IBittyV1Guard.ProtocolAdded(lendingProtocol, LENDING_ID);
        bittyGuard.addProtocols(lendingProtocols, _fillCategories(LENDING_ID, 1));

        vm.expectEmit(true, false, false, true, address(bittyGuard));
        emit IBittyV1Guard.ProtocolDeprecated(lendingProtocol);
        bittyGuard.deprecateProtocols(lendingProtocols);
        vm.stopPrank();
    }

    function test_RemovingOneEntryLeavesTheOthers() public {
        address a = makeAddr("assetA");
        address b = makeAddr("assetB");
        address c = makeAddr("assetC");
        address[] memory three = new address[](3);
        three[0] = a;
        three[1] = b;
        three[2] = c;
        vm.startPrank(protocolOwner);
        bittyGuard.addAssets(three, _cats(three.length, CRYPTO_CAT));

        address[] memory middle = new address[](1);
        middle[0] = b;
        bittyGuard.removeAssets(middle);
        assertTrue(bittyGuard.isAssetRegistered(a));
        assertFalse(bittyGuard.isAssetRegistered(b));
        assertTrue(bittyGuard.isAssetRegistered(c));

        address[] memory tail = new address[](1);
        tail[0] = c;
        bittyGuard.removeAssets(tail);
        assertFalse(bittyGuard.isAssetRegistered(c));
        assertTrue(bittyGuard.isAssetRegistered(a));
        vm.stopPrank();
    }

    function test_EmptyingThenRefillingTheRegistry() public {
        address a = makeAddr("only");
        address[] memory one = new address[](1);
        one[0] = a;
        vm.startPrank(protocolOwner);
        bittyGuard.addAssets(one, _cats(one.length, CRYPTO_CAT));
        bittyGuard.removeAssets(one);
        assertFalse(bittyGuard.isAssetRegistered(a));
        bittyGuard.addAssets(one, _cats(one.length, CRYPTO_CAT));
        assertTrue(bittyGuard.isAssetRegistered(a));
        bittyGuard.removeAssets(one);
        assertFalse(bittyGuard.isAssetRegistered(a));
        vm.stopPrank();
    }

    function test_ZeroAddressIsNeverRegistered() public {
        address[] memory withZero = new address[](2);
        withZero[0] = address(0);
        withZero[1] = address(mockWETH);
        vm.prank(protocolOwner);
        bittyGuard.addAssets(withZero, _cats(withZero.length, CRYPTO_CAT));
        assertFalse(bittyGuard.isAssetRegistered(address(0)));
        assertTrue(bittyGuard.isAssetRegistered(address(mockWETH)));
    }

    function test_GetBittyV1GuardInitCode() public pure {
        bytes32 initCodeHash = keccak256(type(BittyV1Guard).creationCode);
        console.log("INIT_CODE_HASH");
        console.logBytes32(initCodeHash);
    }

    function _addProtocols(address[] memory protocols, uint8 category) internal {
        vm.prank(protocolOwner);
        bittyGuard.addProtocols(protocols, _fillCategories(category, protocols.length));
    }

    function _fillCategories(uint8 category, uint256 length) internal pure returns (uint8[] memory categories) {
        categories = new uint8[](length);
        for (uint256 i = 0; i < length; i++) {
            categories[i] = category;
        }
    }

    uint8 internal constant CRYPTO_CAT = 2;
    uint8 internal constant STABLE_CAT = 1;

    /// @dev Same category for every entry; the tests care about membership, not the taxonomy.
    function _cats(uint256 n, uint8 category) internal pure returns (uint8[] memory out) {
        out = new uint8[](n);
        for (uint256 i = 0; i < n; i++) {
            out[i] = category;
        }
    }

    function _contains(address[] memory list, address item) internal pure returns (bool) {
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == item) return true;
        }
        return false;
    }

    function _assertAssetsAre(address[] memory expected) internal view {
        for (uint256 i = 0; i < assets.length; i++) {
            assertEq(bittyGuard.isAssetRegistered(assets[i]), _contains(expected, assets[i]), "asset membership");
        }
        for (uint256 i = 0; i < expected.length; i++) {
            assertTrue(bittyGuard.isAssetRegistered(expected[i]), "expected asset missing");
        }
    }

    /// @dev A stable coin is just an asset carrying STABLE_CAT, so membership is a category read.
    function _assertStableCoinsAre(address[] memory expected) internal view {
        for (uint256 i = 0; i < stableCoins.length; i++) {
            assertEq(_isStable(stableCoins[i]), _contains(expected, stableCoins[i]), "stable coin membership");
        }
        for (uint256 i = 0; i < expected.length; i++) {
            assertTrue(_isStable(expected[i]), "expected stable coin missing");
        }
    }

    function _isStable(address token) internal view returns (bool) {
        return bittyGuard.isAssetRegistered(token) && bittyGuard.assetCategory(token) == STABLE_CAT;
    }

    function _assertProtocolsAre(address[] memory expected) internal view {
        address[4][4] memory universe =
            [_pad(lendingProtocols), _pad(stakingProtocols), _pad(ammProtocols), _pad(intentProtocols)];
        for (uint256 c = 0; c < universe.length; c++) {
            for (uint256 i = 0; i < universe[c].length; i++) {
                address p = universe[c][i];
                if (p == address(0)) continue;
                assertEq(bittyGuard.isProtocolRegistered(p), _contains(expected, p), "protocol membership");
            }
        }
        for (uint256 i = 0; i < expected.length; i++) {
            assertTrue(bittyGuard.isProtocolRegistered(expected[i]), "expected protocol missing");
        }
    }

    function _pad(address[] storage list) internal view returns (address[4] memory out) {
        for (uint256 i = 0; i < list.length && i < 4; i++) {
            out[i] = list[i];
        }
    }

    /**
     * @notice A deprecated protocol leaves {getProtocols} but stays in {getAllProtocols}.
     * @dev The distinction is load-bearing, not cosmetic. Deprecation is exit-only: vaults keep
     *      positions in the protocol, so a caller identifying those positions - recognising a
     *      position NFT, say - must still be able to see it. Enumerating only the active set would
     *      make a deprecated protocol's NFT indistinguishable from a stray token.
     */
    function test_DeprecatedProtocolMovesFromActiveListToDeprecatedList() public {
        vm.startPrank(protocolOwner);
        bittyGuard.addProtocols(lendingProtocols, _cats(lendingProtocols.length, LENDING_ID));
        bittyGuard.deprecateProtocols(lendingProtocols);
        vm.stopPrank();

        assertFalse(bittyGuard.isProtocolRegistered(lendingProtocol), "still reads as registered");
        assertTrue(bittyGuard.isProtocolDeprecated(lendingProtocol));

        address[] memory active = bittyGuard.getProtocols();
        for (uint256 i = 0; i < active.length; i++) {
            assertTrue(active[i] != lendingProtocol, "deprecated protocol still in the active list");
        }

        bool found;
        address[] memory deprecated = bittyGuard.getDeprecatedProtocols();
        for (uint256 i = 0; i < deprecated.length; i++) {
            if (deprecated[i] == lendingProtocol) found = true;
        }
        assertTrue(found, "deprecated protocol missing from the deprecated list");
    }

    /// @dev Deprecating twice is not a no-op that silently succeeds - the entry is already gone.
    function test_DeprecateTwiceReverts() public {
        vm.startPrank(protocolOwner);
        bittyGuard.addProtocols(lendingProtocols, _cats(lendingProtocols.length, LENDING_ID));
        bittyGuard.deprecateProtocols(lendingProtocols);
        vm.expectRevert(abi.encodeWithSelector(NotRegisteredProtocol.selector, lendingProtocol));
        bittyGuard.deprecateProtocols(lendingProtocols);
        vm.stopPrank();
    }
}
