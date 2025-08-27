// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {TestPlus} from "lib/solady/test/utils/TestPlus.sol";

import {
    RewardsTrackerLib,
    RewardPoolData,
    UserRewardData,
    RewardPoolDataMemory
} from "contracts/launchpad/libraries/RewardsTracker.sol";
import {MockRewardsTracker} from "test/mocks/MockRewardsTracker.sol";

contract RewardsTrackerTest is Test, TestPlus {
    MockRewardsTracker tracker;
    address baseAsset = makeAddr("baseAsset");
    address quoteAsset = makeAddr("quoteAsset");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");
    address user4 = makeAddr("user4");

    // Test constants
    uint128 constant PRECISION_FACTOR = 1e14;
    uint96 constant INITIAL_SHARES = 1000e18;
    uint128 constant INITIAL_BASE_REWARDS = 100e18;
    uint128 constant INITIAL_QUOTE_REWARDS = 50e18; // Match base token precision for now

    function setUp() public {
        tracker = new MockRewardsTracker();
        tracker.initializePair(baseAsset, quoteAsset);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                        INITIALIZATION TESTS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function testInitializePair() public view {
        assertEq(tracker.getQuoteAsset(), quoteAsset);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                        REWARD ADDITION TESTS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function testAddBaseRewards() public {
        vm.expectEmit(true, true, true, true);
        emit RewardsTrackerLib.BaseRewardsAdded(baseAsset, INITIAL_BASE_REWARDS);

        tracker.addBaseRewards(baseAsset, INITIAL_BASE_REWARDS);

        RewardPoolDataMemory memory poolData = tracker.getRewardsPoolData();
        assertEq(poolData.pendingBaseRewards, INITIAL_BASE_REWARDS);
    }

    function testAddQuoteRewards() public {
        vm.expectEmit(true, true, true, true);
        emit RewardsTrackerLib.QuoteRewardsAdded(baseAsset, quoteAsset, INITIAL_QUOTE_REWARDS);

        tracker.addQuoteRewards(baseAsset, quoteAsset, INITIAL_QUOTE_REWARDS);

        RewardPoolDataMemory memory poolData = tracker.getRewardsPoolData();
        assertEq(poolData.pendingQuoteRewards, INITIAL_QUOTE_REWARDS);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                           STAKING TESTS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function testStakeFirstUser() public {
        (uint256 baseReward, uint256 quoteReward) = tracker.stake(user1, INITIAL_SHARES);

        // First staker should get no rewards
        assertEq(baseReward, 0);
        assertEq(quoteReward, 0);

        UserRewardData memory userData = tracker.getUserData(user1);
        assertEq(userData.shares, INITIAL_SHARES);
        assertEq(userData.baseRewardDebt, 0);
        assertEq(userData.quoteRewardDebt, 0);
    }

    function testStakeZeroSharesReverts() public {
        vm.expectRevert(RewardsTrackerLib.ZeroShareStake.selector);
        tracker.stake(user1, 0);
    }

    function testStakeWithPendingRewards() public {
        // Setup: User1 stakes, then rewards are added
        tracker.stake(user1, INITIAL_SHARES);
        tracker.addBaseRewards(baseAsset, INITIAL_BASE_REWARDS);
        tracker.addQuoteRewards(baseAsset, quoteAsset, INITIAL_QUOTE_REWARDS);

        // User1 stakes more - should get pending rewards
        (uint256 baseReward, uint256 quoteReward) = tracker.stake(user1, INITIAL_SHARES);

        assertEq(baseReward, INITIAL_BASE_REWARDS);
        assertEq(quoteReward, INITIAL_QUOTE_REWARDS);
    }

    function testStakeMultipleUsersRewardDistribution() public {
        // User1 stakes
        tracker.stake(user1, INITIAL_SHARES);

        // Add rewards
        tracker.addBaseRewards(baseAsset, INITIAL_BASE_REWARDS);

        // User2 stakes same amount
        tracker.stake(user2, INITIAL_SHARES);

        // Add more rewards
        tracker.addBaseRewards(baseAsset, INITIAL_BASE_REWARDS);

        // Both users should get equal share of second reward batch
        (uint256 user1Rewards,) = tracker.getPendingRewards(user1);
        (uint256 user2Rewards,) = tracker.getPendingRewards(user2);

        assertEq(user1Rewards, INITIAL_BASE_REWARDS + INITIAL_BASE_REWARDS / 2);
        assertEq(user2Rewards, INITIAL_BASE_REWARDS / 2);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            UNSTAKING TESTS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function testUnstakeZeroSharesReverts() public {
        tracker.stake(user1, INITIAL_SHARES);

        vm.expectRevert(RewardsTrackerLib.ZeroShareStake.selector);
        tracker.unstake(user1, 0);
    }

    function testUnstakeInsufficientSharesReverts() public {
        tracker.stake(user1, INITIAL_SHARES);

        vm.expectRevert(RewardsTrackerLib.InsufficientShares.selector);
        tracker.unstake(user1, INITIAL_SHARES + 1);
    }

    function testUnstakePartialWithRewards() public {
        // Setup
        tracker.stake(user1, INITIAL_SHARES);
        tracker.addBaseRewards(baseAsset, INITIAL_BASE_REWARDS);

        uint96 unstakeAmount = INITIAL_SHARES / 2;
        (uint256 baseReward, uint256 quoteReward) = tracker.unstake(user1, unstakeAmount);

        // Should get all accumulated rewards
        assertEq(baseReward, INITIAL_BASE_REWARDS);
        assertEq(quoteReward, 0);

        UserRewardData memory userData = tracker.getUserData(user1);
        assertEq(userData.shares, INITIAL_SHARES - unstakeAmount);
    }

    function testUnstakeComplete() public {
        tracker.stake(user1, INITIAL_SHARES);
        tracker.addBaseRewards(baseAsset, INITIAL_BASE_REWARDS);

        (uint256 baseReward,) = tracker.unstake(user1, INITIAL_SHARES);

        assertEq(baseReward, INITIAL_BASE_REWARDS);

        UserRewardData memory userData = tracker.getUserData(user1);
        assertEq(userData.shares, 0);

        RewardPoolDataMemory memory poolData = tracker.getRewardsPoolData();
        assertEq(poolData.totalShares, 0);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            CLAIMING TESTS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function testClaimNoSharesReverts() public {
        vm.expectRevert(RewardsTrackerLib.ZeroShareClaim.selector);
        tracker.claim(user1);
    }

    function testClaimWithRewards() public {
        tracker.stake(user1, INITIAL_SHARES);
        tracker.addBaseRewards(baseAsset, INITIAL_BASE_REWARDS);
        tracker.addQuoteRewards(baseAsset, quoteAsset, INITIAL_QUOTE_REWARDS);

        (uint256 baseReward, uint256 quoteReward) = tracker.claim(user1);

        assertEq(baseReward, INITIAL_BASE_REWARDS);
        assertEq(quoteReward, INITIAL_QUOTE_REWARDS);

        // Second claim should return zero
        (uint256 baseReward2, uint256 quoteReward2) = tracker.claim(user1);
        assertEq(baseReward2, 0);
        assertEq(quoteReward2, 0);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            PRECISION TESTS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function testPrecisionLossSmallRewards() public {
        uint96 shares = 1000e18;
        uint128 rewards = 1; // 1 wei reward

        tracker.stake(user1, shares);
        tracker.addBaseRewards(baseAsset, rewards);

        (uint256 claimedReward,) = tracker.claim(user1);

        // With large shares and tiny rewards, precision loss should be minimal
        // The reward per share will be very small but should still be calculable
        assertTrue(claimedReward <= rewards);
    }

    function testPrecisionLossLargeNumbers() public {
        // Use large values that won't cause overflow in rewards * PRECISION_FACTOR
        uint96 shares = 1e28;
        uint128 rewards = 1e25;

        tracker.stake(user1, shares);
        tracker.addBaseRewards(baseAsset, rewards);

        (uint256 claimedReward,) = tracker.claim(user1);

        // Should handle large values without overflow
        assertEq(claimedReward, rewards);
    }

    function testFuzz_precisionConsistency(uint96 shares1, uint96 shares2, uint128 rewards) public {
        // Use safe bounds to avoid overflow in rewards * PRECISION_FACTOR
        shares1 = uint96(bound(shares1, 1e18, 1e26)); // Safe range for uint96
        shares2 = uint96(bound(shares2, 1e18, 1e26)); // Safe range for uint96
        rewards = uint128(bound(rewards, 1e18, 1e25)); // Safe range to avoid overflow in rewards * PRECISION_FACTOR

        // Two users stake
        tracker.stake(user1, shares1);
        tracker.stake(user2, shares2);

        // Add rewards
        tracker.addBaseRewards(baseAsset, rewards);

        // Claim rewards
        (uint256 reward1,) = tracker.claim(user1);
        (uint256 reward2,) = tracker.claim(user2);

        uint256 totalClaimed = reward1 + reward2;
        uint256 expectedTotal = rewards;

        // Check precision loss behavior based on share ratio
        uint256 ratio = shares1 > shares2 ? shares1 / shares2 : shares2 / shares1;
        uint256 diff = totalClaimed > expectedTotal ? totalClaimed - expectedTotal : expectedTotal - totalClaimed;

        if (ratio <= 1000) {
            // For reasonable ratios, precision loss should be minimal
            assertLt(diff, expectedTotal / 1000);
        } else {
            // For extreme ratios, precision loss is expected but should not exceed total reward
            assertLe(totalClaimed, expectedTotal);
            // Allow larger precision loss for extreme ratios (up to 10%)
            assertLt(diff, expectedTotal / 10);
        }
    }

    function testSmallPrecisionQuoteRewards() public {
        // Test with USDC-style 6 decimal precision, but use larger amounts to avoid precision loss
        uint96 shares = 1e18; // 1 token worth of shares
        uint128 baseRewards = 100e18; // 100 base tokens
        uint128 quoteRewards = 100e6; // 100 USDC (6 decimals) - reasonable amount

        tracker.stake(user1, shares);
        tracker.addBaseRewards(baseAsset, baseRewards);
        tracker.addQuoteRewards(baseAsset, quoteAsset, quoteRewards);

        (uint256 claimedBase, uint256 claimedQuote) = tracker.claim(user1);

        assertEq(claimedBase, baseRewards);
        assertEq(claimedQuote, quoteRewards);
    }

    function testVerySmallRewardsWithLargeShares() public {
        // Test edge case where small rewards might get lost due to precision
        uint96 shares = 1000e18; // Large share amount
        uint128 rewards = 1e6; // Very small reward (1 USDC)

        tracker.stake(user1, shares);
        tracker.addBaseRewards(baseAsset, rewards);

        (uint256 claimedReward,) = tracker.claim(user1);

        // With large shares and tiny rewards, we might lose precision
        // The reward should be 0 or the full amount, never more than the added amount
        assertTrue(claimedReward <= rewards);

        // But due to integer division, (rewards * PRECISION_FACTOR / shares) might be 0
        uint256 expectedRewardPerShare = (rewards * PRECISION_FACTOR) / shares;
        if (expectedRewardPerShare == 0) assertEq(claimedReward, 0);
        else assertEq(claimedReward, rewards);
    }

    function testRewardDebtConsistency() public {
        // User stakes
        tracker.stake(user1, INITIAL_SHARES);

        // Add rewards
        tracker.addBaseRewards(baseAsset, INITIAL_BASE_REWARDS);

        // Check pending rewards
        (uint256 pendingBefore,) = tracker.getPendingRewards(user1);

        // Claim rewards
        (uint256 claimed,) = tracker.claim(user1);

        // Pending and claimed should match
        assertEq(pendingBefore, claimed);

        // Check that pending is now zero
        (uint256 pendingAfter,) = tracker.getPendingRewards(user1);
        assertEq(pendingAfter, 0);
    }

    function testMultipleStakesSameUser() public {
        // Initial stake
        tracker.stake(user1, INITIAL_SHARES);
        tracker.addBaseRewards(baseAsset, INITIAL_BASE_REWARDS);

        // Second stake should auto-claim previous rewards
        (uint256 baseReward,) = tracker.stake(user1, INITIAL_SHARES);

        assertEq(baseReward, INITIAL_BASE_REWARDS);

        UserRewardData memory userData = tracker.getUserData(user1);
        assertEq(userData.shares, INITIAL_SHARES * 2);
    }

    function testZeroTotalSharesNoRewardDistribution() public {
        tracker.addBaseRewards(baseAsset, INITIAL_BASE_REWARDS);
        (uint256 baseReward,) = tracker.stake(user1, INITIAL_SHARES);

        // Should get no rewards since they were added before anyone staked
        assertEq(baseReward, 0);

        (uint256 pending,) = tracker.getPendingRewards(user1);
        assertEq(pending, 0);
    }

    function testExtremeShareRatios_SmallHolderImpact() public {
        // Realistic scenario: Whale vs retail user
        uint96 whaleShares = 100_000e18; // 100K tokens
        uint96 retailShares = 1e18; // 1 token (100,000:1 ratio)
        uint128 smallReward = 100e18; // 100 token reward

        tracker.stake(user1, whaleShares); // Whale
        tracker.stake(user2, retailShares); // Retail

        tracker.addBaseRewards(baseAsset, smallReward);

        (uint256 whaleReward,) = tracker.claim(user1);
        (uint256 retailReward,) = tracker.claim(user2);

        uint256 totalShares = whaleShares + retailShares;
        uint256 expectedWhaleReward = (uint256(smallReward) * uint256(whaleShares)) / totalShares;
        uint256 expectedRetailReward = (uint256(smallReward) * uint256(retailShares)) / totalShares;

        uint256 totalClaimedActual = whaleReward + retailReward;

        assertApproxEqRel(whaleReward, expectedWhaleReward, 1e8); // 0.00000001% tolerance
        assertApproxEqRel(retailReward, expectedRetailReward, 1e8); // 0.00000001% tolerance

        // Total claimed should not exceed total reward
        assertLe(totalClaimedActual, smallReward);
    }

    function testDustRewards() public {
        // Very realistic scenario: Trading fees generating small rewards
        uint96 whaleShares = 5_000_000e18; // 5M tokens
        uint96 midShares = 100_000e18; // 100k tokens
        uint96 smallShares = 1000e18; // 1k tokens
        uint96 dustShares = 10e18; // 10 tokens
        uint128 dustReward = 1e18; // 1 token reward from fees

        // All users stake
        tracker.stake(user1, whaleShares);
        tracker.stake(user2, midShares);
        tracker.stake(user3, smallShares);
        tracker.stake(user4, dustShares);

        // Add tiny reward (common in fee distribution)
        tracker.addBaseRewards(baseAsset, dustReward);

        // Check rewards
        (uint256 whaleReward,) = tracker.claim(user1);
        (uint256 midReward,) = tracker.claim(user2);
        (uint256 smallReward,) = tracker.claim(user3);
        (uint256 dustUserReward,) = tracker.claim(user4);

        uint256 totalClaimed = whaleReward + midReward + smallReward + dustUserReward;
        assertTrue(totalClaimed < dustReward);
        assertTrue(whaleReward > midReward);
        assertTrue(midReward >= smallReward);
        assertTrue(smallReward >= dustUserReward);
    }
}
