// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IVaultManager} from "./interfaces/IVaultManager.sol";
import {Errors} from "./libraries/Errors.sol";

/**
 * @title VaultManager
 * @notice Manages individual token vaults with share-based accounting
 * @dev ERC4626-inspired vault implementation with multi-token support
 * 
 * Security considerations:
 * - First depositor attack mitigation via DEAD_SHARES
 * - ReentrancyGuard on state-changing functions
 * - Proper rounding (favors vault on deposits, users on withdrawals)
 * - Access control for vault creation
 */
contract VaultManager is IVaultManager, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // ==================== Structs ====================

    /**
     * @notice Vault data for a single token
     * @param totalAssets Total assets deposited in vault
     * @param totalShares Total shares issued
     * @param exists Whether vault has been created
     */
    struct Vault {
        uint256 totalAssets;
        uint256 totalShares;
        bool exists;
    }

    // ==================== State Variables ====================

    /// @notice Mapping of token => Vault data
    mapping(address => Vault) private vaults;

    /// @notice Mapping of token => user => share balance
    mapping(address => mapping(address => uint256)) private shareBalances;

    /// @notice Bank contract address (only Bank can call deposit/withdraw)
    address public immutable BANK;

    /**
     * @notice Dead shares minted on first deposit to prevent inflation attack
     * @dev First depositor receives (shares - DEAD_SHARES), rest are burned to address(0)
     */
    uint256 private constant DEAD_SHARES = 1000;

    /**
     * @notice Minimum assets required for first deposit
     * @dev Prevents dust deposits and first depositor attack
     */
    uint256 private constant MIN_FIRST_DEPOSIT = 1e6;

    // ==================== Modifiers ====================

    modifier onlyBank() {
        _onlyBank();
        _;
    }

    function _onlyBank() internal view {
        if (msg.sender != BANK) revert Errors.Unauthorized();
    }

    // ==================== Constructor ====================

    /**
     * @notice Initialize VaultManager
     * @param _bank Bank contract address
     */
    constructor(address _bank) Ownable(msg.sender) {
        if (_bank == address(0)) revert Errors.ZeroAddress();
        BANK = _bank;
    }

    // ==================== Vault Functions ====================

    /**
     * @notice Create a new vault for a token
     * @param token Token address
     * @dev Can be called by anyone, but typically called by Bank
     */
    function createVault(address token) external {
        if (token == address(0)) revert Errors.ZeroAddress();
        if (vaults[token].exists) revert Errors.TokenAlreadySupported();

        vaults[token] = Vault({
            totalAssets: 0,
            totalShares: 0,
            exists: true
        });

        emit VaultCreated(token);
    }

    /**
     * @notice Deposit assets and mint shares
     * @param token Token address
     * @param assets Amount of assets to deposit
     * @param receiver Address to receive shares
     * @return shares Amount of shares minted
     * 
     * @dev First deposit mints DEAD_SHARES to address(0) to prevent inflation attack
     *      Follows CEI pattern
     */
    function deposit(
        address token,
        uint256 assets,
        address receiver
    ) external nonReentrant onlyBank returns (uint256 shares) {
        if (assets == 0) revert Errors.ZeroAmount();
        if (receiver == address(0)) revert Errors.ZeroAddress();
        if (!vaults[token].exists) revert Errors.VaultDoesNotExist();

        Vault storage vault = vaults[token];

        // Calculate shares to mint
        if (vault.totalShares == 0) {
            // First deposit - mint DEAD_SHARES to prevent inflation attack
            if (assets < MIN_FIRST_DEPOSIT) revert Errors.InvalidAmount();
            
            shares = assets;
            
            // Burn DEAD_SHARES to address(0)
            vault.totalShares = DEAD_SHARES;
            shareBalances[token][address(0)] = DEAD_SHARES;
            
            // User receives (shares - DEAD_SHARES)
            shares = assets - DEAD_SHARES;
        } else {
            // Subsequent deposits - calculate proportional shares
            // shares = (assets * totalShares) / totalAssets
            // Round DOWN (favors vault)
            shares = (assets * vault.totalShares) / vault.totalAssets;
            
            if (shares == 0) revert Errors.InvalidAmount();
        }

        // Update state
        vault.totalAssets += assets;
        vault.totalShares += shares;
        shareBalances[token][receiver] += shares;

        emit SharesMinted(token, receiver, shares, assets);
    }

    /**
     * @notice Burn shares and withdraw assets
     * @param token Token address
     * @param shares Amount of shares to burn
     * @param receiver Address to receive assets
     * @return assets Amount of assets withdrawn
     * 
     * @dev Rounds DOWN on asset calculation (favors vault)
     */
    function withdraw(
        address token,
        uint256 shares,
        address receiver
    ) external nonReentrant onlyBank returns (uint256 assets) {
        if (shares == 0) revert Errors.ZeroAmount();
        if (receiver == address(0)) revert Errors.ZeroAddress();
        if (!vaults[token].exists) revert Errors.VaultDoesNotExist();

        Vault storage vault = vaults[token];

        // Note: We don't check shareBalances here because Bank manages that
        // Bank should ensure user has enough shares before calling

        // Calculate assets to return
        // assets = (shares * totalAssets) / totalShares
        // Round DOWN (favors vault, prevents draining)
        assets = (shares * vault.totalAssets) / vault.totalShares;

        if (assets == 0) revert Errors.InvalidAmount();
        if (assets > vault.totalAssets) revert Errors.InsufficientBalance();

        // Update state (CEI pattern)
        vault.totalAssets -= assets;
        vault.totalShares -= shares;
        // Note: shareBalances NOT updated here - Bank manages user shares

        // Transfer assets to receiver
        IERC20(token).safeTransfer(receiver, assets);

        emit SharesBurned(token, receiver, shares, assets);
    }

    /**
     * @notice Distribute yield to a vault (increases share value)
     * @param token Token address
     * @param yieldAmount Amount of yield to distribute
     * 
     * @dev Called when penalties are collected or external yield is added
     *      Increases totalAssets without minting shares (increases share price)
     */
    function distributeYield(
        address token,
        uint256 yieldAmount
    ) external nonReentrant onlyBank {
        if (yieldAmount == 0) revert Errors.ZeroAmount();
        if (!vaults[token].exists) revert Errors.VaultDoesNotExist();

        Vault storage vault = vaults[token];

        // Increase total assets (share price goes up)
        vault.totalAssets += yieldAmount;

        emit YieldDistributed(token, yieldAmount);
    }

    // ==================== View Functions ====================

    /**
     * @notice Convert assets to shares
     * @dev Uses current exchange rate
     *      Round DOWN (favors vault on deposits)
     */
    function convertToShares(
        address token,
        uint256 assets
    ) external view returns (uint256 shares) {
        if (!vaults[token].exists) return 0;

        Vault memory vault = vaults[token];

        if (vault.totalShares == 0) {
            // First deposit scenario
            return assets > DEAD_SHARES ? assets - DEAD_SHARES : 0;
        }

        // shares = (assets * totalShares) / totalAssets
        shares = (assets * vault.totalShares) / vault.totalAssets;
    }

    /**
     * @notice Convert shares to assets
     * @dev Uses current exchange rate
     *      Round DOWN (prevents over-withdrawal)
     */
    function convertToAssets(
        address token,
        uint256 shares
    ) external view returns (uint256 assets) {
        if (!vaults[token].exists) return 0;

        Vault memory vault = vaults[token];

        if (vault.totalShares == 0) return 0;

        // assets = (shares * totalAssets) / totalShares
        assets = (shares * vault.totalAssets) / vault.totalShares;
    }

    /**
     * @notice Get total assets in vault
     */
    function totalAssets(address token) external view returns (uint256) {
        return vaults[token].totalAssets;
    }

    /**
     * @notice Get total shares in vault
     */
    function totalShares(address token) external view returns (uint256) {
        return vaults[token].totalShares;
    }

    /**
     * @notice Get user's share balance
     * @dev Note: Bank tracks actual user positions, this is just accounting
     */
    function balanceOf(
        address token,
        address user
    ) external view returns (uint256) {
        return shareBalances[token][user];
    }

    /**
     * @notice Check if vault exists
     */
    function vaultExists(address token) external view returns (bool) {
        return vaults[token].exists;
    }

    // ==================== Admin Functions ====================

    /**
     * @notice Emergency function to recover stuck tokens
     * @param token Token to recover
     * @param amount Amount to recover
     * @dev Should only be used if tokens are sent directly to contract by mistake
     */
    function recoverTokens(
        address token,
        uint256 amount
    ) external onlyOwner {
        if (token == address(0)) revert Errors.ZeroAddress();
        if (amount == 0) revert Errors.ZeroAmount();

        // Don't allow recovering tokens that belong to vaults
        if (vaults[token].exists) {
            uint256 excess = IERC20(token).balanceOf(address(this)) - vaults[token].totalAssets;
            if (amount > excess) revert Errors.InsufficientBalance();
        }

        IERC20(token).safeTransfer(msg.sender, amount);
    }
}