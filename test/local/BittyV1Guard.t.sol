// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import "forge-std/console.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {BittyV1Guard} from "../../src/BittyV1Guard.sol";
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";

/**
 * @notice A protocol that declares exactly one category, so the guard will admit it to that one.
 * @dev The guard now verifies a protocol's category via ERC-165 before registering it, so fixtures
 *      can no longer be bare addresses — a code-less address answers nothing and is rejected.
 */
contract MockCategoryProtocol {
    bytes4 private immutable _categoryId;

    constructor(bytes4 categoryId) {
        _categoryId = categoryId;
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return interfaceId == _categoryId || interfaceId == 0x01ffc9a7;
    }
}

/// @dev Declares two categories, which the guard must refuse: see {test_AddProtocols_rejectsAmbiguous}.
contract MockDualCategoryProtocol {
    bytes4 private immutable _a;
    bytes4 private immutable _b;

    constructor(bytes4 a, bytes4 b) {
        _a = a;
        _b = b;
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return interfaceId == _a || interfaceId == _b || interfaceId == 0x01ffc9a7;
    }
}

contract BittyV1GuardTest is Test {
    bytes4 internal constant LENDING_ID = 0xb9f16a0c;
    bytes4 internal constant STAKING_ID = 0xc8ada217;
    bytes4 internal constant AMM_ID = 0x932722bd;
    bytes4 internal constant INTENT_ID = 0x1626ba7e;

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
        ammProtocol = _protocol("ammProtocol", AMM_ID);
        lendingProtocol = _protocol("lendingProtocol", LENDING_ID);
        stakingProtocol = _protocol("stakingProtocol", STAKING_ID);
        intentProtocol = _protocol("intentProtocol", INTENT_ID);
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
        bittyGuard.addProtocols(lendingProtocols);
        assertTrue(bittyGuard.isProtocolRegistered(lendingProtocol));
    }

    function test_DeprecateLendingProtocols() public {
        vm.prank(protocolOwner);
        bittyGuard.addProtocols(lendingProtocols);
        assertTrue(bittyGuard.isProtocolRegistered(lendingProtocol));
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(lendingProtocols);
        assertFalse(bittyGuard.isProtocolRegistered(lendingProtocol));
        assertTrue(bittyGuard.isProtocolDeprecated(lendingProtocol));
        address[] memory active = bittyGuard.getProtocols();
        assertEq(active.length, 0);
    }

    function test_DeprecateUnregistered_DoesNotSetDeprecatedFlag() public {
        address unreg = makeAddr("unregistered");
        address[] memory addrs = new address[](1);
        addrs[0] = unreg;

        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(addrs);

        // Skipped, not marked: an address with no recorded category was never registered, so there
        // is nothing to deprecate and no false history to leave behind.
        assertFalse(bittyGuard.isProtocolDeprecated(unreg));
        assertEq(bittyGuard.protocolCategory(unreg), bytes4(0));
    }

    function test_AddStakingProtocols() public {
        vm.prank(protocolOwner);
        bittyGuard.addProtocols(stakingProtocols);
        assertTrue(bittyGuard.isProtocolRegistered(stakingProtocol));
        assertFalse(bittyGuard.isProtocolDeprecated(stakingProtocol));
    }

    function test_DeprecateStakingProtocols() public {
        vm.prank(protocolOwner);
        bittyGuard.addProtocols(stakingProtocols);
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(stakingProtocols);
        assertFalse(bittyGuard.isProtocolRegistered(stakingProtocol));
        assertTrue(bittyGuard.isProtocolDeprecated(stakingProtocol));
        assertEq(bittyGuard.getProtocols().length, 0);
    }

    function test_AddAMMProtocols() public {
        vm.prank(protocolOwner);
        bittyGuard.addProtocols(ammProtocols);
        assertTrue(bittyGuard.isProtocolRegistered(ammProtocol));
        assertFalse(bittyGuard.isProtocolDeprecated(ammProtocol));
    }

    function test_DeprecateAMMProtocols() public {
        vm.prank(protocolOwner);
        bittyGuard.addProtocols(ammProtocols);
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(ammProtocols);
        assertFalse(bittyGuard.isProtocolRegistered(ammProtocol));
        assertTrue(bittyGuard.isProtocolDeprecated(ammProtocol));
        assertEq(bittyGuard.getProtocols().length, 0);
    }

    function test_DeprecateAMMProtocolsAllowsAllDeprecated() public {
        address[] memory ammProtocolAddresses = new address[](1);
        ammProtocolAddresses[0] = ammProtocol;
        vm.prank(protocolOwner);
        bittyGuard.addProtocols(ammProtocolAddresses);
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(ammProtocolAddresses);
        assertFalse(bittyGuard.isProtocolRegistered(ammProtocol));
        assertTrue(bittyGuard.isProtocolDeprecated(ammProtocol));
    }

    function test_AddAMMProtocolsClearsDeprecatedFlag() public {
        vm.prank(protocolOwner);
        bittyGuard.addProtocols(ammProtocols);
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(ammProtocols);
        vm.prank(protocolOwner);
        bittyGuard.addProtocols(ammProtocols);
        assertTrue(bittyGuard.isProtocolRegistered(ammProtocol));
        assertFalse(bittyGuard.isProtocolDeprecated(ammProtocol));
    }

    function test_AddRegisteredNeedToRemoveDeprecated() public {
        vm.prank(protocolOwner);
        bittyGuard.addProtocols(lendingProtocols);
        assertTrue(bittyGuard.isProtocolRegistered(lendingProtocol));
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(lendingProtocols);
        assertFalse(bittyGuard.isProtocolRegistered(lendingProtocol));
        assertTrue(bittyGuard.isProtocolDeprecated(lendingProtocol));
        vm.prank(protocolOwner);
        bittyGuard.addProtocols(lendingProtocols);
        assertTrue(bittyGuard.isProtocolRegistered(lendingProtocol));
        assertFalse(bittyGuard.isProtocolDeprecated(lendingProtocol));
    }

    function test_AddIntentProtocols() public {
        vm.prank(protocolOwner);
        bittyGuard.addProtocols(intentProtocols);
        assertTrue(bittyGuard.isProtocolRegistered(intentProtocol));
    }

    function test_DeprecateIntentProtocols() public {
        vm.prank(protocolOwner);
        bittyGuard.addProtocols(intentProtocols);
        assertTrue(bittyGuard.isProtocolRegistered(intentProtocol));
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(intentProtocols);
        assertFalse(bittyGuard.isProtocolRegistered(intentProtocol));
        assertTrue(bittyGuard.isProtocolDeprecated(intentProtocol));
        assertEq(bittyGuard.getProtocols().length, 0);
    }

    function test_AddIntentProtocolsClearsDeprecatedFlag() public {
        vm.prank(protocolOwner);
        bittyGuard.addProtocols(intentProtocols);
        assertTrue(bittyGuard.isProtocolRegistered(intentProtocol));
        assertFalse(bittyGuard.isProtocolDeprecated(intentProtocol));
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(intentProtocols);
        assertFalse(bittyGuard.isProtocolRegistered(intentProtocol));
        assertTrue(bittyGuard.isProtocolDeprecated(intentProtocol));
        vm.prank(protocolOwner);
        bittyGuard.addProtocols(intentProtocols);
        assertTrue(bittyGuard.isProtocolRegistered(intentProtocol));
        assertFalse(bittyGuard.isProtocolDeprecated(intentProtocol));
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
        bittyGuard.addProtocols(ammProtocols);
        _assertSameMembers(bittyGuard.getProtocols(), ammProtocols);
    }

    function test_GetAMMProtocolsAfterPartialDeprecate() public {
        address extraAmm = _protocol("extraAmm", AMM_ID);
        address[] memory twoAmms = new address[](2);
        twoAmms[0] = ammProtocol;
        twoAmms[1] = extraAmm;
        vm.prank(protocolOwner);
        bittyGuard.addProtocols(twoAmms);
        address[] memory toDeprecate = new address[](1);
        toDeprecate[0] = extraAmm;
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(toDeprecate);
        address[] memory expected = new address[](1);
        expected[0] = ammProtocol;
        _assertSameMembers(bittyGuard.getProtocols(), expected);
        assertTrue(bittyGuard.isProtocolDeprecated(extraAmm));
        assertFalse(bittyGuard.isProtocolRegistered(extraAmm));
    }

    function test_GetLendingProtocols() public {
        vm.prank(protocolOwner);
        bittyGuard.addProtocols(lendingProtocols);
        _assertSameMembers(bittyGuard.getProtocols(), lendingProtocols);
    }

    function test_GetLendingProtocolsExcludesDeprecated() public {
        address lendingProtocolB = _protocol("lendingProtocolB", LENDING_ID);
        address[] memory twoProtocols = new address[](2);
        twoProtocols[0] = lendingProtocol;
        twoProtocols[1] = lendingProtocolB;
        vm.prank(protocolOwner);
        bittyGuard.addProtocols(twoProtocols);
        address[] memory toDeprecate = new address[](1);
        toDeprecate[0] = lendingProtocol;
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(toDeprecate);
        address[] memory expected = new address[](1);
        expected[0] = lendingProtocolB;
        _assertSameMembers(bittyGuard.getProtocols(), expected);
        assertTrue(bittyGuard.isProtocolDeprecated(lendingProtocol));
        assertFalse(bittyGuard.isProtocolRegistered(lendingProtocol));
        assertTrue(bittyGuard.isProtocolRegistered(lendingProtocolB));
    }

    function test_GetLendingProtocolsReaddAfterDeprecate() public {
        vm.prank(protocolOwner);
        bittyGuard.addProtocols(lendingProtocols);
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(lendingProtocols);
        assertEq(bittyGuard.getProtocols().length, 0);
        vm.prank(protocolOwner);
        bittyGuard.addProtocols(lendingProtocols);
        _assertSameMembers(bittyGuard.getProtocols(), lendingProtocols);
    }

    function test_GetStakingProtocols() public {
        vm.prank(protocolOwner);
        bittyGuard.addProtocols(stakingProtocols);
        _assertSameMembers(bittyGuard.getProtocols(), stakingProtocols);
    }

    function test_GetStakingProtocolsExcludesDeprecated() public {
        address stakingProtocolB = _protocol("stakingProtocolB", STAKING_ID);
        address[] memory twoProtocols = new address[](2);
        twoProtocols[0] = stakingProtocol;
        twoProtocols[1] = stakingProtocolB;
        vm.prank(protocolOwner);
        bittyGuard.addProtocols(twoProtocols);
        address[] memory toDeprecate = new address[](1);
        toDeprecate[0] = stakingProtocol;
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(toDeprecate);
        address[] memory expected = new address[](1);
        expected[0] = stakingProtocolB;
        _assertSameMembers(bittyGuard.getProtocols(), expected);
    }

    function test_GetIntentProtocols() public {
        vm.prank(protocolOwner);
        bittyGuard.addProtocols(intentProtocols);
        _assertSameMembers(bittyGuard.getProtocols(), intentProtocols);
    }

    function test_GetIntentProtocolsExcludesDeprecated() public {
        address intentProtocolB = _protocol("intentProtocolB", INTENT_ID);
        address[] memory twoProtocols = new address[](2);
        twoProtocols[0] = intentProtocol;
        twoProtocols[1] = intentProtocolB;
        vm.prank(protocolOwner);
        bittyGuard.addProtocols(twoProtocols);
        address[] memory toDeprecate = new address[](1);
        toDeprecate[0] = intentProtocol;
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(toDeprecate);
        address[] memory expected = new address[](1);
        expected[0] = intentProtocolB;
        _assertSameMembers(bittyGuard.getProtocols(), expected);
    }

    function test_GetIntentProtocolsReaddAfterDeprecate() public {
        vm.prank(protocolOwner);
        bittyGuard.addProtocols(intentProtocols);
        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(intentProtocols);
        assertEq(bittyGuard.getProtocols().length, 0);
        vm.prank(protocolOwner);
        bittyGuard.addProtocols(intentProtocols);
        _assertSameMembers(bittyGuard.getProtocols(), intentProtocols);
    }

    function test_InitializePopulatesGetters() public {
        vm.startPrank(deployAdmin, deployAdmin);
        BittyV1Guard guard = new BittyV1Guard();
        guard.initialize(assets, stableCoins, lendingProtocols, stakingProtocols, ammProtocols, intentProtocols);
        vm.stopPrank();
        _assertSameMembers(guard.getAssets(), assets);
        _assertSameMembers(guard.getStableCoins(), stableCoins);

        // getProtocols is one flat list now, so the four seeded categories arrive together; the
        // category each one landed in is read back individually.
        address[] memory allProtocols = new address[](4);
        allProtocols[0] = lendingProtocol;
        allProtocols[1] = stakingProtocol;
        allProtocols[2] = ammProtocol;
        allProtocols[3] = intentProtocol;
        _assertSameMembers(guard.getProtocols(), allProtocols);

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

    /// @dev Deploys a category-declaring stand-in and labels it, so traces still read as a name.
    function _protocol(string memory label, bytes4 categoryId) internal returns (address addr) {
        addr = address(new MockCategoryProtocol(categoryId));
        vm.label(addr, label);
    }

    /// @dev An EOA answers nothing, so {ERC165Checker} reports false rather than bubbling a revert.
    function test_AddProtocol_rejectsAddressWithNoCode() public {
        address eoa = makeAddr("eoaNotAProtocol");
        address[] memory addrs = new address[](1);
        addrs[0] = eoa;

        vm.prank(protocolOwner);
        vm.expectRevert(abi.encodeWithSelector(BittyV1Guard.NotABittyProtocol.selector, eoa));
        bittyGuard.addProtocols(addrs);
    }

    /// @dev Each category gates on its own id, so a correct one still registers after a rejection.
    function test_AddProtocol_acceptsEachDeclaredCategory() public {
        vm.startPrank(protocolOwner);
        bittyGuard.addProtocols(lendingProtocols);
        bittyGuard.addProtocols(stakingProtocols);
        bittyGuard.addProtocols(ammProtocols);
        bittyGuard.addProtocols(intentProtocols);
        vm.stopPrank();

        assertTrue(bittyGuard.isProtocolRegistered(lendingProtocol));
        assertTrue(bittyGuard.isProtocolRegistered(stakingProtocol));
        assertTrue(bittyGuard.isProtocolRegistered(ammProtocol));
        assertTrue(bittyGuard.isProtocolRegistered(intentProtocol));
    }

    /// @dev Callers use this as a permission check, so an unknown category grants nothing.
    /// @dev Deprecating removes from the set, so the unified query must stop reporting it too.
    function test_IsProtocolRegistered_falseAfterDeprecate() public {
        vm.startPrank(protocolOwner);
        bittyGuard.addProtocols(lendingProtocols);
        assertTrue(bittyGuard.isProtocolRegistered(lendingProtocol));
        bittyGuard.deprecateProtocols(lendingProtocols);
        vm.stopPrank();
        assertFalse(bittyGuard.isProtocolRegistered(lendingProtocol));
    }

    /// @dev Reads stay total — a permission check for a category nobody defined grants nothing.
    /**
     * @notice Collapsing the four functions into one did NOT collapse the four roles.
     * @dev The category is now an argument, so it would be easy for one manager to reach every
     *      category through the single entry point. Authority still has to be per-category.
     */
    function test_AddProtocols_stillRequiresThatCategorysRole() public {
        address lendingOnlyManager = makeAddr("lendingOnlyManager");
        // Read the role BEFORE pranking: it is itself a call, and would otherwise consume the prank.
        bytes32 lendingRole = bittyGuard.LENDING_MANAGER_ROLE();
        vm.prank(deployAdmin);
        bittyGuard.grantRole(lendingRole, lendingOnlyManager);

        address staker = _protocol("aStaker", STAKING_ID);
        address[] memory addrs = new address[](1);
        addrs[0] = staker;

        vm.prank(lendingOnlyManager);
        vm.expectRevert();
        bittyGuard.addProtocols(addrs);

        // ...and the same caller can still act within the category it does hold.
        address[] memory lenders = new address[](1);
        lenders[0] = lendingProtocol;
        vm.prank(lendingOnlyManager);
        bittyGuard.addProtocols(lenders);
        assertTrue(bittyGuard.isProtocolRegistered(lendingProtocol));
    }

    /// @dev getProtocols reports the ACTIVE list, so a deprecated entry drops out of it.
    function test_GetProtocols_excludesDeprecated() public {
        vm.startPrank(protocolOwner);
        bittyGuard.addProtocols(lendingProtocols);
        bittyGuard.addProtocols(stakingProtocols);
        bittyGuard.deprecateProtocols(lendingProtocols);
        vm.stopPrank();

        address[] memory active = bittyGuard.getProtocols();
        assertEq(active.length, 1, "only the deprecated lender was dropped");
        assertEq(active[0], stakingProtocol, "the untouched protocol is what remains");
        assertTrue(bittyGuard.isProtocolDeprecated(lendingProtocol));
        assertFalse(bittyGuard.isProtocolDeprecated(stakingProtocol));
        // Deprecating does not erase what it WAS — that is what keeps the exit path answerable.
        assertEq(bittyGuard.protocolCategory(lendingProtocol), LENDING_ID);
    }

    /// @dev Re-listing a deprecated protocol is the deliberate act of bringing it back.
    function test_AddProtocols_reRegisteringClearsDeprecation() public {
        vm.startPrank(protocolOwner);
        bittyGuard.addProtocols(lendingProtocols);
        bittyGuard.deprecateProtocols(lendingProtocols);
        assertTrue(bittyGuard.isProtocolDeprecated(lendingProtocol));
        bittyGuard.addProtocols(lendingProtocols);
        vm.stopPrank();

        assertFalse(bittyGuard.isProtocolDeprecated(lendingProtocol));
        assertTrue(bittyGuard.isProtocolRegistered(lendingProtocol));
        assertEq(bittyGuard.getProtocols().length, 1);
    }

    /**
     * @notice The category is DISCOVERED, not supplied — and it is what the protocol declares.
     * @dev Nothing in the call names a category, so this is the whole contract between the guard and
     *      a protocol: register it, and the guard records what it says it is.
     */
    function test_AddProtocols_recordsTheDeclaredCategory() public {
        vm.startPrank(protocolOwner);
        bittyGuard.addProtocols(lendingProtocols);
        bittyGuard.addProtocols(stakingProtocols);
        bittyGuard.addProtocols(ammProtocols);
        bittyGuard.addProtocols(intentProtocols);
        vm.stopPrank();

        assertEq(bittyGuard.protocolCategory(lendingProtocol), LENDING_ID);
        assertEq(bittyGuard.protocolCategory(stakingProtocol), STAKING_ID);
        assertEq(bittyGuard.protocolCategory(ammProtocol), AMM_ID);
        assertEq(bittyGuard.protocolCategory(intentProtocol), INTENT_ID);
    }

    /// @dev An address never registered has no category, which is how callers tell it apart.
    function test_ProtocolCategory_isZeroForUnregistered() public {
        assertEq(bittyGuard.protocolCategory(makeAddr("nobody")), bytes4(0));
    }

    /**
     * @notice A protocol declaring two categories is refused outright.
     * @dev Not pedantry: it would be admissible by the manager of the cheaper category and then
     *      usable as the other, so accepting it would route around the split between manager roles
     *      rather than exercise it.
     */
    function test_AddProtocols_rejectsAmbiguousCategory() public {
        address dual = address(new MockDualCategoryProtocol(LENDING_ID, INTENT_ID));
        address[] memory addrs = new address[](1);
        addrs[0] = dual;

        vm.prank(protocolOwner);
        vm.expectRevert(abi.encodeWithSelector(BittyV1Guard.AmbiguousProtocolCategory.selector, dual));
        bittyGuard.addProtocols(addrs);

        assertFalse(bittyGuard.isProtocolRegistered(dual));
    }

    /**
     * @notice Authority is still per category, even though the call no longer names one.
     * @dev The role is checked against the category the protocol DECLARES, so a lending manager
     *      cannot admit a staking protocol by omitting the category — there is nothing to omit.
     */
    function test_AddProtocols_requiresTheDeclaredCategorysRole() public {
        address lendingOnlyManager = makeAddr("lendingOnlyManager");
        bytes32 lendingRole = bittyGuard.LENDING_MANAGER_ROLE();
        vm.prank(deployAdmin);
        bittyGuard.grantRole(lendingRole, lendingOnlyManager);

        vm.prank(lendingOnlyManager);
        vm.expectRevert();
        bittyGuard.addProtocols(stakingProtocols);

        vm.prank(lendingOnlyManager);
        bittyGuard.addProtocols(lendingProtocols);
        assertTrue(bittyGuard.isProtocolRegistered(lendingProtocol));
    }

    /// @dev A batch spanning categories needs a caller holding every role it touches.
    function test_AddProtocols_mixedBatchNeedsEveryRole() public {
        address lendingOnlyManager = makeAddr("lendingOnlyManager2");
        bytes32 lendingRole = bittyGuard.LENDING_MANAGER_ROLE();
        vm.prank(deployAdmin);
        bittyGuard.grantRole(lendingRole, lendingOnlyManager);

        address[] memory mixed = new address[](2);
        mixed[0] = lendingProtocol;
        mixed[1] = stakingProtocol;

        vm.prank(lendingOnlyManager);
        vm.expectRevert();
        bittyGuard.addProtocols(mixed);

        // Nothing partially applied: the whole batch reverted, including the entry it was entitled to.
        assertFalse(bittyGuard.isProtocolRegistered(lendingProtocol));
    }

    /**
     * @notice Deprecating uses the RECORDED category, so it works on a protocol that has gone silent.
     * @dev Deprecation is the lever for a protocol that has misbehaved. Re-probing it via ERC-165
     *      would make that lever depend on the very contract being disowned still answering.
     */
    function test_DeprecateProtocols_worksWhenProtocolStopsAnswering() public {
        vm.prank(protocolOwner);
        bittyGuard.addProtocols(lendingProtocols);

        // The protocol becomes an address with no code at all — supportsInterface would now revert.
        vm.etch(lendingProtocol, "");

        vm.prank(protocolOwner);
        bittyGuard.deprecateProtocols(lendingProtocols);

        assertTrue(bittyGuard.isProtocolDeprecated(lendingProtocol));
        assertFalse(bittyGuard.isProtocolRegistered(lendingProtocol));
    }
}
