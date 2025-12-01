// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {TierManager} from "../../src/TierManager.sol";
import {ITierManager} from "../../src/interfaces/ITierManager.sol";
import {Errors} from "../../src/libraries/Errors.sol";

/**
 * @title TierManagerTest
 * @notice Comprehensive unit tests for TierManager contract
 */
contract TierManagerTest is Test {
    TierManager public tierManager;
    
    address public owner;
    address public user;

    // Constants
    uint256 constant BASIS_POINTS = 10_000;
    uint256 constant SECONDS_PER_YEAR = 365 days;

    function setUp() public {
        owner = address(this);
        user = makeAddr("user");
        
        tierManager = new TierManager();
    }

    // ==================== Default Configuration Tests ====================

    function test_Constructor_DefaultTierConfigurations() public {
        // Tier 0: No lock
        ITierManager.TierConfig memory tier0 = tierManager.getTierConfig(0);
        assertEq(tier0.lockPeriod, 0);
        assertEq(tier0.apy, 0);
        assertEq(tier0.earlyWithdrawalPenalty, 0);
        assertTrue(tier0.enabled);

        // Tier 1: 30 days, 2% APY
        ITierManager.TierConfig memory tier1 = tierManager.getTierConfig(1);
        assertEq(tier1.lockPeriod, 30 days);
        assertEq(tier1.apy, 200); // 2% = 200 basis points
        assertEq(tier1.earlyWithdrawalPenalty, 5000); // 50%
        assertTrue(tier1.enabled);

        // Tier 2: 90 days, 5% APY
        ITierManager.TierConfig memory tier2 = tierManager.getTierConfig(2);
        assertEq(tier2.lockPeriod, 90 days);
        assertEq(tier2.apy, 500); // 5%
        assertEq(tier2.earlyWithdrawalPenalty, 5000);
        assertTrue(tier2.enabled);

        // Tier 3: 180 days, 8% APY
        ITierManager.TierConfig memory tier3 = tierManager.getTierConfig(3);
        assertEq(tier3.lockPeriod, 180 days);
        assertEq(tier3.apy, 800); // 8%
        assertEq(tier3.earlyWithdrawalPenalty, 5000);
        assertTrue(tier3.enabled);
    }

    function test_GetMaxTiers() public {
        assertEq(tierManager.getMaxTiers(), 4);
    }

    function test_GetAllTiers() public {
        ITierManager.TierConfig[] memory allTiers = tierManager.getAllTiers();
        assertEq(allTiers.length, 4);
        
        // Verify each tier is enabled by default
        for (uint8 i = 0; i < 4; i++) {
            assertTrue(allTiers[i].enabled);
        }
    }

    // ==================== Configuration Tests ====================

    function test_ConfigureTier_Success() public {
        uint8 tier = 1;
        uint256 newLockPeriod = 45 days;
        uint256 newApy = 300; // 3%
        uint256 newPenalty = 6000; // 60%

        tierManager.configureTier(tier, newLockPeriod, newApy, newPenalty);

        ITierManager.TierConfig memory config = tierManager.getTierConfig(tier);
        assertEq(config.lockPeriod, newLockPeriod);
        assertEq(config.apy, newApy);
        assertEq(config.earlyWithdrawalPenalty, newPenalty);
        assertTrue(config.enabled); // Remains enabled
    }

    function test_ConfigureTier_PreservesEnabledState() public {
        uint8 tier = 1;
        
        // Disable tier
        tierManager.setTierEnabled(tier, false);
        assertFalse(tierManager.getTierConfig(tier).enabled);

        // Configure tier (should preserve disabled state)
        tierManager.configureTier(tier, 60 days, 400, 5000);

        // Should still be disabled
        assertFalse(tierManager.getTierConfig(tier).enabled);
    }

    function test_ConfigureTier_RevertIfInvalidTier() public {
        vm.expectRevert(Errors.InvalidTier.selector);
        tierManager.configureTier(5, 30 days, 200, 5000); // Tier 5 doesn't exist
    }

    function test_ConfigureTier_RevertIfAPYTooHigh() public {
        vm.expectRevert(Errors.InvalidAmount.selector);
        tierManager.configureTier(1, 30 days, 10001, 5000); // APY > 100%
    }

    function test_ConfigureTier_RevertIfPenaltyTooHigh() public {
        vm.expectRevert(Errors.InvalidAmount.selector);
        tierManager.configureTier(1, 30 days, 200, 10001); // Penalty > 100%
    }

    function test_ConfigureTier_RevertIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert(); // Ownable: caller is not the owner
        tierManager.configureTier(1, 30 days, 200, 5000);
    }

    function test_SetTierEnabled_Success() public {
        uint8 tier = 1;
        
        // Disable
        tierManager.setTierEnabled(tier, false);
        assertFalse(tierManager.getTierConfig(tier).enabled);

        // Enable
        tierManager.setTierEnabled(tier, true);
        assertTrue(tierManager.getTierConfig(tier).enabled);
    }

    function test_SetTierEnabled_RevertIfInvalidTier() public {
        vm.expectRevert(Errors.InvalidTier.selector);
        tierManager.setTierEnabled(5, true);
    }

    function test_SetTierEnabled_RevertIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert(); // Ownable: caller is not the owner
        tierManager.setTierEnabled(1, false);
    }

    // ==================== Interest Calculation Tests ====================

    function test_CalculateInterest_Tier0_NoInterest() public {
        uint256 principal = 1000e18;
        uint256 duration = 30 days;

        uint256 interest = tierManager.calculateInterest(principal, 0, duration);
        assertEq(interest, 0); // Tier 0 has 0% APY
    }

    function test_CalculateInterest_Tier1_30Days() public {
        uint256 principal = 1000e18;
        uint256 duration = 30 days;
        uint8 tier = 1;

        uint256 interest = tierManager.calculateInterest(principal, tier, duration);

        // Expected: (1000 * 200 * 2592000) / (31536000 * 10000)
        // = 1.643835616... ≈ 1.64 tokens
        uint256 expected = (principal * 200 * duration) / (SECONDS_PER_YEAR * BASIS_POINTS);
        assertEq(interest, expected);
    }

    function test_CalculateInterest_Tier2_FullPeriod() public {
        uint256 principal = 10000e18;
        uint256 duration = 90 days;
        uint8 tier = 2;

        uint256 interest = tierManager.calculateInterest(principal, tier, duration);

        // Expected: (10000 * 500 * 90days) / (365days * 10000)
        // Should be approximately 5% * (90/365) * principal ≈ 123.28 tokens
        uint256 expected = (principal * 500 * duration) / (SECONDS_PER_YEAR * BASIS_POINTS);
        assertEq(interest, expected);
    }

    function test_CalculateInterest_Tier3_FullPeriod() public {
        uint256 principal = 5000e18;
        uint256 duration = 180 days;
        uint8 tier = 3;

        uint256 interest = tierManager.calculateInterest(principal, tier, duration);

        // Expected: (5000 * 800 * 180days) / (365days * 10000)
        // Should be approximately 8% * (180/365) * principal ≈ 197.26 tokens
        uint256 expected = (principal * 800 * duration) / (SECONDS_PER_YEAR * BASIS_POINTS);
        assertEq(interest, expected);
    }

    function test_CalculateInterest_ProRata() public {
        uint256 principal = 1000e18;
        uint8 tier = 1;

        // Calculate for 15 days
        uint256 interest15 = tierManager.calculateInterest(principal, tier, 15 days);

        // Calculate for 30 days
        uint256 interest30 = tierManager.calculateInterest(principal, tier, 30 days);

        // 30 days should be approximately double 15 days
        assertApproxEqRel(interest30, interest15 * 2, 0.01e18); // 1% tolerance
    }

    function test_CalculateInterest_ZeroPrincipal() public {
        uint256 interest = tierManager.calculateInterest(0, 1, 30 days);
        assertEq(interest, 0);
    }

    function test_CalculateInterest_ZeroDuration() public {
        uint256 interest = tierManager.calculateInterest(1000e18, 1, 0);
        assertEq(interest, 0);
    }

    function test_CalculateInterest_InvalidTier() public {
        uint256 interest = tierManager.calculateInterest(1000e18, 5, 30 days);
        assertEq(interest, 0); // Returns 0 for invalid tier
    }

    function test_CalculateInterest_DisabledTier() public {
        uint8 tier = 1;
        tierManager.setTierEnabled(tier, false);

        uint256 interest = tierManager.calculateInterest(1000e18, tier, 30 days);
        assertEq(interest, 0); // Returns 0 for disabled tier
    }

    // ==================== Penalty Calculation Tests ====================

    function test_CalculatePenalty_Tier0_NoPenalty() public {
        uint256 accruedInterest = 100e18;
        uint256 timeRemaining = 15 days;

        uint256 penalty = tierManager.calculatePenalty(accruedInterest, 0, timeRemaining);
        assertEq(penalty, 0); // Tier 0 has no penalty
    }

    function test_CalculatePenalty_Tier1_HalfInterest() public {
        uint256 accruedInterest = 100e18;
        uint256 timeRemaining = 15 days;
        uint8 tier = 1;

        uint256 penalty = tierManager.calculatePenalty(accruedInterest, tier, timeRemaining);

        // Expected: 100 * 5000 / 10000 = 50 tokens (50% penalty)
        assertEq(penalty, 50e18);
    }

    function test_CalculatePenalty_FullInterestLost() public {
        uint256 accruedInterest = 200e18;
        uint8 tier = 1;
        
        // Configure tier with 100% penalty for testing
        tierManager.configureTier(tier, 30 days, 200, 10000); // 100% penalty

        uint256 penalty = tierManager.calculatePenalty(accruedInterest, tier, 15 days);

        assertEq(penalty, 200e18); // All interest lost
    }

    function test_CalculatePenalty_NoTimeRemaining() public {
        uint256 accruedInterest = 100e18;
        uint8 tier = 1;

        uint256 penalty = tierManager.calculatePenalty(accruedInterest, tier, 0);
        assertEq(penalty, 0); // No penalty if lock ended
    }

    function test_CalculatePenalty_InvalidTier() public {
        uint256 penalty = tierManager.calculatePenalty(100e18, 5, 15 days);
        assertEq(penalty, 0);
    }

    function test_CalculatePenalty_DisabledTier() public {
        uint8 tier = 1;
        tierManager.setTierEnabled(tier, false);

        uint256 penalty = tierManager.calculatePenalty(100e18, tier, 15 days);
        assertEq(penalty, 0);
    }

    // ==================== Lock Period Tests ====================

    function test_CanWithdrawWithoutPenalty_Tier0_Always() public {
        uint256 depositTimestamp = block.timestamp;

        assertTrue(tierManager.canWithdrawWithoutPenalty(depositTimestamp, 0));
        
        // Even after time passes
        vm.warp(block.timestamp + 100 days);
        assertTrue(tierManager.canWithdrawWithoutPenalty(depositTimestamp, 0));
    }

    function test_CanWithdrawWithoutPenalty_BeforeLockEnds() public {
        uint256 depositTimestamp = block.timestamp;
        uint8 tier = 1; // 30 days lock

        assertFalse(tierManager.canWithdrawWithoutPenalty(depositTimestamp, tier));
        
        // 29 days later - still locked
        vm.warp(block.timestamp + 29 days);
        assertFalse(tierManager.canWithdrawWithoutPenalty(depositTimestamp, tier));
    }

    function test_CanWithdrawWithoutPenalty_ExactlyAtLockEnd() public {
        uint256 depositTimestamp = block.timestamp;
        uint8 tier = 1; // 30 days lock

        // Exactly 30 days later
        vm.warp(depositTimestamp + 30 days);
        assertTrue(tierManager.canWithdrawWithoutPenalty(depositTimestamp, tier));
    }

    function test_CanWithdrawWithoutPenalty_AfterLockEnds() public {
        uint256 depositTimestamp = block.timestamp;
        uint8 tier = 1; // 30 days lock

        // 31 days later
        vm.warp(depositTimestamp + 31 days);
        assertTrue(tierManager.canWithdrawWithoutPenalty(depositTimestamp, tier));
    }

    function test_CanWithdrawWithoutPenalty_InvalidTier() public {
        assertFalse(tierManager.canWithdrawWithoutPenalty(block.timestamp, 5));
    }

    function test_CanWithdrawWithoutPenalty_DisabledTier() public {
        uint8 tier = 1;
        tierManager.setTierEnabled(tier, false);

        assertFalse(tierManager.canWithdrawWithoutPenalty(block.timestamp, tier));
    }

    function test_GetLockEndTimestamp_Tier0_ReturnsZero() public {
        uint256 depositTimestamp = block.timestamp;
        uint256 lockEnd = tierManager.getLockEndTimestamp(depositTimestamp, 0);
        assertEq(lockEnd, 0); // No lock
    }

    function test_GetLockEndTimestamp_Tier1() public {
        uint256 depositTimestamp = block.timestamp;
        uint256 lockEnd = tierManager.getLockEndTimestamp(depositTimestamp, 1);
        assertEq(lockEnd, depositTimestamp + 30 days);
    }

    function test_GetLockEndTimestamp_Tier2() public {
        uint256 depositTimestamp = block.timestamp;
        uint256 lockEnd = tierManager.getLockEndTimestamp(depositTimestamp, 2);
        assertEq(lockEnd, depositTimestamp + 90 days);
    }

    function test_GetLockEndTimestamp_Tier3() public {
        uint256 depositTimestamp = block.timestamp;
        uint256 lockEnd = tierManager.getLockEndTimestamp(depositTimestamp, 3);
        assertEq(lockEnd, depositTimestamp + 180 days);
    }

    function test_GetLockEndTimestamp_InvalidTier() public {
        uint256 lockEnd = tierManager.getLockEndTimestamp(block.timestamp, 5);
        assertEq(lockEnd, 0);
    }

    // ==================== Tier Validation Tests ====================

    function test_IsTierValid_AllTiersValidByDefault() public {
        for (uint8 i = 0; i < 4; i++) {
            assertTrue(tierManager.isTierValid(i));
        }
    }

    function test_IsTierValid_InvalidTierNumber() public {
        assertFalse(tierManager.isTierValid(5));
    }

    function test_IsTierValid_DisabledTier() public {
        uint8 tier = 1;
        tierManager.setTierEnabled(tier, false);
        assertFalse(tierManager.isTierValid(tier));
    }

    // ==================== Preview Interest Tests ====================

    function test_PreviewInterest_Tier1() public {
        uint256 principal = 1000e18;
        uint8 tier = 1;

        uint256 interest = tierManager.previewInterest(principal, tier);

        // Should calculate interest for full 30 day period
        ITierManager.TierConfig memory config = tierManager.getTierConfig(tier);
        uint256 expected = (principal * config.apy * config.lockPeriod) / (SECONDS_PER_YEAR * BASIS_POINTS);
        assertEq(interest, expected);
    }

    function test_PreviewInterest_Tier2() public {
        uint256 principal = 5000e18;
        uint8 tier = 2;

        uint256 interest = tierManager.previewInterest(principal, tier);

        // Full 90 day period
        ITierManager.TierConfig memory config = tierManager.getTierConfig(tier);
        uint256 expected = (principal * config.apy * config.lockPeriod) / (SECONDS_PER_YEAR * BASIS_POINTS);
        assertEq(interest, expected);
    }

    function test_PreviewInterest_Tier0_ReturnsZero() public {
        uint256 interest = tierManager.previewInterest(1000e18, 0);
        assertEq(interest, 0);
    }

    function test_PreviewInterest_InvalidTier() public {
        uint256 interest = tierManager.previewInterest(1000e18, 5);
        assertEq(interest, 0);
    }

    function test_PreviewInterest_DisabledTier() public {
        uint8 tier = 1;
        tierManager.setTierEnabled(tier, false);

        uint256 interest = tierManager.previewInterest(1000e18, tier);
        assertEq(interest, 0);
    }

    // ==================== Edge Cases ====================

    function test_CalculateInterest_VeryLargePrincipal() public {
        uint256 principal = type(uint128).max; // Very large amount
        uint8 tier = 1;
        uint256 duration = 30 days;

        // Should not overflow
        uint256 interest = tierManager.calculateInterest(principal, tier, duration);
        assertGt(interest, 0);
    }

    function test_CalculateInterest_VeryLongDuration() public {
        uint256 principal = 1000e18;
        uint8 tier = 1;
        uint256 duration = 365 days * 10; // 10 years

        // Should not overflow
        uint256 interest = tierManager.calculateInterest(principal, tier, duration);
        assertGt(interest, 0);
    }
}