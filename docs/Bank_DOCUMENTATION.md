# Bank.sol - Complete Implementation Summary

## Overview

Main user-facing contract for VaultForge. Handles deposits, withdrawals, position management, and referral system.

---

## Key Features Implemented

### 1. **Deposit Flow** (Lines 77-147)

```
User deposits → Validate → Create vault if needed → Transfer tokens → Mint shares → Store position
```

**Security patterns:**

- ✅ CEI pattern (Checks-Effects-Interactions)
- ✅ ReentrancyGuard
- ✅ Pausable
- ✅ SafeERC20 for transfers
- ✅ MIN_DEPOSIT constant (prevents dust attacks)
- ✅ Referral validation

**Gas optimization:**

- Position ID increments per user (not global)
- Single SSTORE for position struct

---

### 2. **Withdraw Flow** (Lines 149-231)

```
User withdraws → Validate → Calculate penalty if early → Burn shares → Transfer tokens → Distribute penalty as yield
```

**Security patterns:**

- ✅ CEI pattern
- ✅ Lock period enforcement
- ✅ Penalty calculation capped at accrued interest
- ✅ Penalty redistributed to remaining depositors (not lost)

**Key logic:**

- If `shares == 0`, withdraws entire position
- Proportional amount tracking for partial withdrawals
- Penalties stay in vault as yield for others

---

### 3. **View Functions** (Lines 233-294)

- `getPosition()` - Returns full position details
- `getUserPositionCount()` - Number of positions user has
- `getPositionValue()` - Current value including yield
- `calculatePenalty()` - Preview penalty before withdrawal

**Note:** All view functions are gas-efficient (no external calls in loops)

---

### 4. **Admin Functions** (Lines 296-340)

- `setSupportedToken()` - Add/remove tokens
- `setPaused()` - Emergency pause
- `emergencyWithdraw()` - Last resort recovery

**Security:**

- ✅ OnlyOwner modifier
- ✅ Validation to prevent duplicate state changes
- ✅ Events for all state changes

---

### 5. **Referral System** (Lines 342-365)

- `registerReferralCode()` - Users create unique codes
- `getReferrer()` - Lookup referrer by code
- Stored in `referralCodes` mapping

**Features:**

- Unique codes (can't override)
- Self-referral blocked
- No minimum holding period (can be added later)

---

## Security Considerations

### ✅ **Implemented Protections**

1. **Reentrancy Protection**

   - `nonReentrant` on deposit/withdraw
   - CEI pattern throughout

2. **Access Control**

   - `onlyOwner` for admin functions
   - Proper validation on user functions

3. **Token Safety**

   - `SafeERC20` for all transfers
   - Return value checks handled automatically

4. **Input Validation**

   - Zero address checks
   - Zero amount checks
   - Tier validation
   - Token support checks

5. **Economic Attacks**

   - MIN_DEPOSIT prevents dust/griefing
   - Penalty capped at accrued interest
   - First depositor attack mitigated by MIN_DEPOSIT

6. **Emergency Controls**
   - Pausable pattern
   - Emergency withdraw function

---

### ⚠️ **Considerations for Testing**

1. **Flash loan attacks**

   - Current design: deposit/withdraw in same block allowed
   - Consider: Add cooldown period if needed

2. **Price manipulation**

   - Shares use VaultManager exchange rate
   - Need to test vault inflation scenarios

3. **Rounding errors**

   - Test with tokens of different decimals (6, 8, 18)
   - Proportional withdrawal math needs thorough testing

4. **Lock period edge cases**
   - Withdraw exactly at `lockEndTimestamp`
   - Very small time remaining

---

## Dependencies

### External (OpenZeppelin)

- `IERC20` - Token interface
- `SafeERC20` - Safe transfer wrapper
- `ReentrancyGuard` - Reentrancy protection
- `Ownable` - Access control
- `Pausable` - Emergency pause

### Internal

- `IBank` - Interface
- `IVaultManager` - Vault share accounting
- `ITierManager` - Lock period & APY logic
- `Errors` - Custom errors

---

## State Variables

```solidity
IVaultManager public immutable VAULT_MANAGER;
ITierManager public immutable TIER_MANAGER;
mapping(address => bool) public supportedTokens;
mapping(address => mapping(uint256 => Position)) private userPositions;
mapping(address => uint256) private userPositionCount;
mapping(bytes32 => address) public referralCodes;
uint256 public constant MIN_DEPOSIT = 1000;
```

**Gas efficiency:**

- Immutable for contracts (saves SLOAD)
- Position counter per user (cheaper than global)
- Constant for MIN_DEPOSIT (inline)

---

## Testing Priorities (for later)

### Unit Tests

1. Deposit with all tier types
2. Withdraw with/without penalty
3. Partial withdrawals
4. Referral code registration
5. Admin functions

### Integration Tests

1. Full user flow: deposit → wait → withdraw
2. Multi-user scenarios
3. Penalty redistribution

### Fuzz Tests

1. Random deposit/withdraw amounts
2. Random time travel (lock periods)
3. Edge case shares/amounts

### Attack Vectors

1. Reentrancy attempts
2. Flash loan simulations
3. First depositor inflation
4. Dust deposits

---

## Known Limitations

1. **No position transfer** - Positions are non-transferable (by design)
2. **No position merging** - Each deposit creates new position
3. **Token removal** - Can disable but can't force-withdraw existing positions
4. **Penalty model** - Redistributed to vault, not burned or sent to protocol

---

## Lines of Code: 384

**Breakdown:**

- Imports & setup: 30 lines
- State variables: 25 lines
- Constructor: 15 lines
- Deposit function: 70 lines
- Withdraw function: 82 lines
- View functions: 61 lines
- Admin functions: 44 lines
- Referral system: 23 lines
- Comments/docs: 134 lines
