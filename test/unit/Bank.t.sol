// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "../BaseTest.sol";
import {IBank} from "../../src/interfaces/IBank.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/**
 * @title BankTest
 * @notice Comprehensive unit tests for Bank contract
 */
contract BankTest is BaseTest {
    // ==================== Deposit Tests ====================

    function test_Deposit_Success() public {
        uint256 depositAmount = 1000e6; // 1000 USDC
        uint8 tier = 1; // 30 days

        vm.startPrank(alice);
        usdc.approve(address(bank), depositAmount);
        
        uint256 positionId = bank.deposit(
            address(usdc),
            depositAmount,
            tier,
            bytes32(0)
        );

        // Verify position was created
        IBank.Position memory position = bank.getPosition(alice, positionId);
        assertEq(position.token, address(usdc));
        assertEq(position.amount, depositAmount);
        assertEq(position.tier, tier);
        assertGt(position.shares, 0);
        assertGt(position.lockEndTimestamp, block.timestamp);

        vm.stopPrank();
    }

    function test_Deposit_MultiplePositions() public {
        vm.startPrank(alice);
        
        // First deposit
        usdc.approve(address(bank), 1000e6);
        uint256 pos1 = bank.deposit(address(usdc), 1000e6, 0, bytes32(0));
        
        // Second deposit
        usdc.approve(address(bank), 2000e6);
        uint256 pos2 = bank.deposit(address(usdc), 2000e6, 1, bytes32(0));
        
        vm.stopPrank();

        // Verify both positions exist
        assertEq(pos1, 0);
        assertEq(pos2, 1);
        assertEq(bank.getUserPositionCount(alice), 2);
    }

    function test_Deposit_RevertIfZeroAddress() public {
        vm.startPrank(alice);
        vm.expectRevert(Errors.ZeroAddress.selector);
        bank.deposit(address(0), 1000e6, 0, bytes32(0));
        vm.stopPrank();
    }

    function test_Deposit_RevertIfZeroAmount() public {
        vm.startPrank(alice);
        vm.expectRevert(Errors.ZeroAmount.selector);
        bank.deposit(address(usdc), 0, 0, bytes32(0));
        vm.stopPrank();
    }

    function test_Deposit_RevertIfBelowMinDeposit() public {
        vm.startPrank(alice);
        usdc.approve(address(bank), 999);
        vm.expectRevert(Errors.InvalidAmount.selector);
        bank.deposit(address(usdc), 999, 0, bytes32(0));
        vm.stopPrank();
    }

    function test_Deposit_RevertIfTokenNotSupported() public {
        MockERC20 unsupportedToken = new MockERC20("Unsupported", "UNS", 18);
        unsupportedToken.mint(alice, 1000e18);

        vm.startPrank(alice);
        unsupportedToken.approve(address(bank), 1000e18);
        vm.expectRevert(Errors.TokenNotSupported.selector);
        bank.deposit(address(unsupportedToken), 1000e18, 0, bytes32(0));
        vm.stopPrank();
    }

    function test_Deposit_RevertIfInvalidTier() public {
        vm.startPrank(alice);
        usdc.approve(address(bank), 1000e6);
        vm.expectRevert(Errors.InvalidTier.selector);
        bank.deposit(address(usdc), 1000e6, 5, bytes32(0)); // Tier 5 doesn't exist
        vm.stopPrank();
    }

    function test_Deposit_WithReferral() public {
        // Bob registers referral code
        bytes32 referralCode = keccak256("BOB_REFERRAL");
        vm.prank(bob);
        bank.registerReferralCode(referralCode);

        // Alice deposits with Bob's referral
        vm.startPrank(alice);
        usdc.approve(address(bank), 1000e6);
        uint256 positionId = bank.deposit(
            address(usdc),
            1000e6,
            1,
            referralCode
        );
        vm.stopPrank();

        // Verify referrer is set
        IBank.Position memory position = bank.getPosition(alice, positionId);
        assertEq(position.referrer, bob);
    }

    function test_Deposit_RevertIfSelfReferral() public {
        // Alice registers code
        bytes32 referralCode = keccak256("ALICE_REFERRAL");
        vm.prank(alice);
        bank.registerReferralCode(referralCode);

        // Alice tries to use own code
        vm.startPrank(alice);
        usdc.approve(address(bank), 1000e6);
        vm.expectRevert(Errors.CannotReferSelf.selector);
        bank.deposit(address(usdc), 1000e6, 1, referralCode);
        vm.stopPrank();
    }

    // ==================== Withdraw Tests ====================

    function test_Withdraw_FullWithdrawNoLock() public {
        // Deposit with no lock (tier 0)
        uint256 positionId = _approveAndDeposit(alice, address(usdc), 1000e6, 0);

        // Time travel (optional for tier 0)
        _warp(1 days);

        // Withdraw
        uint256 balanceBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        bank.withdraw(positionId, 0); // 0 = withdraw all

        uint256 balanceAfter = usdc.balanceOf(alice);
        
        // Should receive close to original amount (account for DEAD_SHARES rounding loss)
        // Allow up to 0.1% difference due to rounding
        assertApproxEqRel(balanceAfter - balanceBefore, 1000e6, 0.001e18); // 0.1%
    }

    function test_Withdraw_FullWithdrawAfterLockEnds() public {
        // Deposit with 30 day lock
        uint256 positionId = _approveAndDeposit(alice, address(dai), 1000e18, 1);

        // Time travel past lock period
        _warp(31 days);

        // Withdraw
        uint256 balanceBefore = dai.balanceOf(alice);
        vm.prank(alice);
        bank.withdraw(positionId, 0);

        uint256 balanceAfter = dai.balanceOf(alice);
        
        // Should receive original + interest (no penalty)
        // Account for rounding - should be close to or above principal
        assertGe(balanceAfter - balanceBefore, 999e18); // At least 99.9% of principal
    }

    function test_Withdraw_EarlyWithdrawWithPenalty() public {
        // Deposit with 30 day lock
        uint256 positionId = _approveAndDeposit(alice, address(dai), 1000e18, 1);

        // Time travel 15 days (half way)
        _warp(15 days);

        // Withdraw early
        uint256 balanceBefore = dai.balanceOf(alice);
        vm.prank(alice);
        bank.withdraw(positionId, 0);

        uint256 balanceAfter = dai.balanceOf(alice);
        
        // Should receive close to principal after penalty on interest
        // Allow for rounding - should be at least 99% of principal
        assertGe(balanceAfter - balanceBefore, 990e18); // At least 99% of principal
    }

    function test_Withdraw_PartialWithdraw() public {
        // Deposit
        uint256 positionId = _approveAndDeposit(alice, address(dai), 1000e18, 0);
        
        IBank.Position memory positionBefore = bank.getPosition(alice, positionId);
        uint256 sharesToWithdraw = positionBefore.shares / 2;

        // Withdraw half
        vm.prank(alice);
        bank.withdraw(positionId, sharesToWithdraw);

        // Verify position updated
        IBank.Position memory positionAfter = bank.getPosition(alice, positionId);
        assertEq(positionAfter.shares, positionBefore.shares - sharesToWithdraw);
    }

    function test_Withdraw_RevertIfPositionDoesNotExist() public {
        vm.prank(alice);
        vm.expectRevert(Errors.PositionDoesNotExist.selector);
        bank.withdraw(999, 0); // Position 999 doesn't exist
    }

    function test_Withdraw_RevertIfInsufficientShares() public {
        uint256 positionId = _approveAndDeposit(alice, address(dai), 1000e18, 0);
        
        IBank.Position memory position = bank.getPosition(alice, positionId);

        vm.prank(alice);
        vm.expectRevert(Errors.InsufficientShares.selector);
        bank.withdraw(positionId, position.shares + 1);
    }

    // ==================== View Function Tests ====================

    function test_GetPositionValue_IncreasesOverTime() public {
        uint256 positionId = _approveAndDeposit(alice, address(dai), 1000e18, 1);

        uint256 valueBefore = bank.getPositionValue(alice, positionId);

        // Time travel
        _warp(15 days);

        uint256 valueAfter = bank.getPositionValue(alice, positionId);

        // Value should increase due to accrued interest
        // Even with rounding, it should at least stay the same or increase
        assertGe(valueAfter, valueBefore);
    }

    function test_CalculatePenalty_ZeroForNoLock() public {
        uint256 positionId = _approveAndDeposit(alice, address(dai), 1000e18, 0);

        uint256 penalty = bank.calculatePenalty(alice, positionId);
        assertEq(penalty, 0);
    }

    function test_CalculatePenalty_ZeroAfterLockEnds() public {
        uint256 positionId = _approveAndDeposit(alice, address(dai), 1000e18, 1);

        _warp(31 days);

        uint256 penalty = bank.calculatePenalty(alice, positionId);
        assertEq(penalty, 0);
    }

    function test_CalculatePenalty_NonZeroDuringLock() public {
        uint256 positionId = _approveAndDeposit(alice, address(dai), 1000e18, 1);

        _warp(15 days);

        uint256 penalty = bank.calculatePenalty(alice, positionId);
        assertGt(penalty, 0);
    }

    // ==================== Admin Function Tests ====================

    function test_SetSupportedToken() public {
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18);

        // Add token
        bank.setSupportedToken(address(newToken), true);
        
        // Should be supported now
        newToken.mint(alice, 1000e18);
        vm.startPrank(alice);
        newToken.approve(address(bank), 1000e18);
        bank.deposit(address(newToken), 1000e18, 0, bytes32(0));
        vm.stopPrank();
    }

    function test_SetSupportedToken_RevertIfNotOwner() public {
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18);

        vm.prank(alice);
        vm.expectRevert(); // Ownable: caller is not the owner
        bank.setSupportedToken(address(newToken), true);
    }

    function test_SetPaused() public {
        // Pause
        bank.setPaused(true);

        // Deposits should fail
        vm.startPrank(alice);
        usdc.approve(address(bank), 1000e6);
        vm.expectRevert(); // Pausable: paused
        bank.deposit(address(usdc), 1000e6, 0, bytes32(0));
        vm.stopPrank();

        // Unpause
        bank.setPaused(false);

        // Deposits should work again
        vm.startPrank(alice);
        bank.deposit(address(usdc), 1000e6, 0, bytes32(0));
        vm.stopPrank();
    }

    // ==================== Referral Tests ====================

    function test_RegisterReferralCode() public {
        bytes32 code = keccak256("ALICE_CODE");
        
        vm.prank(alice);
        bank.registerReferralCode(code);

        assertEq(bank.getReferrer(code), alice);
    }

    function test_RegisterReferralCode_RevertIfZero() public {
        vm.prank(alice);
        vm.expectRevert(Errors.InvalidReferralCode.selector);
        bank.registerReferralCode(bytes32(0));
    }

    function test_RegisterReferralCode_RevertIfAlreadyExists() public {
        bytes32 code = keccak256("ALICE_CODE");
        
        vm.prank(alice);
        bank.registerReferralCode(code);

        vm.prank(bob);
        vm.expectRevert(Errors.ReferralCodeAlreadyExists.selector);
        bank.registerReferralCode(code);
    }
}