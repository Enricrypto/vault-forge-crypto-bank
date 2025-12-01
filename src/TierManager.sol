// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ITierManager} from "./interfaces/ITierManager.sol";
import {Errors} from "./libraries/Errors.sol";

/**
 * @title TierManager
 * @notice Manages lock tier configurations and interest calculations
 * @dev Handles APY, lock periods, and penalty calculations for time-locked deposits
 * 
 * Default tiers:
 * - Tier 0: No lock, 0% APY, no penalty
 * - Tier 1: 30 days, 2% APY, 50% penalty
 * - Tier 2: 90 days, 5% APY, 50% penalty
 * - Tier 3: 180 days, 8% APY, 50% penalty
 */
contract TierManager is ITierManager, Ownable {
    // ==================== Constants ====================

    /// @notice Basis points denominator (10000 = 100%)
    uint256 public constant BASIS_POINTS = 10_000;

    /// @notice Seconds in a year (365 days)
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    /// @notice Maximum number of tiers
    uint8 private constant MAX_TIERS = 4;

    // ==================== State Variables ====================

    /// @notice Tier configurations
    mapping(uint8 => TierConfig) private tiers;

    // ==================== Constructor ====================

    /**
     * @notice Initialize TierManager with default tier configurations
     */
    constructor() Ownable(msg.sender) {
        // Tier 0: No lock
        tiers[0] = TierConfig({
            lockPeriod: 0,
            apy: 0, // 0% APY
            earlyWithdrawalPenalty: 0, // No penalty (no lock)
            enabled: true
        });

        // Tier 1: 30 days
        tiers[1] = TierConfig({
            lockPeriod: 30 days,
            apy: 200, // 2% APY (200 basis points)
            earlyWithdrawalPenalty: 5000, // 50% penalty
            enabled: true
        });

        // Tier 2: 90 days
        tiers[2] = TierConfig({
            lockPeriod: 90 days,
            apy: 500, // 5% APY (500 basis points)
            earlyWithdrawalPenalty: 5000, // 50% penalty
            enabled: true
        });

        // Tier 3: 180 days
        tiers[3] = TierConfig({
            lockPeriod: 180 days,
            apy: 800, // 8% APY (800 basis points)
            earlyWithdrawalPenalty: 5000, // 50% penalty
            enabled: true
        });
    }

    // ==================== Configuration Functions ====================

    /**
     * @notice Configure a tier
     * @param tier Tier number (0-3)
     * @param lockPeriod Lock duration in seconds
     * @param apy APY in basis points (e.g., 500 = 5%)
     * @param penalty Early withdrawal penalty in basis points (e.g., 5000 = 50%)
     */
    function configureTier(
        uint8 tier,
        uint256 lockPeriod,
        uint256 apy,
        uint256 penalty
    ) external onlyOwner {
        if (tier >= MAX_TIERS) revert Errors.InvalidTier();
        if (apy > BASIS_POINTS) revert Errors.InvalidAmount(); // APY can't exceed 100%
        if (penalty > BASIS_POINTS) revert Errors.InvalidAmount(); // Penalty can't exceed 100%

        tiers[tier] = TierConfig({
            lockPeriod: lockPeriod,
            apy: apy,
            earlyWithdrawalPenalty: penalty,
            enabled: tiers[tier].enabled // Preserve enabled state
        });

        emit TierConfigured(tier, lockPeriod, apy, penalty);
    }

    /**
     * @notice Enable or disable a tier
     * @param tier Tier number
     * @param enabled Whether tier should be enabled
     */
    function setTierEnabled(uint8 tier, bool enabled) external onlyOwner {
        if (tier >= MAX_TIERS) revert Errors.InvalidTier();

        tiers[tier].enabled = enabled;
        emit TierEnabled(tier, enabled);
    }

    // ==================== Calculation Functions ====================

    /**
     * @notice Calculate interest earned for a position
     * @param principal Initial deposit amount
     * @param tier Lock tier
     * @param duration Time elapsed in seconds
     * @return interest Interest earned
     * 
     * @dev Formula: interest = principal * apy * duration / (SECONDS_PER_YEAR * BASIS_POINTS)
     *      This is simple interest, not compounding
     */
    function calculateInterest(
        uint256 principal,
        uint8 tier,
        uint256 duration
    ) external view returns (uint256 interest) {
        if (tier >= MAX_TIERS) return 0;
        
        TierConfig memory config = tiers[tier];
        if (!config.enabled || config.apy == 0) return 0;

        // interest = (principal * apy * duration) / (SECONDS_PER_YEAR * BASIS_POINTS)
        // Using safe math (Solidity 0.8+)
        interest = (principal * config.apy * duration) / (SECONDS_PER_YEAR * BASIS_POINTS);
    }

    /**
     * @notice Calculate early withdrawal penalty
     * @param accruedInterest Total interest earned so far
     * @param tier Lock tier
     * @param timeRemaining Seconds remaining in lock period
     * @return penalty Penalty amount
     * 
     * @dev Penalty is a percentage of accrued interest
     *      Full penalty applied regardless of time remaining (flat rate model)
     *      Alternative: could make penalty proportional to timeRemaining
     */
    function calculatePenalty(
        uint256 accruedInterest,
        uint8 tier,
        uint256 timeRemaining
    ) external view returns (uint256 penalty) {
        if (tier >= MAX_TIERS) return 0;
        if (timeRemaining == 0) return 0; // No penalty if lock period ended
        
        TierConfig memory config = tiers[tier];
        if (!config.enabled) return 0;

        // penalty = accruedInterest * earlyWithdrawalPenalty / BASIS_POINTS
        penalty = (accruedInterest * config.earlyWithdrawalPenalty) / BASIS_POINTS;

        // Note: This is a flat penalty model
        // Alternative models:
        // 1. Proportional: penalty increases as more time remaining
        // 2. Progressive: penalty decreases as lock period progresses
    }

    /**
     * @notice Check if position can be withdrawn without penalty
     * @param depositTimestamp When position was created
     * @param tier Lock tier
     * @return canWithdraw True if lock period has ended
     */
    function canWithdrawWithoutPenalty(
        uint256 depositTimestamp,
        uint8 tier
    ) external view returns (bool canWithdraw) {
        if (tier >= MAX_TIERS) return false;
        
        TierConfig memory config = tiers[tier];
        if (!config.enabled) return false;

        // No lock period means always can withdraw
        if (config.lockPeriod == 0) return true;

        // Check if lock period has elapsed
        return block.timestamp >= depositTimestamp + config.lockPeriod;
    }

    /**
     * @notice Get lock end timestamp for a deposit
     * @param depositTimestamp When deposit was made
     * @param tier Lock tier
     * @return Lock end timestamp (0 if no lock)
     */
    function getLockEndTimestamp(
        uint256 depositTimestamp,
        uint8 tier
    ) external view returns (uint256) {
        if (tier >= MAX_TIERS) return 0;
        
        TierConfig memory config = tiers[tier];
        if (!config.enabled) return 0;

        // No lock period
        if (config.lockPeriod == 0) return 0;

        return depositTimestamp + config.lockPeriod;
    }

    // ==================== View Functions ====================

    /**
     * @notice Get tier configuration
     * @param tier Tier number
     * @return TierConfig struct
     */
    function getTierConfig(uint8 tier) external view returns (TierConfig memory) {
        if (tier >= MAX_TIERS) {
            // Return empty config for invalid tier
            return TierConfig({
                lockPeriod: 0,
                apy: 0,
                earlyWithdrawalPenalty: 0,
                enabled: false
            });
        }
        return tiers[tier];
    }

    /**
     * @notice Check if tier is valid and enabled
     * @param tier Tier number
     * @return True if tier exists and is enabled
     */
    function isTierValid(uint8 tier) external view returns (bool) {
        if (tier >= MAX_TIERS) return false;
        return tiers[tier].enabled;
    }

    /**
     * @notice Get all tier configurations
     * @return Array of all tier configs
     * @dev Useful for frontend to display available options
     */
    function getAllTiers() external view returns (TierConfig[] memory) {
        TierConfig[] memory allTiers = new TierConfig[](MAX_TIERS);
        for (uint8 i = 0; i < MAX_TIERS; i++) {
            allTiers[i] = tiers[i];
        }
        return allTiers;
    }

    /**
     * @notice Get maximum tier number
     */
    function getMaxTiers() external pure returns (uint8) {
        return MAX_TIERS;
    }

    /**
     * @notice Preview interest for a potential deposit
     * @param principal Amount to deposit
     * @param tier Desired tier
     * @return interest Interest earned after full lock period
     * @dev Useful for frontend to show users potential returns
     */
    function previewInterest(
        uint256 principal,
        uint8 tier
    ) external view returns (uint256 interest) {
        if (tier >= MAX_TIERS) return 0;
        
        TierConfig memory config = tiers[tier];
        if (!config.enabled || config.apy == 0) return 0;

        // Calculate interest for full lock period
        interest = (principal * config.apy * config.lockPeriod) / (SECONDS_PER_YEAR * BASIS_POINTS);
    }
}