// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title Errors
 * @notice Library containing all custom errors for VaultForge
 * @dev Using custom errors instead of require strings saves gas
 */
library Errors {
    // ==================== General Errors ====================
    error ZeroAddress();
    error ZeroAmount();
    error InvalidAmount();
    error Unauthorized();
    error Paused();
    error NotPaused();
    
    // ==================== Bank Errors ====================
    error TokenNotSupported();
    error TokenAlreadySupported();
    error InsufficientBalance();
    error TransferFailed();
    
    // ==================== Vault Errors ====================
    error VaultDoesNotExist();
    error InsufficientShares();
    error MaxCapReached();
    
    // ==================== Tier Errors ====================
    error InvalidTier();
    error PositionLocked();
    error PositionDoesNotExist();
    error LockPeriodNotEnded();
    error InvalidLockPeriod();
    
    // ==================== Yield Router Errors ====================
    error StrategyFailed();
    error InsufficientLiquidity();
    error InvalidStrategy();
    
    // ==================== Fee Errors ====================
    error ExcessiveFee();
    error FeeTransferFailed();
    
    // ==================== Referral Errors ====================
    error InvalidReferralCode();
    error ReferralCodeAlreadyExists();
    error CannotReferSelf();
    error MinimumDepositNotMet();
}