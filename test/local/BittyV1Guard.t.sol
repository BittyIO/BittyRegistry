// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import "forge-std/console.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {BittyV1Guard} from "../../src/BittyV1Guard.sol";
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";

contract BittyV1GuardTest is Test {
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
        // BittyV1Guard can only be deployed by tx.origin == DEPLOYER, which becomes its admin.
        deployAdmin = 0x12EE2de7BF086388B1D560eb95e7191Edfab9823;
        vm.prank(deployAdmin, deployAdmin);
        bittyGuard = new BittyV1Guard();
        vm.startPrank(deployAdmin);
        bittyGuard.grantRole(bittyGuard.ASSET_MANAGER_ROLE(), protocolOwner);
        bittyGuard.grantRole(bittyGuard.STABLE_COIN_MANAGER_ROLE(), protocolOwner);
        bittyGuard.grantRole(bittyGuard.LENDING_MANAGER_ROLE(), protocolOwner);
        bittyGuard.grantRole(bittyGuard.STAKING_MANAGER_ROLE(), protocolOwner);
        bittyGuard.grantRole(bittyGuard.AMM_MANAGER_ROLE(), protocolOwner);
        bittyGuard.grantRole(bittyGuard.INTENT_MANAGER_ROLE(), protocolOwner);
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
        vm.expectRevert(BittyV1Guard.NotDeployer.selector);
        new BittyV1Guard();

        address deployer = bittyGuard.DEPLOYER();
        vm.prank(deployer, deployer);
        BittyV1Guard g = new BittyV1Guard();
        assertTrue(g.hasRole(g.DEFAULT_ADMIN_ROLE(), deployer));
        assertFalse(g.hasRole(g.DEFAULT_ADMIN_ROLE(), randomDeployer));
    }

    function test_AddRegisteredAssets() public {
        vm.prank(protocolOwner);
        bittyGuard.addAssets(assets);
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
        bittyGuard.addStableCoins(stableCoins);
        assertTrue(bittyGuard.isStableCoinRegistered(address(mockUSDT)));
        assertTrue(bittyGuard.isStableCoinRegistered(address(mockUSDC)));
    }

    function test_RemoveStableCoins() public {
        vm.prank(protocolOwner);
        bittyGuard.removeStableCoins(stableCoins);
        assertFalse(bittyGuard.isStableCoinRegistered(address(mockUSDT)));
        assertFalse(bittyGuard.isStableCoinRegistered(address(mockUSDC)));
    }

    function test_AddLendingProtocols() public {
        vm.prank(protocolOwner);
        bittyGuard.addLendingProtocols(lendingProtocols);
        assertTrue(bittyGuard.isLendingProtocolRegistered(lendingProtocol));
    }

    function test_DeprecateLendingProtocols() public {
        vm.prank(protocolOwner);
        bittyGuard.addLendingProtocols(lendingProtocols);
        assertTrue(bittyGuard.isLendingProtocolRegistered(lendingProtocol));
        vm.prank(protocolOwner);
        bittyGuard.deprecateLendingProtocols(lendingProtocols);
        assertFalse(bittyGuard.isLendingProtocolRegistered(lendingProtocol));
        assertTrue(bittyGuard.isLendingProtocolDeprecated(lendingProtocol));
        address[] memory active = bittyGuard.getLendingProtocols();
        assertEq(active.length, 0);
    }

    function test_DeprecateUnregistered_DoesNotSetDeprecatedFlag() public {
        address unreg = makeAddr("unregistered");
        address[] memory addrs = new address[](1);
        addrs[0] = unreg;

        vm.startPrank(protocolOwner);
        bittyGuard.deprecateLendingProtocols(addrs);
        bittyGuard.deprecateStakingProtocols(addrs);
        bittyGuard.deprecateAMMProtocols(addrs);
        bittyGuard.deprecateIntentProtocols(addrs);
        vm.stopPrank();

        assertFalse(bittyGuard.isLendingProtocolDeprecated(unreg));
        assertFalse(bittyGuard.isStakingProtocolDeprecated(unreg));
        assertFalse(bittyGuard.isAMMProtocolDeprecated(unreg));
        assertFalse(bittyGuard.isIntentProtocolDeprecated(unreg));
    }

    function test_AddStakingProtocols() public {
        vm.prank(protocolOwner);
        bittyGuard.addStakingProtocols(stakingProtocols);
        assertTrue(bittyGuard.isStakingProtocolRegistered(stakingProtocol));
        assertFalse(bittyGuard.isStakingProtocolDeprecated(stakingProtocol));
    }

    function test_DeprecateStakingProtocols() public {
        vm.prank(protocolOwner);
        bittyGuard.addStakingProtocols(stakingProtocols);
        vm.prank(protocolOwner);
        bittyGuard.deprecateStakingProtocols(stakingProtocols);
        assertFalse(bittyGuard.isStakingProtocolRegistered(stakingProtocol));
        assertTrue(bittyGuard.isStakingProtocolDeprecated(stakingProtocol));
        assertEq(bittyGuard.getStakingProtocols().length, 0);
    }

    function test_AddAMMProtocols() public {
        vm.prank(protocolOwner);
        bittyGuard.addAMMProtocols(ammProtocols);
        assertTrue(bittyGuard.isAMMProtocolRegistered(ammProtocol));
        assertFalse(bittyGuard.isAMMProtocolDeprecated(ammProtocol));
    }

    function test_DeprecateAMMProtocols() public {
        vm.prank(protocolOwner);
        bittyGuard.addAMMProtocols(ammProtocols);
        vm.prank(protocolOwner);
        bittyGuard.deprecateAMMProtocols(ammProtocols);
        assertFalse(bittyGuard.isAMMProtocolRegistered(ammProtocol));
        assertTrue(bittyGuard.isAMMProtocolDeprecated(ammProtocol));
        assertEq(bittyGuard.getAMMProtocols().length, 0);
    }

    function test_DeprecateAMMProtocolsAllowsAllDeprecated() public {
        address[] memory ammProtocolAddresses = new address[](1);
        ammProtocolAddresses[0] = ammProtocol;
        vm.prank(protocolOwner);
        bittyGuard.addAMMProtocols(ammProtocolAddresses);
        vm.prank(protocolOwner);
        bittyGuard.deprecateAMMProtocols(ammProtocolAddresses);
        assertFalse(bittyGuard.isAMMProtocolRegistered(ammProtocol));
        assertTrue(bittyGuard.isAMMProtocolDeprecated(ammProtocol));
    }

    function test_AddAMMProtocolsClearsDeprecatedFlag() public {
        vm.prank(protocolOwner);
        bittyGuard.addAMMProtocols(ammProtocols);
        vm.prank(protocolOwner);
        bittyGuard.deprecateAMMProtocols(ammProtocols);
        vm.prank(protocolOwner);
        bittyGuard.addAMMProtocols(ammProtocols);
        assertTrue(bittyGuard.isAMMProtocolRegistered(ammProtocol));
        assertFalse(bittyGuard.isAMMProtocolDeprecated(ammProtocol));
    }

    function test_AddRegisteredNeedToRemoveDeprecated() public {
        vm.prank(protocolOwner);
        bittyGuard.addLendingProtocols(lendingProtocols);
        assertTrue(bittyGuard.isLendingProtocolRegistered(lendingProtocol));
        vm.prank(protocolOwner);
        bittyGuard.deprecateLendingProtocols(lendingProtocols);
        assertFalse(bittyGuard.isLendingProtocolRegistered(lendingProtocol));
        assertTrue(bittyGuard.isLendingProtocolDeprecated(lendingProtocol));
        vm.prank(protocolOwner);
        bittyGuard.addLendingProtocols(lendingProtocols);
        assertTrue(bittyGuard.isLendingProtocolRegistered(lendingProtocol));
        assertFalse(bittyGuard.isLendingProtocolDeprecated(lendingProtocol));
    }

    function test_AddIntentProtocols() public {
        vm.prank(protocolOwner);
        bittyGuard.addIntentProtocols(intentProtocols);
        assertTrue(bittyGuard.isIntentProtocolRegistered(intentProtocol));
    }

    function test_DeprecateIntentProtocols() public {
        vm.prank(protocolOwner);
        bittyGuard.addIntentProtocols(intentProtocols);
        assertTrue(bittyGuard.isIntentProtocolRegistered(intentProtocol));
        vm.prank(protocolOwner);
        bittyGuard.deprecateIntentProtocols(intentProtocols);
        assertFalse(bittyGuard.isIntentProtocolRegistered(intentProtocol));
        assertTrue(bittyGuard.isIntentProtocolDeprecated(intentProtocol));
        assertEq(bittyGuard.getIntentProtocols().length, 0);
    }

    function test_AddIntentProtocolsClearsDeprecatedFlag() public {
        vm.prank(protocolOwner);
        bittyGuard.addIntentProtocols(intentProtocols);
        assertTrue(bittyGuard.isIntentProtocolRegistered(intentProtocol));
        assertFalse(bittyGuard.isIntentProtocolDeprecated(intentProtocol));
        vm.prank(protocolOwner);
        bittyGuard.deprecateIntentProtocols(intentProtocols);
        assertFalse(bittyGuard.isIntentProtocolRegistered(intentProtocol));
        assertTrue(bittyGuard.isIntentProtocolDeprecated(intentProtocol));
        vm.prank(protocolOwner);
        bittyGuard.addIntentProtocols(intentProtocols);
        assertTrue(bittyGuard.isIntentProtocolRegistered(intentProtocol));
        assertFalse(bittyGuard.isIntentProtocolDeprecated(intentProtocol));
    }

    function test_GetAssets() public {
        vm.prank(protocolOwner);
        bittyGuard.addAssets(assets);
        _assertSameMembers(bittyGuard.getAssets(), assets);
    }

    function test_GetAssetsAfterRemove() public {
        vm.prank(protocolOwner);
        bittyGuard.addAssets(assets);
        address[] memory toRemove = new address[](1);
        toRemove[0] = address(mockWETH);
        vm.prank(protocolOwner);
        bittyGuard.removeAssets(toRemove);
        address[] memory expected = new address[](1);
        expected[0] = address(mockWBTC);
        _assertSameMembers(bittyGuard.getAssets(), expected);
    }

    function test_GetStableCoins() public {
        vm.prank(protocolOwner);
        bittyGuard.addStableCoins(stableCoins);
        _assertSameMembers(bittyGuard.getStableCoins(), stableCoins);
    }

    function test_GetStableCoinsAfterRemove() public {
        vm.prank(protocolOwner);
        bittyGuard.addStableCoins(stableCoins);
        address[] memory toRemove = new address[](1);
        toRemove[0] = address(mockUSDT);
        vm.prank(protocolOwner);
        bittyGuard.removeStableCoins(toRemove);
        address[] memory expected = new address[](1);
        expected[0] = address(mockUSDC);
        _assertSameMembers(bittyGuard.getStableCoins(), expected);
    }

    function test_GetAMMProtocols() public {
        vm.prank(protocolOwner);
        bittyGuard.addAMMProtocols(ammProtocols);
        _assertSameMembers(bittyGuard.getAMMProtocols(), ammProtocols);
    }

    function test_GetAMMProtocolsAfterPartialDeprecate() public {
        address extraAmm = makeAddr("extraAmm");
        address[] memory twoAmms = new address[](2);
        twoAmms[0] = ammProtocol;
        twoAmms[1] = extraAmm;
        vm.prank(protocolOwner);
        bittyGuard.addAMMProtocols(twoAmms);
        address[] memory toDeprecate = new address[](1);
        toDeprecate[0] = extraAmm;
        vm.prank(protocolOwner);
        bittyGuard.deprecateAMMProtocols(toDeprecate);
        address[] memory expected = new address[](1);
        expected[0] = ammProtocol;
        _assertSameMembers(bittyGuard.getAMMProtocols(), expected);
        assertTrue(bittyGuard.isAMMProtocolDeprecated(extraAmm));
        assertFalse(bittyGuard.isAMMProtocolRegistered(extraAmm));
    }

    function test_GetLendingProtocols() public {
        vm.prank(protocolOwner);
        bittyGuard.addLendingProtocols(lendingProtocols);
        _assertSameMembers(bittyGuard.getLendingProtocols(), lendingProtocols);
    }

    function test_GetLendingProtocolsExcludesDeprecated() public {
        address lendingProtocolB = makeAddr("lendingProtocolB");
        address[] memory twoProtocols = new address[](2);
        twoProtocols[0] = lendingProtocol;
        twoProtocols[1] = lendingProtocolB;
        vm.prank(protocolOwner);
        bittyGuard.addLendingProtocols(twoProtocols);
        address[] memory toDeprecate = new address[](1);
        toDeprecate[0] = lendingProtocol;
        vm.prank(protocolOwner);
        bittyGuard.deprecateLendingProtocols(toDeprecate);
        address[] memory expected = new address[](1);
        expected[0] = lendingProtocolB;
        _assertSameMembers(bittyGuard.getLendingProtocols(), expected);
        assertTrue(bittyGuard.isLendingProtocolDeprecated(lendingProtocol));
        assertFalse(bittyGuard.isLendingProtocolRegistered(lendingProtocol));
        assertTrue(bittyGuard.isLendingProtocolRegistered(lendingProtocolB));
    }

    function test_GetLendingProtocolsReaddAfterDeprecate() public {
        vm.prank(protocolOwner);
        bittyGuard.addLendingProtocols(lendingProtocols);
        vm.prank(protocolOwner);
        bittyGuard.deprecateLendingProtocols(lendingProtocols);
        assertEq(bittyGuard.getLendingProtocols().length, 0);
        vm.prank(protocolOwner);
        bittyGuard.addLendingProtocols(lendingProtocols);
        _assertSameMembers(bittyGuard.getLendingProtocols(), lendingProtocols);
    }

    function test_GetStakingProtocols() public {
        vm.prank(protocolOwner);
        bittyGuard.addStakingProtocols(stakingProtocols);
        _assertSameMembers(bittyGuard.getStakingProtocols(), stakingProtocols);
    }

    function test_GetStakingProtocolsExcludesDeprecated() public {
        address stakingProtocolB = makeAddr("stakingProtocolB");
        address[] memory twoProtocols = new address[](2);
        twoProtocols[0] = stakingProtocol;
        twoProtocols[1] = stakingProtocolB;
        vm.prank(protocolOwner);
        bittyGuard.addStakingProtocols(twoProtocols);
        address[] memory toDeprecate = new address[](1);
        toDeprecate[0] = stakingProtocol;
        vm.prank(protocolOwner);
        bittyGuard.deprecateStakingProtocols(toDeprecate);
        address[] memory expected = new address[](1);
        expected[0] = stakingProtocolB;
        _assertSameMembers(bittyGuard.getStakingProtocols(), expected);
    }

    function test_GetIntentProtocols() public {
        vm.prank(protocolOwner);
        bittyGuard.addIntentProtocols(intentProtocols);
        _assertSameMembers(bittyGuard.getIntentProtocols(), intentProtocols);
    }

    function test_GetIntentProtocolsExcludesDeprecated() public {
        address intentProtocolB = makeAddr("intentProtocolB");
        address[] memory twoProtocols = new address[](2);
        twoProtocols[0] = intentProtocol;
        twoProtocols[1] = intentProtocolB;
        vm.prank(protocolOwner);
        bittyGuard.addIntentProtocols(twoProtocols);
        address[] memory toDeprecate = new address[](1);
        toDeprecate[0] = intentProtocol;
        vm.prank(protocolOwner);
        bittyGuard.deprecateIntentProtocols(toDeprecate);
        address[] memory expected = new address[](1);
        expected[0] = intentProtocolB;
        _assertSameMembers(bittyGuard.getIntentProtocols(), expected);
    }

    function test_GetIntentProtocolsReaddAfterDeprecate() public {
        vm.prank(protocolOwner);
        bittyGuard.addIntentProtocols(intentProtocols);
        vm.prank(protocolOwner);
        bittyGuard.deprecateIntentProtocols(intentProtocols);
        assertEq(bittyGuard.getIntentProtocols().length, 0);
        vm.prank(protocolOwner);
        bittyGuard.addIntentProtocols(intentProtocols);
        _assertSameMembers(bittyGuard.getIntentProtocols(), intentProtocols);
    }

    function test_InitializePopulatesGetters() public {
        vm.startPrank(deployAdmin, deployAdmin);
        BittyV1Guard guard = new BittyV1Guard();
        guard.initialize(assets, stableCoins, lendingProtocols, stakingProtocols, ammProtocols, intentProtocols);
        vm.stopPrank();
        _assertSameMembers(guard.getAssets(), assets);
        _assertSameMembers(guard.getStableCoins(), stableCoins);
        _assertSameMembers(guard.getLendingProtocols(), lendingProtocols);
        _assertSameMembers(guard.getStakingProtocols(), stakingProtocols);
        _assertSameMembers(guard.getAMMProtocols(), ammProtocols);
        _assertSameMembers(guard.getIntentProtocols(), intentProtocols);
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

    function _assertSameMembers(address[] memory actual, address[] memory expected) internal pure {
        assertEq(actual.length, expected.length, "array length mismatch");
        for (uint256 i = 0; i < expected.length; i++) {
            bool found;
            for (uint256 j = 0; j < actual.length; j++) {
                if (actual[j] == expected[i]) {
                    found = true;
                    break;
                }
            }
            assertTrue(found, "expected address missing from result");
        }
    }

    function test_GetBittyV1GuardInitCode() public pure {
        bytes32 initCodeHash = keccak256(type(BittyV1Guard).creationCode);
        console.log("INIT_CODE_HASH");
        console.logBytes32(initCodeHash);
    }
}
