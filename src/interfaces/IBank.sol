// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IBank
 * @notice Interface for the main Bank contract
 * @dev User-facing entry point for deposits, withdrawals, and position management
 */
interface IBank {
    // ==================== Structs ====================
    
    /**
     * @notice Represents a user's deposit position
     * @param amount Total amount deposited
     * @param shares Vault shares owned
     * @param tier Lock tier (0=NoLock, 1=30D, 2=90D, 3=180D)
     * @param depositTimestamp When position was created
     * @param lockEndTimestamp When lock period ends (0 if no lock)
     * @param referrer Address of referrer (address(0) if none)
     */
    struct Position {
        address token; 
        uint256 amount;
        uint256 shares;
        uint8 tier;
        uint256 depositTimestamp;
        uint256 lockEndTimestamp;
        address referrer;
    }
    
    // ==================== Events ====================
    
    event Deposit(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 shares,
        uint8 tier,
        uint256 positionId
    );
    
    event Withdraw(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 shares,
        uint256 positionId,
        uint256 penalty
    );
    
    event TokenSupported(address indexed token, bool supported);
    event EmergencyWithdraw(address indexed user, address indexed token, uint256 amount);
    
    // ==================== User Functions ====================
    
    /**
     * @notice Deposit tokens into the bank with specified lock tier
     * @param token Address of token to deposit
     * @param amount Amount to deposit
     * @param tier Lock tier (0-3)
     * @param referralCode Referral code (0 if none)
     * @return positionId ID of created position
     */
    function deposit(
        address token,
        uint256 amount,
        uint8 tier,
        bytes32 referralCode
    ) external returns (uint256 positionId);
    
    /**
     * @notice Withdraw from a position
     * @param positionId ID of position to withdraw from
     * @param shares Amount of shares to withdraw (0 = withdraw all)
     */
    function withdraw(uint256 positionId, uint256 shares) external;
    
    /**
     * @notice Get user's position details
     * @param user User address
     * @param positionId Position ID
     */
    function getPosition(address user, uint256 positionId) external view returns (Position memory);
    
    /**
     * @notice Get user's total positions count
     */
    function getUserPositionCount(address user) external view returns (uint256);
    
    /**
     * @notice Calculate current value of position including yield
     */
    function getPositionValue(address user, uint256 positionId) external view returns (uint256);
    
    /**
     * @notice Calculate early withdrawal penalty for a position
     */
    function calculatePenalty(address user, uint256 positionId) external view returns (uint256);
    
    // ==================== Admin Functions ====================
    
    /**
     * @notice Add or remove supported token
     */
    function setSupportedToken(address token, bool supported) external;
    
    /**
     * @notice Pause/unpause deposits and withdrawals
     */
    function setPaused(bool paused) external;
    
    /**
     * @notice Emergency withdraw (admin only, bypasses locks)
     */
    function emergencyWithdraw(address token) external;
}