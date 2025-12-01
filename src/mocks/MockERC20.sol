// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @notice Mock ERC20 token for testing purposes
 * @dev Allows anyone to mint tokens for testing
 */
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    /**
     * @notice Create a new mock token
     * @param name Token name
     * @param symbol Token symbol
     * @param decimals_ Token decimals (6, 8, or 18 typically)
     */
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    /**
     * @notice Mint tokens to any address
     * @param to Address to receive tokens
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens from any address
     * @param from Address to burn from
     * @param amount Amount to burn
     */
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    /**
     * @notice Override decimals function
     */
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}