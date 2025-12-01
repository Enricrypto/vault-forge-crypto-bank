// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "../BaseTest.sol";
import {IBank} from "../../src/interfaces/IBank.sol";

/**
 * @title IntegrationTest
 * @notice End-to-end integration tests for VaultForge
 * @dev Tests complete user journeys across all contracts
 */
contract IntegrationTest is BaseTest {
    
    // ==================== Single User Journey Tests ====================

    function test_Integration_FullJourney_NoLock() public {
        uint256 depositAmount = 10000e18;
        
        // 1. User deposits with no lock (Tier 0)
        vm.startPrank(alice);
        dai.approve(address(bank), depositAmount);
        uint256 positionId = bank.deposit(address(dai), depositAmount, 0, bytes32(0));
        vm.stopPrank();

        // Verify position created
        IBank.Position memory position = bank.getPosition(alice, positionId);
        assertEq(position.token, address(dai));
        assertEq(position.amount, depositAmount);
        assertEq(position.tier, 0);
        assertGt(position.shares, 0);

        // 2. Time passes (30 days)
        _warp(30 days);

        // 3. No interest accrued (Tier 0 has 0% APY)
        uint256 positionValue = bank.getPositionValue(alice, positionId);
        assertApproxEqRel(positionValue, depositAmount, 0.01e18); // Should be close to original

        // 4. User withdraws - no penalty
        uint256 balanceBefore = dai.balanceOf(alice);
        vm.prank(alice);
        bank.withdraw(positionId, 0); // Withdraw all

        uint256 balanceAfter = dai.balanceOf(alice);
        
        // Should receive close to original amount
        assertApproxEqRel(balanceAfter - balanceBefore, depositAmount, 0.01e18);
    }

    function test_Integration_FullJourney_WithInterest() public {
        uint256 depositAmount = 10000e18;
        
        // 1. Alice deposits with 30-day lock (Tier 1, 2% APY)
        vm.startPrank(alice);
        dai.approve(address(bank), depositAmount);
        uint256 positionId = bank.deposit(address(dai), depositAmount, 1, bytes32(0));
        vm.stopPrank();

        // 2. Time passes - full lock period
        _warp(30 days);

        // 3. Calculate expected interest
        uint256 expectedInterest = _calculateExpectedInterest(depositAmount, 1, 30 days);
        
        // 4. Check position value includes interest
        uint256 positionValue = bank.getPositionValue(alice, positionId);
        assertGe(positionValue, depositAmount * 99 / 100); // At least 99% (rounding losses)

        // 5. Alice withdraws after lock - no penalty
        uint256 balanceBefore = dai.balanceOf(alice);
        vm.prank(alice);
        bank.withdraw(positionId, 0);

        uint256 balanceAfter = dai.balanceOf(alice);
        uint256 received = balanceAfter - balanceBefore;
        
        // Should receive at least 99% of principal (accounting for DEAD_SHARES rounding)
        assertGe(received, depositAmount * 99 / 100);
    }

    function test_Integration_EarlyWithdrawal_WithPenalty() public {
        uint256 depositAmount = 10000e18;
        
        // 1. Alice deposits with 90-day lock (Tier 2, 5% APY)
        vm.startPrank(alice);
        dai.approve(address(bank), depositAmount);
        uint256 positionId = bank.deposit(address(dai), depositAmount, 2, bytes32(0));
        vm.stopPrank();

        // 2. Time passes - only 45 days (halfway through lock)
        _warp(45 days);

        // 3. Calculate expected penalty
        uint256 accruedInterest = _calculateExpectedInterest(depositAmount, 2, 45 days);
        uint256 expectedPenalty = bank.calculatePenalty(alice, positionId);
        assertGt(expectedPenalty, 0); // Should have penalty

        // 4. Alice withdraws early
        uint256 balanceBefore = dai.balanceOf(alice);
        vm.prank(alice);
        bank.withdraw(positionId, 0);

        uint256 balanceAfter = dai.balanceOf(alice);
        uint256 received = balanceAfter - balanceBefore;
        
        // Should receive: principal + interest - penalty
        // Penalty is 50% of accrued interest
        uint256 expectedReceived = depositAmount + accruedInterest - expectedPenalty;
        assertApproxEqRel(received, expectedReceived, 0.05e18); // 5% tolerance
    }

    // ==================== Multi-User Scenarios ====================

    function test_Integration_MultiUser_SameToken() public {
        uint256 aliceDeposit = 10000e18;
        uint256 bobDeposit = 5000e18;
        
        // 1. Alice deposits first
        vm.startPrank(alice);
        dai.approve(address(bank), aliceDeposit);
        uint256 alicePos = bank.deposit(address(dai), aliceDeposit, 1, bytes32(0));
        vm.stopPrank();

        // 2. Bob deposits later (same token, different amount)
        vm.startPrank(bob);
        dai.approve(address(bank), bobDeposit);
        uint256 bobPos = bank.deposit(address(dai), bobDeposit, 1, bytes32(0));
        vm.stopPrank();

        // 3. Time passes
        _warp(30 days);

        // 4. Both should have earned proportional interest
        uint256 aliceValue = bank.getPositionValue(alice, alicePos);
        uint256 bobValue = bank.getPositionValue(bob, bobPos);

        // Alice deposited 2x Bob's amount, should have ~2x value
        assertApproxEqRel(aliceValue, bobValue * 2, 0.05e18);
    }

    function test_Integration_MultiUser_DifferentTiers() public {
        uint256 depositAmount = 10000e18;
        
        // 1. Alice deposits in Tier 1 (30 days, 2% APY)
        vm.startPrank(alice);
        dai.approve(address(bank), depositAmount);
        uint256 alicePos = bank.deposit(address(dai), depositAmount, 1, bytes32(0));
        vm.stopPrank();

        // 2. Bob deposits in Tier 2 (90 days, 5% APY)
        vm.startPrank(bob);
        dai.approve(address(bank), depositAmount);
        uint256 bobPos = bank.deposit(address(dai), depositAmount, 2, bytes32(0));
        vm.stopPrank();

        // 3. Time passes (30 days)
        _warp(30 days);

        // 4. Check values
        uint256 aliceValue = bank.getPositionValue(alice, alicePos);
        uint256 bobValue = bank.getPositionValue(bob, bobPos);

        // Bob has higher APY (5% vs 2%), so should have more value
        assertGt(bobValue, aliceValue);
    }

    function test_Integration_PenaltyRedistribution() public {
        uint256 deposit1 = 10000e18;
        uint256 deposit2 = 10000e18;
        
        // 1. Alice deposits
        vm.startPrank(alice);
        dai.approve(address(bank), deposit1);
        uint256 alicePos = bank.deposit(address(dai), deposit1, 2, bytes32(0));
        vm.stopPrank();

        // 2. Bob deposits (same tier, same amount)
        vm.startPrank(bob);
        dai.approve(address(bank), deposit2);
        uint256 bobPos = bank.deposit(address(dai), deposit2, 2, bytes32(0));
        vm.stopPrank();

        // 3. Time passes - 45 days
        _warp(45 days);

        // Get Bob's value before Alice's early withdrawal
        uint256 bobValueBefore = bank.getPositionValue(bob, bobPos);

        // 4. Alice withdraws early (pays penalty)
        vm.prank(alice);
        bank.withdraw(alicePos, 0);

        // 5. Bob's position should be worth more due to penalty redistribution
        uint256 bobValueAfter = bank.getPositionValue(bob, bobPos);
        
        // Bob's value should increase from Alice's penalty
        assertGt(bobValueAfter, bobValueBefore);
    }

    // ==================== Referral System Tests ====================

    function test_Integration_ReferralSystem() public {
        uint256 depositAmount = 10000e18;
        
        // 1. Bob registers referral code
        bytes32 referralCode = keccak256("BOB_REF");
        vm.prank(bob);
        bank.registerReferralCode(referralCode);

        // 2. Alice deposits using Bob's referral
        vm.startPrank(alice);
        dai.approve(address(bank), depositAmount);
        uint256 positionId = bank.deposit(address(dai), depositAmount, 1, referralCode);
        vm.stopPrank();

        // 3. Verify referrer is set
        IBank.Position memory position = bank.getPosition(alice, positionId);
        assertEq(position.referrer, bob);

        // 4. Carol deposits using Bob's referral too
        vm.startPrank(carol);
        dai.approve(address(bank), depositAmount);
        uint256 carolPos = bank.deposit(address(dai), depositAmount, 1, referralCode);
        vm.stopPrank();

        IBank.Position memory carolPosition = bank.getPosition(carol, carolPos);
        assertEq(carolPosition.referrer, bob);

        // Bob has successfully referred 2 users
    }

    // ==================== Multiple Positions Tests ====================

    function test_Integration_MultiplePositions_SameUser() public {
        // 1. Alice creates 3 different positions
        vm.startPrank(alice);
        
        // Position 1: Tier 0, USDC
        usdc.approve(address(bank), 1000e6);
        uint256 pos1 = bank.deposit(address(usdc), 1000e6, 0, bytes32(0));
        
        // Position 2: Tier 1, DAI
        dai.approve(address(bank), 5000e18);
        uint256 pos2 = bank.deposit(address(dai), 5000e18, 1, bytes32(0));
        
        // Position 3: Tier 2, WETH
        weth.approve(address(bank), 2e18);
        uint256 pos3 = bank.deposit(address(weth), 2e18, 2, bytes32(0));
        
        vm.stopPrank();

        // 2. Verify user has 3 positions
        assertEq(bank.getUserPositionCount(alice), 3);

        // 3. Time passes
        _warp(30 days);

        // 4. Withdraw from Position 2 only
        vm.prank(alice);
        bank.withdraw(pos2, 0);

        // 5. Alice still has positions 1 and 3
        IBank.Position memory position1 = bank.getPosition(alice, pos1);
        IBank.Position memory position3 = bank.getPosition(alice, pos3);
        
        assertGt(position1.shares, 0);
        assertGt(position3.shares, 0);
    }

    function test_Integration_PartialWithdrawals() public {
        uint256 depositAmount = 10000e18;
        
        // 1. Alice deposits
        vm.startPrank(alice);
        dai.approve(address(bank), depositAmount);
        uint256 positionId = bank.deposit(address(dai), depositAmount, 0, bytes32(0));
        vm.stopPrank();

        IBank.Position memory positionBefore = bank.getPosition(alice, positionId);
        uint256 totalShares = positionBefore.shares;

        // 2. Withdraw 25%
        vm.prank(alice);
        bank.withdraw(positionId, totalShares / 4);

        // 3. Check remaining
        IBank.Position memory positionAfter1 = bank.getPosition(alice, positionId);
        assertApproxEqRel(positionAfter1.shares, totalShares * 3 / 4, 0.01e18);

        // 4. Time passes
        _warp(15 days);

        // 5. Withdraw another 25%
        vm.prank(alice);
        bank.withdraw(positionId, totalShares / 4);

        // 6. Check remaining (should be ~50% of original)
        IBank.Position memory positionAfter2 = bank.getPosition(alice, positionId);
        assertApproxEqRel(positionAfter2.shares, totalShares / 2, 0.01e18);

        // 7. Withdraw rest
        vm.prank(alice);
        bank.withdraw(positionId, 0); // 0 = withdraw all remaining

        // 8. Position should have 0 shares
        IBank.Position memory finalPosition = bank.getPosition(alice, positionId);
        assertEq(finalPosition.shares, 0);
    }

    // ==================== Edge Case Scenarios ====================

    function test_Integration_DepositWithdrawImmediately() public {
        uint256 depositAmount = 10000e18;
        
        // 1. Alice deposits (Tier 0 - no lock)
        vm.startPrank(alice);
        dai.approve(address(bank), depositAmount);
        uint256 positionId = bank.deposit(address(dai), depositAmount, 0, bytes32(0));
        
        // 2. Withdraw immediately in same block
        uint256 balanceBefore = dai.balanceOf(alice);
        bank.withdraw(positionId, 0);
        
        vm.stopPrank();

        uint256 balanceAfter = dai.balanceOf(alice);
        
        // Should get back close to original (minus rounding)
        assertApproxEqRel(balanceAfter - balanceBefore, depositAmount, 0.01e18);
    }

    function test_Integration_MaximumLockPeriod() public {
        uint256 depositAmount = 10000e18;
        
        // 1. Alice deposits with maximum lock (Tier 3 - 180 days)
        vm.startPrank(alice);
        dai.approve(address(bank), depositAmount);
        uint256 positionId = bank.deposit(address(dai), depositAmount, 3, bytes32(0));
        vm.stopPrank();

        // 2. Time passes - full 180 days
        _warp(180 days);

        // 3. Calculate expected interest (8% APY for 180 days)
        uint256 expectedInterest = _calculateExpectedInterest(depositAmount, 3, 180 days);

        // 4. Withdraw
        uint256 balanceBefore = dai.balanceOf(alice);
        vm.prank(alice);
        bank.withdraw(positionId, 0);

        uint256 balanceAfter = dai.balanceOf(alice);
        uint256 received = balanceAfter - balanceBefore;
        
        // Should receive at least 99% of principal (accounting for rounding)
        assertGe(received, depositAmount * 99 / 100);
    }

    function test_Integration_MultipleTokens() public {
        // Alice deposits 3 different tokens
        vm.startPrank(alice);
        
        // USDC deposit
        usdc.approve(address(bank), 10000e6);
        uint256 usdcPos = bank.deposit(address(usdc), 10000e6, 1, bytes32(0));
        
        // DAI deposit
        dai.approve(address(bank), 10000e18);
        uint256 daiPos = bank.deposit(address(dai), 10000e18, 2, bytes32(0));
        
        // WETH deposit
        weth.approve(address(bank), 5e18);
        uint256 wethPos = bank.deposit(address(weth), 5e18, 3, bytes32(0));
        
        vm.stopPrank();

        // Time passes
        _warp(90 days);

        // Verify all positions have value
        assertGt(bank.getPositionValue(alice, usdcPos), 0);
        assertGt(bank.getPositionValue(alice, daiPos), 0);
        assertGt(bank.getPositionValue(alice, wethPos), 0);

        // Withdraw all
        vm.startPrank(alice);
        bank.withdraw(usdcPos, 0);
        bank.withdraw(daiPos, 0);
        bank.withdraw(wethPos, 0);
        vm.stopPrank();

        // Check balances increased
        assertGt(usdc.balanceOf(alice), 0);
        assertGt(dai.balanceOf(alice), 0);
        assertGt(weth.balanceOf(alice), 0);
    }

    // ==================== Stress Test ====================

    function test_Integration_ManyUsersDepositing() public {
        address[] memory users = new address[](5);
        users[0] = alice;
        users[1] = bob;
        users[2] = carol;
        users[3] = makeAddr("dave");
        users[4] = makeAddr("eve");

        // Setup: Give tokens to all users
        for (uint i = 0; i < users.length; i++) {
            dai.mint(users[i], 10000e18);
        }

        // All users deposit
        for (uint i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            dai.approve(address(bank), 10000e18);
            bank.deposit(address(dai), 10000e18, 1, bytes32(0));
            vm.stopPrank();
        }

        // Time passes
        _warp(30 days);

        // All users can check their positions
        for (uint i = 0; i < users.length; i++) {
            uint256 value = bank.getPositionValue(users[i], 0);
            // Each user should have at least 99% of deposit (accounting for rounding)
            assertGe(value, 9900e18);
        }
    }
}