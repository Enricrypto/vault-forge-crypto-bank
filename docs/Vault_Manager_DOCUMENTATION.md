# VaultManager.sol - Implementation Documentation

## Overview

Manages individual token vaults with share-based accounting. Inspired by ERC4626 but adapted for multi-token support. Handles the core mathematics of converting deposits to shares and calculating withdrawals.

---

## Architecture

### Share-Based Accounting Model

VaultManager uses a **share-based system** similar to ERC4626:

```
Share Price = Total Assets / Total Shares

On Deposit:
  shares = (assets * totalShares) / totalAssets

On Withdraw:
  assets = (shares * totalAssets) / totalShares
```

As yield is distributed, `totalAssets` increases without minting shares, causing share price to increase.

---

## Key Features

### 1. **First Depositor Attack Mitigation** (Lines 111-150)

**The Problem:**
In share-based vaults, the first depositor can manipulate the exchange rate by:

1. Depositing 1 wei
2. Directly transferring large amounts to vault
3. Causing extreme rounding errors for subsequent depositors

**Our Solution:**

```solidity
uint256 private constant DEAD_SHARES = 1000;
uint256 private constant MIN_FIRST_DEPOSIT = 1e6; // 1 million wei

// First deposit burns DEAD_SHARES to address(0)
// User receives (assets - DEAD_SHARES)
// This makes the attack economically unfeasible
```

**Why This Works:**

- Attacker would need to donate 1000+ shares worth of value
- Makes manipulation cost exceed potential profit
- Industry-standard mitigation (used by Yearn, etc.)

---

### 2. **Vault Creation** (Lines 88-99)

```solidity
function createVault(address token) external
```

**Features:**

- Can be called by anyone (permissionless)
- Typically called automatically by Bank on first deposit
- Initializes vault with zero assets/shares

**Design Decision:**
Permissionless creation allows flexibility but Bank typically manages this to ensure proper initialization.

---

### 3. **Deposit Flow** (Lines 111-150)

```solidity
function deposit(
    address token,
    uint256 assets,
    address receiver
) external nonReentrant onlyBank returns (uint256 shares)
```

**Access Control:**

- `onlyBank` modifier - only Bank contract can call
- Prevents direct vault manipulation

**First Deposit Special Case:**

```solidity
if (vault.totalShares == 0) {
    // Mint DEAD_SHARES to address(0)
    vault.totalShares = DEAD_SHARES;
    shareBalances[token][address(0)] = DEAD_SHARES;

    // User receives (assets - DEAD_SHARES)
    shares = assets - DEAD_SHARES;
}
```

**Subsequent Deposits:**

```solidity
shares = (assets * vault.totalShares) / vault.totalAssets;
```

- Rounds DOWN (favors vault slightly)
- Prevents share inflation attacks

---

### 4. **Withdraw Flow** (Lines 161-192)

```solidity
function withdraw(
    address token,
    uint256 shares,
    address receiver
) external nonReentrant onlyBank returns (uint256 assets)
```

**Key Logic:**

```solidity
assets = (shares * vault.totalAssets) / vault.totalShares;
```

**Rounding Strategy:**

- Rounds DOWN on asset calculation
- Prevents vault draining through rounding exploitation
- Tiny amounts lost to rounding accumulate in vault (benefits all holders)

**Note:**
VaultManager does NOT track individual user share balances for withdrawals. Bank manages user positions and ensures users have sufficient shares.

---

### 5. **Yield Distribution** (Lines 202-215)

```solidity
function distributeYield(
    address token,
    uint256 yieldAmount
) external nonReentrant onlyBank
```

**How It Works:**

```solidity
vault.totalAssets += yieldAmount;
// totalShares stays the same
// → Share price increases
```

**Sources of Yield:**

1. Early withdrawal penalties (redistributed from Bank)
2. External yield strategies (future feature)
3. Protocol revenue sharing (future feature)

**Example:**

```
Before:
  totalAssets: 1000
  totalShares: 1000
  Share Price: 1.0

Distribute 100 yield:
  totalAssets: 1100
  totalShares: 1000
  Share Price: 1.1

User with 100 shares now owns 110 assets!
```

---

## Security Considerations

### ✅ **Implemented Protections**

1. **Access Control**

   - `onlyBank` modifier on all state-changing functions
   - Only Bank can deposit/withdraw/distribute yield
   - Prevents direct manipulation

2. **First Depositor Attack**

   - DEAD_SHARES mechanism
   - MIN_FIRST_DEPOSIT requirement
   - Makes attack economically unfeasible

3. **Rounding Protection**

   - Always rounds DOWN
   - Favors vault on deposits
   - Prevents draining on withdrawals

4. **ReentrancyGuard**

   - All external state-changing functions protected
   - Prevents reentrancy during transfers

5. **CEI Pattern**

   - Checks → Effects → Interactions
   - State updated before external calls

6. **Integer Overflow**
   - Solidity 0.8+ automatic overflow checks
   - Safe arithmetic guaranteed

---

### ⚠️ **Testing Priorities**

1. **First Deposit Scenarios**

   - Test with MIN_FIRST_DEPOSIT boundary
   - Verify DEAD_SHARES correctly burned
   - Confirm attacker can't profit from manipulation

2. **Rounding Errors**

   - Test with various decimal tokens (6, 8, 18)
   - Very small deposits/withdrawals
   - Extreme ratios (1 wei vs 1M tokens)

3. **Share Price Manipulation**

   - Direct token transfers to vault
   - Flash loan scenarios
   - Sandwich attacks on deposits/withdrawals

4. **Yield Distribution**

   - Multiple yield distributions
   - Verify share price increases correctly
   - Test with different vault sizes

5. **Edge Cases**
   - First depositor withdraws everything
   - Vault with 0 assets but shares exist
   - Maximum uint256 values

---

## State Variables

```solidity
mapping(address => Vault) private vaults;
mapping(address => mapping(address => uint256)) private shareBalances;
address public immutable BANK;
uint256 private constant DEAD_SHARES = 1000;
uint256 private constant MIN_FIRST_DEPOSIT = 1e6;
```

**Gas Optimization:**

- `BANK` is immutable (inline)
- Constants for DEAD_SHARES and MIN_FIRST_DEPOSIT
- Vault struct packs efficiently

---

## View Functions

### Conversion Functions

```solidity
convertToShares(token, assets) → shares
convertToAssets(token, shares) → assets
```

**Use Cases:**

- Preview deposit/withdrawal amounts
- UI display of current values
- Smart contract integrations

### Vault Info

```solidity
totalAssets(token) → uint256
totalShares(token) → uint256
balanceOf(token, user) → uint256
vaultExists(token) → bool
```

---

## Admin Functions

### `recoverTokens()` (Lines 300-314)

**Purpose:**
Emergency recovery of tokens sent directly to contract by mistake

**Protection:**

```solidity
if (vaults[token].exists) {
    uint256 excess = IERC20(token).balanceOf(address(this)) - vaults[token].totalAssets;
    if (amount > excess) revert Errors.InsufficientBalance();
}
```

**Safety:**

- Cannot recover tokens that belong to vaults
- Only recovers "excess" tokens (sent by mistake)
- Owner-only function

---

## Integration with Bank.sol

### Typical Flow

**Deposit:**

```
1. User calls Bank.deposit()
2. Bank transfers tokens to VaultManager
3. Bank calls VaultManager.deposit()
4. VaultManager mints shares
5. Bank stores position with share amount
```

**Withdraw:**

```
1. User calls Bank.withdraw()
2. Bank calls VaultManager.withdraw()
3. VaultManager burns shares, transfers tokens to Bank
4. Bank applies penalties if needed
5. Bank transfers final amount to user
```

**Penalty Redistribution:**

```
1. Bank calculates penalty
2. Bank transfers penalty to VaultManager
3. Bank calls VaultManager.distributeYield()
4. Share price increases for all holders
```

---

## Known Limitations

1. **No Per-User Share Tracking**

   - VaultManager tracks shares in `shareBalances` but Bank is source of truth
   - Bank must ensure users have sufficient shares before withdrawal
   - This separation prevents issues with position tracking

2. **Simple Interest Model**

   - Interest calculated in TierManager, not compounding
   - For compounding, would need to redistribute yield periodically

3. **Rounding Losses**

   - Small rounding losses accumulate in vault
   - Benefits all share holders slightly
   - Negligible in practice but worth testing

4. **No Vault Removal**
   - Once created, vaults cannot be removed
   - Can be worked around by preventing new deposits

---

## Gas Optimization

**Efficient Design:**

- Single SSTORE for vault struct updates
- Immutable BANK address
- Constants for fixed values
- Minimal storage reads in view functions

**Further Optimizations (if needed):**

- Pack Vault struct (already efficient)
- Use unchecked math where overflow impossible
- Batch operations for multiple tokens

---

## Mathematical Properties

### Invariants (for Testing)

1. **Share Conservation:**

   ```
   sum(all user shares) + DEAD_SHARES == totalShares
   ```

2. **Asset Accounting:**

   ```
   totalAssets >= sum(convertToAssets(user shares))
   ```

   (Equality or slight surplus due to rounding)

3. **Monotonic Share Price:**

   ```
   Share price never decreases (except on withdrawal)
   sharePrice = totalAssets / totalShares
   ```

4. **First Deposit:**
   ```
   After first deposit:
   totalShares >= DEAD_SHARES
   shareBalances[address(0)] == DEAD_SHARES
   ```

---

## Lines of Code: 315

**Breakdown:**

- Imports & setup: 25 lines
- Struct & state: 40 lines
- Constructor: 10 lines
- Vault creation: 15 lines
- Deposit function: 40 lines
- Withdraw function: 32 lines
- Yield distribution: 15 lines
- View functions: 70 lines
- Admin functions: 20 lines
- Comments/docs: 48 lines
