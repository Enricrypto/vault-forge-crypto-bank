// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {IBank} from "./interfaces/IBank.sol";
import {IVaultManager} from "./interfaces/IVaultManager.sol";
import {ITierManager} from "./interfaces/ITierManager.sol";
import {Errors} from "./libraries/Errors.sol";

/**
 * @title Bank
 * @notice Main entry point for VaultForge - multi-token savings bank with tiered yields
 * @dev Implements deposit/withdraw with lock periods, referral system, and emergency controls
 * 
 * Security considerations:
 * - ReentrancyGuard on all state-changing external functions
 * - Pausable for emergency stops
 * - Ownable for admin functions
 * - CEI pattern (Checks-Effects-Interactions) throughout
 * - SafeERC20 for all token transfers
 * - First depositor attack mitigation via MIN_DEPOSIT
 */
contract Bank is IBank, ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    // ==================== State Variables ====================

    /// @notice VaultManager contract for share accounting
    IVaultManager public immutable VAULT_MANAGER;
    
    /// @notice TierManager contract for lock period logic
    ITierManager public immutable TIER_MANAGER;

    /// @notice Mapping of token address => whether it's supported
    mapping(address => bool) public supportedTokens;

    /// @notice User positions: user => positionId => Position
    mapping(address => mapping(uint256 => Position)) private userPositions;

    /// @notice Position counter per user: user => position count
    mapping(address => uint256) private userPositionCount;

    /// @notice Minimum deposit amount to prevent dust/griefing (in wei)
    uint256 public constant MIN_DEPOSIT = 1000;

    // ==================== Constructor ====================

    /**
     * @notice Initialize Bank with required contracts
     * @param _vaultManager VAULT_MANAGER contract address
     * @param _tierManager TIER_MANAGER contract address
     */
    constructor(
        address _vaultManager,
        address _tierManager
    ) Ownable(msg.sender) {
        if (_vaultManager == address(0) || _tierManager == address(0)) {
            revert Errors.ZeroAddress();
        }
        
        VAULT_MANAGER = IVaultManager(_vaultManager);
        TIER_MANAGER = ITierManager(_tierManager);
    }

    // ==================== User Functions ====================

    /**
     * @notice Deposit tokens into the bank with specified lock tier
     * @param token Address of token to deposit
     * @param amount Amount to deposit
     * @param tier Lock tier (0-3)
     * @param referralCode Referral code (0 if none)
     * @return positionId ID of created position
     * 
     * @dev Follows CEI pattern:
     *      1. Checks: validations
     *      2. Effects: update state
     *      3. Interactions: external calls
     */
    function deposit(
        address token,
        uint256 amount,
        uint8 tier,
        bytes32 referralCode
    ) external nonReentrant whenNotPaused returns (uint256 positionId) {
        // ========== CHECKS ==========
        if (token == address(0)) revert Errors.ZeroAddress();
        if (amount == 0) revert Errors.ZeroAmount();
        if (amount < MIN_DEPOSIT) revert Errors.InvalidAmount();
        if (!supportedTokens[token]) revert Errors.TokenNotSupported();
        if (!TIER_MANAGER.isTierValid(tier)) revert Errors.InvalidTier();

        // Handle referral
        address referrer = address(0);
        if (referralCode != bytes32(0)) {
            referrer = referralCodes[referralCode];
            if (referrer == address(0)) revert Errors.InvalidReferralCode();
            if (referrer == msg.sender) revert Errors.CannotReferSelf();
        }

        // ========== EFFECTS ==========
        // Generate position ID
        positionId = userPositionCount[msg.sender];
        userPositionCount[msg.sender]++;

        // Calculate lock end timestamp
        uint256 lockEndTimestamp = TIER_MANAGER.getLockEndTimestamp(
            block.timestamp,
            tier
        );

        // Create vault if doesn't exist
        if (!VAULT_MANAGER.vaultExists(token)) {
            VAULT_MANAGER.createVault(token);
        }

        // ========== INTERACTIONS ==========
        // Transfer tokens from user to VAULT_MANAGER
        IERC20(token).safeTransferFrom(msg.sender, address(VAULT_MANAGER), amount);

        // Mint shares in vault
        uint256 shares = VAULT_MANAGER.deposit(token, amount, msg.sender);

        // Store position
        userPositions[msg.sender][positionId] = Position({
            token: token,
            amount: amount,
            shares: shares,
            tier: tier,
            depositTimestamp: block.timestamp,
            lockEndTimestamp: lockEndTimestamp,
            referrer: referrer
        });

        emit Deposit(msg.sender, token, amount, shares, tier, positionId);
    }

    /**
     * @notice Withdraw from a position
     * @param positionId ID of position to withdraw from
     * @param shares Amount of shares to withdraw (0 = withdraw all)
     * 
     * @dev Applies early withdrawal penalty if lock period not ended
     *      Follows CEI pattern with reentrancy guard
     */
    function withdraw(
        uint256 positionId,
        uint256 shares
    ) external nonReentrant whenNotPaused {
        // ========== CHECKS ==========
        Position storage position = userPositions[msg.sender][positionId];
        
        if (position.shares == 0) revert Errors.PositionDoesNotExist();
        
        // If shares = 0, withdraw all
        uint256 sharesToWithdraw = shares == 0 ? position.shares : shares;
        if (sharesToWithdraw > position.shares) revert Errors.InsufficientShares();

        // Check if position is locked
        bool isLocked = block.timestamp < position.lockEndTimestamp;

        // Calculate penalty if early withdrawal
        uint256 penalty = 0;
        if (isLocked) {
            // Calculate time elapsed and accrued interest
            uint256 timeElapsed = block.timestamp - position.depositTimestamp;
            uint256 accruedInterest = TIER_MANAGER.calculateInterest(
                position.amount,
                position.tier,
                timeElapsed
            );

            // Calculate penalty on accrued interest
            uint256 timeRemaining = position.lockEndTimestamp - block.timestamp;
            penalty = TIER_MANAGER.calculatePenalty(
                accruedInterest,
                position.tier,
                timeRemaining
            );

            // Penalty cannot exceed accrued interest
            if (penalty > accruedInterest) {
                penalty = accruedInterest;
            }
        }

        // ========== EFFECTS ==========
        // Update position
        position.shares -= sharesToWithdraw;
        
        // If fully withdrawn, keep the position struct (gas consideration)
        // User can still query it, just with 0 shares

        // Calculate proportional amount withdrawn
        uint256 proportionalAmount = (position.amount * sharesToWithdraw) / (position.shares + sharesToWithdraw);
        position.amount -= proportionalAmount;

        // ========== INTERACTIONS ==========
        // Burn shares and receive assets
        uint256 receivedAssets = VAULT_MANAGER.withdraw(
            position.token,
            sharesToWithdraw,
            address(this)
        );

        // Calculate final amount after penalty
        uint256 finalAmount = receivedAssets > penalty ? receivedAssets - penalty : 0;

        // Transfer to user
        if (finalAmount > 0) {
            IERC20(position.token).safeTransfer(msg.sender, finalAmount);
        }

        // If there's a penalty, it stays in the vault (redistributed to other depositors)
        if (penalty > 0) {
            // Transfer penalty back to vault as yield
            IERC20(position.token).safeTransfer(address(VAULT_MANAGER), penalty);
            VAULT_MANAGER.distributeYield(position.token, penalty);
        }

        emit Withdraw(
            msg.sender,
            position.token,
            finalAmount,
            sharesToWithdraw,
            positionId,
            penalty
        );
    }

    // ==================== View Functions ====================

    /**
     * @notice Get user's position details
     * @param user User address
     * @param positionId Position ID
     */
    function getPosition(
        address user,
        uint256 positionId
    ) external view returns (Position memory) {
        return userPositions[user][positionId];
    }

    /**
     * @notice Get user's total positions count
     */
    function getUserPositionCount(address user) external view returns (uint256) {
        return userPositionCount[user];
    }

    /**
     * @notice Calculate current value of position including yield
     * @dev Converts shares to current asset value based on vault exchange rate
     */
    function getPositionValue(
        address user,
        uint256 positionId
    ) external view returns (uint256) {
        Position memory position = userPositions[user][positionId];
        if (position.shares == 0) return 0;

        // Get current value of shares (includes accumulated yield)
        return VAULT_MANAGER.convertToAssets(position.token, position.shares);
    }

    /**
     * @notice Calculate early withdrawal penalty for a position
     * @return penalty Penalty amount in tokens
     */
    function calculatePenalty(
        address user,
        uint256 positionId
    ) external view returns (uint256 penalty) {
        Position memory position = userPositions[user][positionId];
        if (position.shares == 0) return 0;

        // Check if lock period ended
        if (block.timestamp >= position.lockEndTimestamp) {
            return 0; // No penalty
        }

        // Calculate time elapsed and remaining
        uint256 timeElapsed = block.timestamp - position.depositTimestamp;
        uint256 timeRemaining = position.lockEndTimestamp - block.timestamp;

        // Calculate accrued interest
        uint256 accruedInterest = TIER_MANAGER.calculateInterest(
            position.amount,
            position.tier,
            timeElapsed
        );

        // Calculate penalty
        penalty = TIER_MANAGER.calculatePenalty(
            accruedInterest,
            position.tier,
            timeRemaining
        );

        // Ensure penalty doesn't exceed accrued interest
        if (penalty > accruedInterest) {
            penalty = accruedInterest;
        }
    }

    // ==================== Admin Functions ====================

    /**
     * @notice Add or remove supported token
     * @param token Token address
     * @param supported Whether token should be supported
     */
    function setSupportedToken(
    address token,
    bool supported
) external onlyOwner {
    if (token == address(0)) revert Errors.ZeroAddress();
    if (supportedTokens[token] == supported) {
        if (supported) {
            revert Errors.TokenAlreadySupported();
        } else {
            revert Errors.TokenNotSupported();
        }
    }

    supportedTokens[token] = supported;
    emit TokenSupported(token, supported);
}

    /**
     * @notice Pause/unpause deposits and withdrawals
     * @param paused True to pause, false to unpause
     */
    function setPaused(bool paused) external onlyOwner {
        if (paused) {
            _pause();
        } else {
            _unpause();
        }
    }

    /**
     * @notice Emergency withdraw - admin only, bypasses locks
     * @param token Token to withdraw
     * @dev Should only be used in emergencies (contract migration, critical bug)
     */
    function emergencyWithdraw(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) revert Errors.InsufficientBalance();

        IERC20(token).safeTransfer(msg.sender, balance);
        emit EmergencyWithdraw(msg.sender, token, balance);
    }

    // ==================== Referral System ====================

    /// @notice Referral code registry: code => referrer address
    mapping(bytes32 => address) public referralCodes;

    /**
     * @notice Register a referral code
     * @param code Referral code (must be unique)
     */
    function registerReferralCode(bytes32 code) external {
        if (code == bytes32(0)) revert Errors.InvalidReferralCode();
        if (referralCodes[code] != address(0)) revert Errors.ReferralCodeAlreadyExists();

        referralCodes[code] = msg.sender;
    }

    /**
     * @notice Get referrer for a code
     * @param code Referral code
     * @return referrer Address of referrer (address(0) if code doesn't exist)
     */
    function getReferrer(bytes32 code) external view returns (address referrer) {
        return referralCodes[code];
    }
}