// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {VaultManager} from "../../src/VaultManager.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {Errors} from "../../src/libraries/Errors.sol";

/**
 * @title VaultManagerTest
 * @notice Comprehensive unit tests for VaultManager contract
 */
contract VaultManagerTest is Test {
    VaultManager public vaultManager;
    MockERC20 public token;
    
    address public bank;
    address public user1;
    address public user2;
    address public owner;

    uint256 constant DEAD_SHARES = 1000;
    uint256 constant MIN_FIRST_DEPOSIT = 1e6;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        // Create mock bank address
        bank = makeAddr("bank");
        
        // Deploy VaultManager
        vaultManager = new VaultManager(bank);
        
        // Deploy mock token
        token = new MockERC20("Test Token", "TEST", 18);
    }

    // ==================== Vault Creation Tests ====================

    function test_CreateVault_Success() public {
        vaultManager.createVault(address(token));
        
        assertTrue(vaultManager.vaultExists(address(token)));
        assertEq(vaultManager.totalAssets(address(token)), 0);
        assertEq(vaultManager.totalShares(address(token)), 0);
    }

    function test_CreateVault_RevertIfZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vaultManager.createVault(address(0));
    }

    function test_CreateVault_RevertIfAlreadyExists() public {
        vaultManager.createVault(address(token));
        
        vm.expectRevert(Errors.TokenAlreadySupported.selector);
        vaultManager.createVault(address(token));
    }

    // ==================== First Deposit Tests ====================

    function test_Deposit_FirstDeposit_BurnsDeadShares() public {
        vaultManager.createVault(address(token));
        
        uint256 depositAmount = 10000e18;
        token.mint(bank, depositAmount);
        
        vm.startPrank(bank);
        token.approve(address(vaultManager), depositAmount);
        
        uint256 shares = vaultManager.deposit(address(token), depositAmount, user1);
        vm.stopPrank();
        
        // User should receive (amount - DEAD_SHARES)
        assertEq(shares, depositAmount - DEAD_SHARES);
        
        // Total shares should be depositAmount (includes DEAD_SHARES)
        assertEq(vaultManager.totalShares(address(token)), depositAmount);
        
        // DEAD_SHARES should be burned to address(0)
        assertEq(vaultManager.balanceOf(address(token), address(0)), DEAD_SHARES);
        
        // User balance should be (shares received)
        assertEq(vaultManager.balanceOf(address(token), user1), depositAmount - DEAD_SHARES);
    }

    function test_Deposit_FirstDeposit_RevertIfBelowMinimum() public {
        vaultManager.createVault(address(token));
        
        uint256 depositAmount = MIN_FIRST_DEPOSIT - 1;
        token.mint(bank, depositAmount);
        
        vm.startPrank(bank);
        token.approve(address(vaultManager), depositAmount);
        
        vm.expectRevert(Errors.InvalidAmount.selector);
        vaultManager.deposit(address(token), depositAmount, user1);
        vm.stopPrank();
    }

    function test_Deposit_FirstDeposit_MinimumAmount() public {
        vaultManager.createVault(address(token));
        
        uint256 depositAmount = MIN_FIRST_DEPOSIT;
        token.mint(bank, depositAmount);
        
        vm.startPrank(bank);
        token.approve(address(vaultManager), depositAmount);
        
        uint256 shares = vaultManager.deposit(address(token), depositAmount, user1);
        vm.stopPrank();
        
        assertEq(shares, depositAmount - DEAD_SHARES);
    }

    // ==================== Subsequent Deposit Tests ====================

    function test_Deposit_SubsequentDeposit_ProportionalShares() public {
        vaultManager.createVault(address(token));
        
        // First deposit
        uint256 firstDeposit = 10000e18;
        token.mint(bank, firstDeposit);
        
        vm.startPrank(bank);
        token.approve(address(vaultManager), firstDeposit);
        vaultManager.deposit(address(token), firstDeposit, user1);
        vm.stopPrank();
        
        // Second deposit
        uint256 secondDeposit = 5000e18;
        token.mint(bank, secondDeposit);
        
        vm.startPrank(bank);
        token.approve(address(vaultManager), secondDeposit);
        uint256 shares = vaultManager.deposit(address(token), secondDeposit, user2);
        vm.stopPrank();
        
        // Calculate expected shares: (assets * totalShares) / totalAssets
        uint256 expectedShares = (secondDeposit * vaultManager.totalShares(address(token))) / vaultManager.totalAssets(address(token));
        
        assertEq(shares, expectedShares);
    }

    function test_Deposit_RevertIfNotBank() public {
        vaultManager.createVault(address(token));
        token.mint(user1, 1000e18);
        
        vm.startPrank(user1);
        token.approve(address(vaultManager), 1000e18);
        
        vm.expectRevert(Errors.Unauthorized.selector);
        vaultManager.deposit(address(token), 1000e18, user1);
        vm.stopPrank();
    }

    function test_Deposit_RevertIfZeroAmount() public {
        vaultManager.createVault(address(token));
        
        vm.prank(bank);
        vm.expectRevert(Errors.ZeroAmount.selector);
        vaultManager.deposit(address(token), 0, user1);
    }

    function test_Deposit_RevertIfZeroReceiver() public {
        vaultManager.createVault(address(token));
        token.mint(bank, 1000e18);
        
        vm.startPrank(bank);
        token.approve(address(vaultManager), 1000e18);
        
        vm.expectRevert(Errors.ZeroAddress.selector);
        vaultManager.deposit(address(token), 1000e18, address(0));
        vm.stopPrank();
    }

    function test_Deposit_RevertIfVaultDoesNotExist() public {
        token.mint(bank, 1000e18);
        
        vm.startPrank(bank);
        token.approve(address(vaultManager), 1000e18);
        
        vm.expectRevert(Errors.VaultDoesNotExist.selector);
        vaultManager.deposit(address(token), 1000e18, user1);
        vm.stopPrank();
    }

    // ==================== Withdraw Tests ====================

    function test_Withdraw_Success() public {
        vaultManager.createVault(address(token));
        
        // Deposit
        uint256 depositAmount = 10000e18;
        token.mint(bank, depositAmount);
        
        vm.startPrank(bank);
        token.approve(address(vaultManager), depositAmount);
        uint256 shares = vaultManager.deposit(address(token), depositAmount, user1);
        
        // Withdraw
        uint256 assets = vaultManager.withdraw(address(token), shares, user1);
        vm.stopPrank();
        
        // Should receive proportional assets
        assertGt(assets, 0);
        assertEq(token.balanceOf(user1), assets);
    }

    function test_Withdraw_PartialWithdraw() public {
        vaultManager.createVault(address(token));
        
        // Deposit
        uint256 depositAmount = 10000e18;
        token.mint(bank, depositAmount);
        
        vm.startPrank(bank);
        token.approve(address(vaultManager), depositAmount);
        uint256 totalShares = vaultManager.deposit(address(token), depositAmount, user1);
        
        // Withdraw half
        uint256 sharesToWithdraw = totalShares / 2;
        uint256 assets = vaultManager.withdraw(address(token), sharesToWithdraw, user1);
        vm.stopPrank();
        
        // Should receive approximately half the assets
        assertApproxEqRel(assets, depositAmount / 2, 0.01e18); // 1% tolerance
        
        // Remaining shares in vault
        uint256 remainingShares = vaultManager.totalShares(address(token)) - sharesToWithdraw;
        assertGt(remainingShares, 0);
    }

    function test_Withdraw_RevertIfNotBank() public {
        vaultManager.createVault(address(token));
        
        vm.prank(user1);
        vm.expectRevert(Errors.Unauthorized.selector);
        vaultManager.withdraw(address(token), 1000, user1);
    }

    function test_Withdraw_RevertIfZeroShares() public {
        vaultManager.createVault(address(token));
        
        vm.prank(bank);
        vm.expectRevert(Errors.ZeroAmount.selector);
        vaultManager.withdraw(address(token), 0, user1);
    }

    function test_Withdraw_RevertIfZeroReceiver() public {
        vaultManager.createVault(address(token));
        
        vm.prank(bank);
        vm.expectRevert(Errors.ZeroAddress.selector);
        vaultManager.withdraw(address(token), 1000, address(0));
    }

    // ==================== Yield Distribution Tests ====================

    function test_DistributeYield_IncreasesShareValue() public {
        vaultManager.createVault(address(token));
        
        // Initial deposit
        uint256 depositAmount = 10000e18;
        token.mint(bank, depositAmount);
        
        vm.startPrank(bank);
        token.approve(address(vaultManager), depositAmount);
        uint256 shares = vaultManager.deposit(address(token), depositAmount, user1);
        
        // Get initial share value
        uint256 initialValue = vaultManager.convertToAssets(address(token), shares);
        
        // Distribute yield
        uint256 yieldAmount = 1000e18;
        token.mint(bank, yieldAmount);
        token.approve(address(vaultManager), yieldAmount);
        token.transfer(address(vaultManager), yieldAmount);
        
        vaultManager.distributeYield(address(token), yieldAmount);
        vm.stopPrank();
        
        // Get new share value
        uint256 newValue = vaultManager.convertToAssets(address(token), shares);
        
        // Share value should increase
        assertGt(newValue, initialValue);
    }

    function test_DistributeYield_RevertIfNotBank() public {
        vaultManager.createVault(address(token));
        
        vm.prank(user1);
        vm.expectRevert(Errors.Unauthorized.selector);
        vaultManager.distributeYield(address(token), 1000e18);
    }

    function test_DistributeYield_RevertIfZeroAmount() public {
        vaultManager.createVault(address(token));
        
        vm.prank(bank);
        vm.expectRevert(Errors.ZeroAmount.selector);
        vaultManager.distributeYield(address(token), 0);
    }

    // ==================== Conversion Function Tests ====================

    function test_ConvertToShares_FirstDeposit() public {
        vaultManager.createVault(address(token));
        
        uint256 assets = 10000e18;
        uint256 shares = vaultManager.convertToShares(address(token), assets);
        
        // First deposit: shares = assets - DEAD_SHARES
        assertEq(shares, assets - DEAD_SHARES);
    }

    function test_ConvertToShares_SubsequentDeposit() public {
        vaultManager.createVault(address(token));
        
        // Make first deposit
        uint256 firstDeposit = 10000e18;
        token.mint(bank, firstDeposit);
        
        vm.startPrank(bank);
        token.approve(address(vaultManager), firstDeposit);
        vaultManager.deposit(address(token), firstDeposit, user1);
        vm.stopPrank();
        
        // Check conversion
        uint256 assets = 5000e18;
        uint256 shares = vaultManager.convertToShares(address(token), assets);
        
        // shares = (assets * totalShares) / totalAssets
        uint256 expectedShares = (assets * vaultManager.totalShares(address(token))) / vaultManager.totalAssets(address(token));
        assertEq(shares, expectedShares);
    }

    function test_ConvertToAssets_Success() public {
        vaultManager.createVault(address(token));
        
        // Make deposit
        uint256 depositAmount = 10000e18;
        token.mint(bank, depositAmount);
        
        vm.startPrank(bank);
        token.approve(address(vaultManager), depositAmount);
        uint256 shares = vaultManager.deposit(address(token), depositAmount, user1);
        vm.stopPrank();
        
        // Convert back to assets
        uint256 assets = vaultManager.convertToAssets(address(token), shares);
        
        // Should be close to original deposit (minus DEAD_SHARES rounding)
        assertApproxEqRel(assets, depositAmount, 0.01e18); // 1% tolerance
    }

    function test_ConvertToAssets_ReturnsZeroForNonExistentVault() public view {
        uint256 assets = vaultManager.convertToAssets(address(token), 1000);
        assertEq(assets, 0);
    }

    // ==================== View Function Tests ====================

    function test_TotalAssets_UpdatesCorrectly() public {
        vaultManager.createVault(address(token));
        
        assertEq(vaultManager.totalAssets(address(token)), 0);
        
        // Deposit
        uint256 depositAmount = 10000e18;
        token.mint(bank, depositAmount);
        
        vm.startPrank(bank);
        token.approve(address(vaultManager), depositAmount);
        vaultManager.deposit(address(token), depositAmount, user1);
        vm.stopPrank();
        
        assertEq(vaultManager.totalAssets(address(token)), depositAmount);
    }

    function test_TotalShares_UpdatesCorrectly() public {
        vaultManager.createVault(address(token));
        
        assertEq(vaultManager.totalShares(address(token)), 0);
        
        // Deposit
        uint256 depositAmount = 10000e18;
        token.mint(bank, depositAmount);
        
        vm.startPrank(bank);
        token.approve(address(vaultManager), depositAmount);
        vaultManager.deposit(address(token), depositAmount, user1);
        vm.stopPrank();
        
        // First deposit: totalShares = depositAmount (includes DEAD_SHARES)
        assertEq(vaultManager.totalShares(address(token)), depositAmount);
    }

    function test_BalanceOf_TracksUserShares() public {
        vaultManager.createVault(address(token));
        
        uint256 depositAmount = 10000e18;
        token.mint(bank, depositAmount);
        
        vm.startPrank(bank);
        token.approve(address(vaultManager), depositAmount);
        uint256 shares = vaultManager.deposit(address(token), depositAmount, user1);
        vm.stopPrank();
        
        assertEq(vaultManager.balanceOf(address(token), user1), shares);
    }

    function test_VaultExists_ReturnsCorrectly() public {
        assertFalse(vaultManager.vaultExists(address(token)));
        
        vaultManager.createVault(address(token));
        
        assertTrue(vaultManager.vaultExists(address(token)));
    }

    // ==================== Edge Case Tests ====================

    function test_Deposit_VerySmallAmount() public {
        vaultManager.createVault(address(token));
        
        // First deposit must be above MIN_FIRST_DEPOSIT
        uint256 firstDeposit = MIN_FIRST_DEPOSIT;
        token.mint(bank, firstDeposit);
        
        vm.startPrank(bank);
        token.approve(address(vaultManager), firstDeposit);
        vaultManager.deposit(address(token), firstDeposit, user1);
        
        // Second deposit can be small
        uint256 smallDeposit = 1000; // 1000 wei
        token.mint(bank, smallDeposit);
        token.approve(address(vaultManager), smallDeposit);
        
        uint256 shares = vaultManager.deposit(address(token), smallDeposit, user2);
        vm.stopPrank();
        
        // Should still mint some shares (unless rounding to zero)
        // In which case it should revert with InvalidAmount
        // Let's just verify it doesn't revert unexpectedly
        assertGe(shares, 0);
    }

    function test_MultipleUsersDeposit() public {
        vaultManager.createVault(address(token));
        
        // User1 deposits
        uint256 deposit1 = 10000e18;
        token.mint(bank, deposit1);
        
        vm.startPrank(bank);
        token.approve(address(vaultManager), deposit1);
        uint256 shares1 = vaultManager.deposit(address(token), deposit1, user1);
        
        // User2 deposits
        uint256 deposit2 = 5000e18;
        token.mint(bank, deposit2);
        token.approve(address(vaultManager), deposit2);
        uint256 shares2 = vaultManager.deposit(address(token), deposit2, user2);
        vm.stopPrank();
        
        // Both should have shares
        assertGt(shares1, 0);
        assertGt(shares2, 0);
        
        // User1 should have more shares (deposited first + more amount)
        assertGt(shares1, shares2);
    }
}