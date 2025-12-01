# TierManager.sol - Implementation Documentation

## Overview

Manages lock tier configurations and handles all interest/penalty calculations. Provides the economic model for time-locked deposits with varying APYs and early withdrawal penalties.

---

## Default Tier Configuration

| Tier | Lock Period | APY | Penalty | Use Case                        |
| ---- | ----------- | --- | ------- | ------------------------------- |
| 0    | No lock     | 0%  | 0%      | Flexible savings, no commitment |
| 1    | 30 days     | 2%  | 50%     | Short-term lock, modest returns |
| 2    | 90 days     | 5%  | 50%     | Medium-term lock, good returns  |
| 3    | 180 days    | 8%  | 50%     | Long-term lock, best returns    |

**Risk-Reward Tradeoff:**

- Longer locks → Higher APY
- Early withdrawal → Lose 50% of earned interest
- Tier 0 has no risk/reward (instant liquidity)

---

## Core Calculations

### 1. **Interest Calculation** (Lines 116-131)

**Formula:**

```solidity
interest = (principal * apy * duration) / (SECONDS_PER_YEAR * BASIS_POINTS)
```

**Example:**

```
principal = 1000 tokens
apy = 500 (5%)
duration = 90 days

interest = (1000 * 500 * 7,776,000) / (31,536,000 * 10,000)
         = 12.33 tokens
```

**Interest Model:**

- **Simple interest** (not compounding)
- Pro-rata calculation based on time elapsed
- Calculated per-second for accuracy

**Design Decision:**
Simple interest keeps calculations straightforward and gas-efficient. For compounding, would need periodic yield distribution.

---

### 2. **Penalty Calculation** (Lines 133-157)

**Current Model - Flat Rate:**

```solidity
penalty = (accruedInterest * earlyWithdrawalPenalty) / BASIS_POINTS
```

**Example:**

```
accruedInterest = 10 tokens
earlyWithdrawalPenalty = 5000 (50%)

penalty = (10 * 5000) / 10,000 = 5 tokens
```

**Alternative Models (commented in code):**

1. **Proportional Model:**

   ```solidity
   // Penalty increases with more time remaining
   penalty = accruedInterest * (timeRemaining / lockPeriod) * penaltyRate
   ```

2. **Progressive Model:**
   ```solidity
   // Penalty decreases as lock progresses
   penalty = accruedInterest * (timeElapsed / lockPeriod) * penaltyRate
   ```

**Current Choice: Flat Rate**

- Simple and predictable
- Easy for users to understand
- Gas efficient
- Can be changed by admin if needed

---

### 3. **Lock Period Enforcement** (Lines 159-173)

**Function:**

```solidity
function canWithdrawWithoutPenalty(
    uint256 depositTimestamp,
    uint8 tier
) external view returns (bool)
```

**Logic:**

```solidity
// Tier 0 (no lock) always returns true
if (config.lockPeriod == 0) return true;

// Check if enough time has elapsed
return block.timestamp >= depositTimestamp + config.lockPeriod;
```

**Used by Bank to:**

- Preview penalty before withdrawal
- Display lock status to users
- Determine if penalty should be applied

---

## Configuration Management

### 1. **Configure Tier** (Lines 77-97)

```solidity
function configureTier(
    uint8 tier,
    uint256 lockPeriod,
    uint256 apy,
    uint256 penalty
) external onlyOwner
```

**Validations:**

```solidity
if (tier >= MAX_TIERS) revert Errors.InvalidTier();
if (apy > BASIS_POINTS) revert Errors.InvalidAmount(); // Max 100%
if (penalty > BASIS_POINTS) revert Errors.InvalidAmount(); // Max 100%
```

**Use Cases:**

- Adjust APYs based on market conditions
- Change lock periods for promotions
- Modify penalty structure
- Add seasonal tiers

**Safety:**

- Owner-only function
- Validation prevents invalid configs
- Preserves enabled state
- Emits event for transparency

---

### 2. **Enable/Disable Tiers** (Lines 99-109)

```solidity
function setTierEnabled(uint8 tier, bool enabled) external onlyOwner
```

**Purpose:**

- Temporarily disable tiers without losing config
- Phase out unpopular tiers
- Launch new tiers gradually
- Emergency pause specific tiers

**Example Scenario:**

```
1. Tier 1 not popular → disable it
2. Config stays intact
3. Users with existing Tier 1 positions unaffected
4. New deposits cannot use Tier 1
5. Can re-enable later
```

---

## View Functions

### 1. **Get Tier Config** (Lines 196-209)

```solidity
function getTierConfig(uint8 tier)
    external view returns (TierConfig memory)
```

Returns complete tier configuration:

```solidity
struct TierConfig {
    uint256 lockPeriod;        // Lock duration in seconds
    uint256 apy;               // Annual percentage yield (basis points)
    uint256 earlyWithdrawalPenalty; // Penalty percentage (basis points)
    bool enabled;              // Whether tier is active
}
```

---

### 2. **Get All Tiers** (Lines 224-231)

```solidity
function getAllTiers() external view returns (TierConfig[] memory)
```

**Purpose:**

- Frontend displays all options
- User compares tiers easily
- Admin dashboard shows full config

**Gas Efficient:**

- Returns array of 4 structs (small)
- Single call for all data
- No iteration on-chain needed

---

### 3. **Preview Interest** (Lines 244-257)

```solidity
function previewInterest(
    uint256 principal,
    uint8 tier
) external view returns (uint256 interest)
```

**Use Case:**
Before deposit, user can see:

```
"If you deposit 1000 tokens in Tier 2 (90 days):
 You will earn 12.33 tokens"
```

**Calculation:**

```solidity
interest = (principal * config.apy * config.lockPeriod)
         / (SECONDS_PER_YEAR * BASIS_POINTS)
```

Shows interest for **full lock period** (not partial).

---

## Constants

```solidity
uint256 public constant BASIS_POINTS = 10_000;        // 100%
uint256 public constant SECONDS_PER_YEAR = 365 days;  // 31,536,000 seconds
uint8 private constant MAX_TIERS = 4;                 // Maximum number of tiers
```

**Design Choices:**

- **BASIS_POINTS = 10,000**: Allows precision to 0.01% (e.g., 4.75% = 475)
- **SECONDS_PER_YEAR = 365 days**: Standard year (not accounting for leap years)
- **MAX_TIERS = 4**: Keeps UI simple, can be increased if needed

---

## Integration with Bank.sol

### Typical Flow

**Deposit:**

```
1. User selects tier
2. Bank calls TierManager.isTierValid(tier)
3. Bank calls TierManager.getLockEndTimestamp()
4. Bank stores position with lockEndTimestamp
```

**During Lock Period:**

```
1. User checks position value
2. Bank calls TierManager.calculateInterest()
3. Shows user accrued interest
4. Bank calls TierManager.calculatePenalty()
5. Shows potential penalty if early withdrawal
```

**Withdrawal:**

```
1. User requests withdrawal
2. Bank checks TierManager.canWithdrawWithoutPenalty()
3. If still locked:
   - Calculate penalty
   - Apply penalty
   - Redistribute to vault
4. If lock ended:
   - No penalty
   - Full amount + interest
```

---

## Economic Model

### APY Justification

| Tier | Lock | APY | Rationale                                  |
| ---- | ---- | --- | ------------------------------------------ |
| 0    | None | 0%  | Opportunity cost: capital locked = 0       |
| 1    | 30d  | 2%  | Short commitment, minimal opportunity cost |
| 2    | 90d  | 5%  | Medium commitment, competitive with DeFi   |
| 3    | 180d | 8%  | Long commitment, above-market returns      |

**Comparison:**

- Traditional bank savings: 0.5-1%
- Stablecoins: 3-5%
- DeFi yield: 5-15% (varies)
- Our Tier 3: 8% (competitive, sustainable)

---

### Penalty Model

**50% Flat Penalty Design:**

**Pros:**

- ✅ Simple and predictable
- ✅ Strong disincentive for early withdrawal
- ✅ Fair to remaining depositors (penalty redistributed)
- ✅ Standard in traditional finance (CDs)

**Cons:**

- ⚠️ Harsh for users with emergencies
- ⚠️ May discourage longer locks
- ⚠️ No grace period near end of lock

**Alternative Considerations:**

```solidity
// Progressive penalty (decreases over time)
uint256 timeElapsed = block.timestamp - depositTimestamp;
uint256 progressPct = (timeElapsed * BASIS_POINTS) / lockPeriod;
uint256 adjustedPenalty = basePenalty * (BASIS_POINTS - progressPct) / BASIS_POINTS;

// Example:
// - Day 1: 50% penalty
// - Day 45 (halfway): 25% penalty
// - Day 89: 1% penalty
// - Day 90+: 0% penalty
```

Can be implemented in future version if needed.

---

## Security Considerations

### ✅ **Implemented Protections**

1. **Configuration Validation**

   - APY capped at 100%
   - Penalty capped at 100%
   - Tier number checked
   - Owner-only modifications

2. **Overflow Protection**

   - Solidity 0.8+ automatic checks
   - All math operations safe
   - No unchecked blocks

3. **Access Control**

   - Only owner can modify configs
   - View functions are public (safe)
   - No user-facing state changes

4. **Consistency Checks**
   - Invalid tiers return 0 or false
   - Disabled tiers treated as invalid
   - Graceful handling of edge cases

---

### ⚠️ **Testing Priorities**

1. **Interest Calculations**

   - Verify math at various durations
   - Test with different APYs
   - Edge cases: 0 duration, max duration
   - Different principal amounts

2. **Penalty Calculations**

   - Test at various time points in lock
   - Verify penalty never exceeds interest
   - Test with 0 penalty (Tier 0)
   - Test with 100% penalty (hypothetical)

3. **Lock Period Logic**

   - Exact timestamp boundaries
   - Block.timestamp manipulation scenarios
   - Very short lock periods (1 second)
   - Very long lock periods (years)

4. **Configuration Changes**

   - Change config mid-lock (doesn't affect existing positions)
   - Disable tier with active positions
   - Extreme values (0 APY, 10000 APY)

5. **Rounding Errors**
   - Very small principals (1 wei)
   - Very short durations (1 second)
   - Maximum values (uint256 max)

---

## Mathematical Properties

### Invariants

1. **Interest is Pro-Rata:**

   ```
   interest(2x duration) = 2 * interest(x duration)
   ```

2. **APY Constraint:**

   ```
   0 <= apy <= 10000 (0% to 100%)
   ```

3. **Penalty Constraint:**

   ```
   0 <= penalty <= accruedInterest
   ```

4. **Time Progression:**
   ```
   If t2 > t1, then interest(t2) >= interest(t1)
   ```

---

## Gas Optimization

**Efficient Design:**

- Pure constants (inlined by compiler)
- View functions (no state changes)
- Minimal storage reads
- Simple arithmetic (no loops)

**Gas Costs (approximate):**

- `calculateInterest()`: ~2k gas
- `calculatePenalty()`: ~2k gas
- `getTierConfig()`: ~1k gas
- `configureTier()`: ~45k gas (state change)

---

## Future Enhancements

### Potential Features

1. **Progressive Penalties:**

   ```solidity
   // Penalty decreases as lock period progresses
   ```

2. **Bonus Tiers:**

   ```solidity
   // Extra APY for deposits over certain amount
   // Tier 4: 180 days, 1M tokens, 10% APY
   ```

3. **Dynamic APY:**

   ```solidity
   // APY adjusts based on total deposits
   // Encourage/discourage deposits based on liquidity
   ```

4. **Grace Period:**

   ```solidity
   // No penalty in last X days of lock
   // Tier 1: 30 days lock, 3 day grace period
   ```

5. **Compounding:**
   ```solidity
   // Auto-reinvest interest
   // Requires periodic yield distribution
   ```

---

## Lines of Code: 265

**Breakdown:**

- Imports & setup: 20 lines
- Constants: 10 lines
- State variables: 5 lines
- Constructor (default config): 50 lines
- Configuration functions: 35 lines
- Calculation functions: 70 lines
- View functions: 50 lines
- Comments/docs: 25 lines
