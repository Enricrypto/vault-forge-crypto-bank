## 🏦 VaultForge - Multi-Token Crypto Savings Bank

A multi-token crypto savings protocol with tiered lock periods, dynamic yields, and penalty-based incentives.

[![Solidity](https://img.shields.io/badge/Solidity-^0.8.20-363636?style=flat-square)]
[![Foundry](https://img.shields.io/badge/Tested%20With-Foundry-red?style=flat-square)]
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)]
[![Tests](https://img.shields.io/badge/Tests-131%20Passing-brightgreen?style=flat-square)]()

## 🌟 Overview

VaultForge is a sophisticated DeFi savings protocol that allows users to deposit ERC20 tokens with varying lock periods in exchange for tiered APY rewards. The protocol implements advanced security patterns, economic incentives, and a share-based accounting system inspired by ERC4626.

## 🎯 Technical Highlights

**What makes this project stand out:**

- **131+ Comprehensive Tests**: Full unit, integration, and edge case coverage with 100% pass rate
- **Production-Grade Architecture**: ERC4626-inspired vault system with multi-token support
- **Security-First Design**: Multiple attack mitigations including first depositor protection
- **Gas Optimized**: All contracts well under 24KB limit (Bank: 6.8KB, others <4KB)
- **Real-World Economics**: Penalty redistribution mechanism incentivizes long-term deposits
- **Extensive Documentation**: Every contract fully documented with NatSpec

**Perfect for demonstrating:**

- Advanced Solidity patterns (ERC4626, share accounting, penalty systems)
- Comprehensive testing strategies (unit + integration + edge cases)
- DeFi protocol design and tokenomics
- Security-conscious development practices

### Key Features

- 🔐 **Multi-Token Support** - Deposit any ERC20 token
- ⏰ **Tiered Lock Periods** - 4 tiers from instant liquidity to 180-day locks
- 📈 **Dynamic APY** - Up to 8% APY for longer commitments
- 💰 **Penalty Redistribution** - Early withdrawal penalties benefit remaining depositors
- 🤝 **Referral System** - Built-in incentives for user growth
- 🛡️ **Battle-Tested Security** - Multiple security patterns and attack mitigations

## 📊 Lock Tiers & APY

| Tier | Lock Period | APY | Early Penalty   | Use Case               |
| ---- | ----------- | --- | --------------- | ---------------------- |
| 0    | No lock     | 0%  | None            | Instant liquidity      |
| 1    | 30 days     | 2%  | 50% of interest | Short-term savings     |
| 2    | 90 days     | 5%  | 50% of interest | Medium-term commitment |
| 3    | 180 days    | 8%  | 50% of interest | Maximum returns        |

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────┐
│                   Bank.sol                      │
│         (Main User-Facing Contract)             │
│  • Deposits & Withdrawals                       │
│  • Position Management                          │
│  • Referral System                              │
└───────────────┬─────────────────┬───────────────┘
                │                 │
        ┌───────▼──────┐   ┌──────▼──────┐
        │ VaultManager │   │ TierManager │
        │              │   │             │
        │ • Share      │   │ • APY       │
        │   Accounting │   │   Calculation│
        │ • Yield      │   │ • Penalties │
        │   Distribution│   │ • Lock Logic│
        └──────────────┘   └─────────────┘
```

### Core Contracts

1. **Bank.sol** (384 lines)

   - User deposits and withdrawals
   - Position tracking with NFT-like IDs
   - Early withdrawal penalty enforcement
   - Emergency pause functionality

2. **VaultManager.sol** (315 lines)

   - ERC4626-inspired share-based accounting
   - Multi-token vault management
   - First depositor attack mitigation
   - Yield distribution mechanism

3. **TierManager.sol** (265 lines)
   - Lock period configuration
   - Interest calculations (simple interest)
   - Penalty computation
   - Admin tier management

## 🔒 Security Features

### Implemented Protections

- ✅ **ReentrancyGuard** on all state-changing functions
- ✅ **CEI Pattern** (Checks-Effects-Interactions)
- ✅ **SafeERC20** for all token transfers
- ✅ **Access Control** (Ownable, custom modifiers)
- ✅ **Pausable** for emergency stops
- ✅ **First Depositor Attack Mitigation** (DEAD_SHARES)
- ✅ **MIN_DEPOSIT** protection against dust/griefing
- ✅ **Penalty Caps** (never exceeds accrued interest)

### Attack Vectors Considered

- First depositor vault inflation
- Reentrancy attacks
- Flash loan exploits
- Rounding errors and precision loss
- Integer overflow/underflow
- Front-running scenarios
- Dust deposit griefing

## 🚀 Getting Started

### Prerequisites

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/vault-forge-crypto-bank.git
cd vault-forge-crypto-bank

# Install dependencies
forge install

# Build contracts
forge build
```

### Testing

### Testing

```bash
# Run all tests (131+ tests)
forge test

# Run with verbosity to see details
forge test -vvv

# Run specific test suite
forge test --match-contract BankTest
forge test --match-contract VaultManagerTest
forge test --match-contract TierManagerTest
forge test --match-contract IntegrationTest

# Run specific test
forge test --match-test test_Deposit_Success

# Check contract sizes
forge build --sizes

# Gas report
forge test --gas-report
```

**Expected Output:**

```
Ran 131 tests for test/integration/Integration.t.sol:IntegrationTest
[PASS] (131/131 tests passed)
```

## 📖 Usage Example

```solidity
// 1. Deploy contracts
VaultManager vaultManager = new VaultManager(address(bank));
TierManager tierManager = new TierManager();
Bank bank = new Bank(address(vaultManager), address(tierManager));

// 2. Enable a token
bank.setSupportedToken(address(usdc), true);

// 3. User deposits 1000 USDC for 90 days (Tier 2)
usdc.approve(address(bank), 1000e6);
uint256 positionId = bank.deposit(
    address(usdc),
    1000e6,
    2, // Tier 2 (90 days, 5% APY)
    0  // No referral code
);

// 4. Check position value after 30 days
uint256 currentValue = bank.getPositionValue(msg.sender, positionId);
// currentValue ≈ 1004.11 USDC (1000 + ~1.37% interest for 30/365 days)

// 5. Withdraw (with penalty if early)
bank.withdraw(positionId, 0); // 0 = withdraw all shares
```

## 🧪 Testing Strategy

### Test Coverage

### Test Coverage: 131+ Tests - 100% Passing ✅

| Test Suite             | Tests     | Coverage                                          |
| ---------------------- | --------- | ------------------------------------------------- |
| **Bank.t.sol**         | 25 tests  | Deposits, withdrawals, referrals, admin functions |
| **VaultManager.t.sol** | 30 tests  | Share accounting, DEAD_SHARES, yield distribution |
| **TierManager.t.sol**  | 60+ tests | Interest calculations, penalties, lock periods    |
| **Integration.t.sol**  | 16 tests  | End-to-end user flows, multi-user scenarios       |

**Test Categories:**

- ✅ **Unit Tests**: Individual function testing
- ✅ **Integration Tests**: Full deposit → withdraw flows
- ✅ **Edge Cases**: Rounding, very large amounts, many users
- ✅ **Attack Simulations**: Reentrancy, inflation, dust attacks

### Target Coverage: 95%+

## 📁 Project Structure

```
vault-forge-crypto-bank/
├── src/
│   ├── Bank.sol                    # Main entry point
│   ├── core/
│   │   ├── VaultManager.sol        # Share accounting
│   │   └── TierManager.sol         # Lock period logic
│   ├── interfaces/
│   │   ├── IBank.sol
│   │   ├── IVaultManager.sol
│   │   └── ITierManager.sol
│   └── libraries/
│       └── Errors.sol              # Custom errors
├── test/
│   ├── BaseTest.sol              # Test helper with setup
│   ├── unit/
│   │   ├── Bank.t.sol            # 25 tests
│   │   ├── VaultManager.t.sol    # 30 tests
│   │   └── TierManager.t.sol     # 60+ tests
│   └── integration/
│       └── Integration.t.sol     # 16 tests
├── script/
│   └── Deploy.s.sol
├── docs/
│   ├── Bank_DOCUMENTATION.md
│   ├── VaultManager_DOCUMENTATION.md
│   └── TierManager_DOCUMENTATION.md
└── README.md
```

## 🔧 Configuration

### Default Settings

```solidity
MIN_DEPOSIT = 1000 wei              // Prevents dust attacks
DEAD_SHARES = 1000                  // First depositor mitigation
MIN_FIRST_DEPOSIT = 1e6            // Minimum first deposit per vault
BASIS_POINTS = 10_000              // 100% = 10,000 basis points
EARLY_WITHDRAWAL_PENALTY = 5000    // 50% penalty on interest
MAX_TIERS = 4                      // Number of lock tiers
```

### Contract Sizes (Optimized)

| Contract     | Size   | Limit | Status |
| ------------ | ------ | ----- | ------ |
| Bank         | 6.8 KB | 24 KB | ✅     |
| VaultManager | 3.9 KB | 24 KB | ✅     |
| TierManager  | 3.1 KB | 24 KB | ✅     |

All contracts well under the 24KB Spurious Dragon limit.

## 🚧 Roadmap

### Phase 1: Core Protocol ✅

- [x] Multi-token vault system
- [x] Tiered lock periods
- [x] Penalty mechanism
- [x] Referral system

### Phase 2: Advanced Features (Future)

- [ ] FeeCollector integration
- [ ] YieldRouter for external strategies
- [ ] Governance system
- [ ] NFT position tokens

### Phase 3: Optimization (Future)

- [ ] Gas optimizations
- [ ] L2 deployment
- [ ] Cross-chain support

## ⛽ Gas Benchmarks

### Bank.sol Gas Costs

| Function                 | Min Gas | Average Gas | Max Gas | Description                                    |
| ------------------------ | ------- | ----------- | ------- | ---------------------------------------------- |
| `deposit()`              | 29,473  | **293,036** | 395,075 | First deposit costs more due to vault creation |
| `withdraw()`             | 31,246  | **89,017**  | 113,556 | Varies by shares withdrawn                     |
| `getPositionValue()`     | 25,858  | **25,858**  | 25,858  | View function (read-only)                      |
| `calculatePenalty()`     | 15,582  | **22,800**  | 30,019  | View function (read-only)                      |
| `registerReferralCode()` | 21,580  | **38,196**  | 44,326  | One-time registration                          |
| `setSupportedToken()`    | 24,250  | **47,921**  | 48,127  | Admin function                                 |

### VaultManager.sol Gas Costs

| Function            | Min Gas | Average Gas | Max Gas | Description                       |
| ------------------- | ------- | ----------- | ------- | --------------------------------- |
| `deposit()`         | 27,557  | **109,174** | 147,995 | Higher on first deposit per token |
| `withdraw()`        | 27,498  | **45,871**  | 73,253  | Share burning and transfer        |
| `createVault()`     | 21,613  | **47,997**  | 49,932  | One-time per token                |
| `distributeYield()` | 27,209  | **29,316**  | 33,477  | Yield redistribution              |
| `convertToAssets()` | 2,662   | **7,127**   | 7,340   | View function                     |

### TierManager.sol Gas Costs

| Function                      | Min Gas | Average Gas | Max Gas | Description    |
| ----------------------------- | ------- | ----------- | ------- | -------------- |
| `calculateInterest()`         | 528     | **9,095**   | 9,558   | View function  |
| `calculatePenalty()`          | 464     | **3,816**   | 9,300   | View function  |
| `getLockEndTimestamp()`       | 483     | **7,244**   | 9,235   | View function  |
| `configureTier()`             | 24,279  | **31,479**  | 43,852  | Admin function |
| `canWithdrawWithoutPenalty()` | 522     | **8,153**   | 9,278   | View function  |

### Deployment Costs

| Contract         | Deployment Gas | Contract Size |
| ---------------- | -------------- | ------------- |
| **Bank**         | 1,571,824      | 7.36 KB       |
| **VaultManager** | 944,392        | 4.26 KB       |
| **TierManager**  | 1,047,846      | 4.01 KB       |

### Gas Optimization Notes

- ✅ **First deposits are expensive** (~395k gas) due to DEAD_SHARES mechanism and vault initialization
- ✅ **Subsequent deposits are cheaper** (~180k gas average)
- ✅ **View functions are highly optimized** (<10k gas for most calculations)
- ✅ **Withdrawals scale efficiently** with position size
- ✅ **All contracts under 24KB** Spurious Dragon limit

_Generated via `forge test --gas-report` on 131 test cases_

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⚠️ Disclaimer

This code is provided as-is for educational and portfolio purposes. It has not been audited. Do not use in production with real funds without a professional security audit.

## 🙏 Acknowledgments

- Inspired by [ERC4626](https://eips.ethereum.org/EIPS/eip-4626) vault standard
- Built with [Foundry](https://getfoundry.sh/)
- Uses [OpenZeppelin](https://openzeppelin.com/) contracts
- Security patterns from [Consensys Best Practices](https://consensys.github.io/smart-contract-best-practices/)

## 📧 Contact

Enricrypto - [GitHub](https://github.com/Enricrypto)

Project Link: [https://github.com/Enricrypto/vault-forge-crypto-bank](https://github.com/Enricrypto/vault-forge-crypto-bank)

---

**⭐ If you find this project useful, please consider giving it a star!**
