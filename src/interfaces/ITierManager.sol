// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title ITierManager
 * @notice Interface for managing lock tiers and interest rates
 * @dev Handles tier configuration, APY calculations, and penalties
 */
interface ITierManager {
    // ==================== Structs ====================
    
    /**
     * @notice Tier configuration
     * @param lockPeriod Duration of lock in seconds
     * @param apy Annual percentage yield (in basis points, e.g., 500 = 5%)
     * @param earlyWithdrawalPenalty Penalty percentage for early withdrawal (in basis points)
     * @param enabled Whether tier is active
     */
    struct TierConfig {
        uint256 lockPeriod;
        uint256 apy;
        uint256 earlyWithdrawalPenalty;
        bool enabled;
    }
    
    // ==================== Events ====================
    
    event TierConfigured(uint8 indexed tier, uint256 lockPeriod, uint256 apy, uint256 penalty);
    event TierEnabled(uint8 indexed tier, bool enabled);
    
    // ==================== Constants ====================
    
    function BASIS_POINTS() external view returns (uint256);
    function SECONDS_PER_YEAR() external view returns (uint256);
    
    // ==================== Configuration Functions ====================
    
    /**
     * @notice Configure a tier
     * @param tier Tier number (0-3)
     * @param lockPeriod Lock duration in seconds
     * @param apy APY in basis points
     * @param penalty Early withdrawal penalty in basis points
     */
    function configureTier(
        uint8 tier,
        uint256 lockPeriod,
        uint256 apy,
        uint256 penalty
    ) external;
    
    /**
     * @notice Enable or disable a tier
     */
    function setTierEnabled(uint8 tier, bool enabled) external;
    
    // ==================== Calculation Functions ====================
    
    /**
     * @notice Calculate interest earned for a position
     * @param principal Initial deposit amount
     * @param tier Lock tier
     * @param duration Time elapsed in seconds
     * @return interest Interest earned
     */
    function calculateInterest(
        uint256 principal,
        uint8 tier,
        uint256 duration
    ) external view returns (uint256 interest);
    
    /**
     * @notice Calculate early withdrawal penalty
     * @param accruedInterest Total interest earned
     * @param tier Lock tier
     * @param timeRemaining Seconds remaining in lock period
     * @return penalty Penalty amount
     */
    function calculatePenalty(
        uint256 accruedInterest,
        uint8 tier,
        uint256 timeRemaining
    ) external view returns (uint256 penalty);
    
    /**
     * @notice Check if position can be withdrawn without penalty
     * @param depositTimestamp When position was created
     * @param tier Lock tier
     * @return canWithdraw True if lock period has ended
     */
    function canWithdrawWithoutPenalty(
        uint256 depositTimestamp,
        uint8 tier
    ) external view returns (bool canWithdraw);
    
    /**
     * @notice Get lock end timestamp for a deposit
     */
    function getLockEndTimestamp(
        uint256 depositTimestamp,
        uint8 tier
    ) external view returns (uint256);
    
    // ==================== View Functions ====================
    
    /**
     * @notice Get tier configuration
     */
    function getTierConfig(uint8 tier) external view returns (TierConfig memory);
    
    /**
     * @notice Check if tier is valid and enabled
     */
    function isTierValid(uint8 tier) external view returns (bool);
}