// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Bank} from "../src/Bank.sol";
import {VaultManager} from "../src/VaultManager.sol";
import {TierManager} from "../src/TierManager.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/**
 * @title BaseTest
 * @notice Base test contract with common setup and utilities
 * @dev All test contracts should inherit from this
 */
contract BaseTest is Test {
    // Contracts
    Bank public bank;
    VaultManager public vaultManager;
    TierManager public tierManager;

    // Mock tokens
    MockERC20 public usdc;
    MockERC20 public dai;
    MockERC20 public weth;

    // Test users
    address public alice;
    address public bob;
    address public carol;
    address public owner;

    // Constants
    uint256 public constant INITIAL_BALANCE = 1_000_000e18;
    uint256 public constant MIN_DEPOSIT = 1000;

    /**
     * @notice Set up test environment
     * @dev Called before each test
     */
    function setUp() public virtual {
        // Create test users
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");
        owner = address(this);

        // Deploy mock tokens with different decimals
        usdc = new MockERC20("USD Coin", "USDC", 6);
        dai = new MockERC20("Dai Stablecoin", "DAI", 18);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);

        // Deploy contracts in correct order
        _deployContracts();

        // Setup tokens
        _setupTokens();
    }

    /**
     * @notice Deploy all contracts with correct dependencies
     * @dev Simple approach: Calculate Bank address beforehand
     */
    function _deployContracts() internal {
        // Deploy TierManager (no dependencies)
        tierManager = new TierManager();

        // Calculate what the Bank address will be
        // The next contract deployed by this contract will be at this address
        address predictedBankAddress = _predictNextAddress(address(this), vm.getNonce(address(this)) + 1);

        // Deploy VaultManager with predicted Bank address
        vaultManager = new VaultManager(predictedBankAddress);

        // Deploy Bank (should match predicted address)
        bank = new Bank(address(vaultManager), address(tierManager));

        // Verify addresses match
        require(address(bank) == predictedBankAddress, "Bank address mismatch");
    }

    /**
     * @notice Predict Next address
     */
    function _predictNextAddress(address deployer, uint256 nonce) internal pure returns (address) {
        if (nonce == 0x00) return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), deployer, bytes1(0x80))))));
        if (nonce <= 0x7f) return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), deployer, uint8(nonce))))));
        if (nonce <= 0xff) return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd7), bytes1(0x94), deployer, bytes1(0x81), uint8(nonce))))));
        if (nonce <= 0xffff) return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd8), bytes1(0x94), deployer, bytes1(0x82), uint16(nonce))))));
        if (nonce <= 0xffffff) return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd9), bytes1(0x94), deployer, bytes1(0x83), uint24(nonce))))));
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xda), bytes1(0x94), deployer, bytes1(0x84), uint32(nonce))))));
    }

    /**
     * @notice Setup mock tokens and mint to test users
     */
    function _setupTokens() internal {
        // Mint tokens to test users
        usdc.mint(alice, INITIAL_BALANCE / 1e12); // Adjust for 6 decimals
        usdc.mint(bob, INITIAL_BALANCE / 1e12);
        usdc.mint(carol, INITIAL_BALANCE / 1e12);

        dai.mint(alice, INITIAL_BALANCE);
        dai.mint(bob, INITIAL_BALANCE);
        dai.mint(carol, INITIAL_BALANCE);

        weth.mint(alice, INITIAL_BALANCE);
        weth.mint(bob, INITIAL_BALANCE);
        weth.mint(carol, INITIAL_BALANCE);

        // Add tokens as supported in Bank
        bank.setSupportedToken(address(usdc), true);
        bank.setSupportedToken(address(dai), true);
        bank.setSupportedToken(address(weth), true);
    }

    /**
     * @notice Helper to approve and deposit
     */
    function _approveAndDeposit(
        address user,
        address token,
        uint256 amount,
        uint8 tier
    ) internal returns (uint256 positionId) {
        vm.startPrank(user);
        MockERC20(token).approve(address(bank), amount);
        positionId = bank.deposit(token, amount, tier, bytes32(0));
        vm.stopPrank();
    }

    /**
     * @notice Helper to get position value
     */
    function _getPositionValue(
        address user,
        uint256 positionId
    ) internal view returns (uint256) {
        return bank.getPositionValue(user, positionId);
    }

    /**
     * @notice Helper to time travel
     */
    function _warp(uint256 time) internal {
        vm.warp(block.timestamp + time);
    }

    /**
     * @notice Helper to calculate expected interest
     */
    function _calculateExpectedInterest(
        uint256 principal,
        uint8 tier,
        uint256 duration
    ) internal view returns (uint256) {
        return tierManager.calculateInterest(principal, tier, duration);
    }
}