# 🏦 VaultForge - Multi-Token Crypto Savings Bank

A production-ready Solidity protocol implementing a multi-token savings bank with tiered lock periods, dynamic yields, and penalty-based incentives.

[![Solidity](https://img.shields.io/badge/Solidity-0.8.30-363636?style=flat-square&logo=solidity)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Foundry-✓-blue?style=flat-square)](https://getfoundry.sh/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](https://opensource.org/licenses/MIT)

## 🌟 Overview

VaultForge is a sophisticated DeFi savings protocol that allows users to deposit ERC20 tokens with varying lock periods in exchange for tiered APY rewards. The protocol implements advanced security patterns, economic incentives, and a share-based accounting system inspired by ERC4626.

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

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test testDeposit

# Coverage report
forge coverage
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

- **Unit Tests**: Individual function testing
- **Integration Tests**: Full deposit → withdraw flows
- **Fuzz Tests**: Randomized input testing
- **Invariant Tests**: Protocol-level guarantees
- **Attack Simulations**: Reentrancy, inflation, etc.

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
│   ├── unit/
│   ├── integration/
│   └── fuzzing/
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
```

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

## 📊 Gas Estimates

| Function           | Gas Cost (approx) |
| ------------------ | ----------------- |
| deposit()          | ~180k gas         |
| withdraw()         | ~150k gas         |
| getPositionValue() | ~3k gas (view)    |
| calculatePenalty() | ~2k gas (view)    |

_Note: Gas costs vary based on token decimals, first deposit, etc._

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

Your Name - [@yourtwitter](https://twitter.com/yourtwitter)

Project Link: [https://github.com/yourusername/vault-forge-crypto-bank](https://github.com/enricrypto/vault-forge-crypto-bank)

---

**⭐ If you find this project useful, please consider giving it a star!**
