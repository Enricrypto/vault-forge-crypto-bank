// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IVaultManager
 * @notice Interface for managing individual token vaults
 * @dev Handles share calculations and vault accounting per token
 */
interface IVaultManager {
    // ==================== Events ====================
    
    event VaultCreated(address indexed token);
    event SharesMinted(address indexed token, address indexed user, uint256 shares, uint256 assets);
    event SharesBurned(address indexed token, address indexed user, uint256 shares, uint256 assets);
    event YieldDistributed(address indexed token, uint256 amount);
    
    // ==================== Vault Functions ====================
    
    /**
     * @notice Create a new vault for a token
     * @param token Token address
     */
    function createVault(address token) external;
    
    /**
     * @notice Deposit assets and mint shares
     * @param token Token address
     * @param assets Amount of assets to deposit
     * @param receiver Address to receive shares
     * @return shares Amount of shares minted
     */
    function deposit(
        address token,
        uint256 assets,
        address receiver
    ) external returns (uint256 shares);
    
    /**
     * @notice Burn shares and withdraw assets
     * @param token Token address
     * @param shares Amount of shares to burn
     * @param receiver Address to receive assets
     * @return assets Amount of assets withdrawn
     */
    function withdraw(
        address token,
        uint256 shares,
        address receiver
    ) external returns (uint256 assets);
    
    /**
     * @notice Distribute yield to a vault (increases share value)
     * @param token Token address
     * @param yieldAmount Amount of yield to distribute
     */
    function distributeYield(address token, uint256 yieldAmount) external;
    
    // ==================== View Functions ====================
    
    /**
     * @notice Convert assets to shares
     */
    function convertToShares(address token, uint256 assets) external view returns (uint256 shares);
    
    /**
     * @notice Convert shares to assets
     */
    function convertToAssets(address token, uint256 shares) external view returns (uint256 assets);
    
    /**
     * @notice Get total assets in vault
     */
    function totalAssets(address token) external view returns (uint256);
    
    /**
     * @notice Get total shares in vault
     */
    function totalShares(address token) external view returns (uint256);
    
    /**
     * @notice Get user's share balance
     */
    function balanceOf(address token, address user) external view returns (uint256);
    
    /**
     * @notice Check if vault exists
     */
    function vaultExists(address token) external view returns (bool);
}