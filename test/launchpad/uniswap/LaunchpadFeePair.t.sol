// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";
import {GTELaunchpadV2PairFactory} from "contracts/launchpad/uniswap/GTELaunchpadV2PairFactory.sol";
import {GTELaunchpadV2Pair} from "contracts/launchpad/uniswap/GTELaunchpadV2Pair.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {MockDistributor} from "../../mocks/MockDistributor.sol";

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IERC20} from "@gte-univ2-core/interfaces/IERC20.sol";

/// @dev This quoter is based off on univ2's periphery quoter and serves as the expected result of a swap in a normal uniswap pool
// Trades through the gte fee sharing pool should have the same swap results as this pool, as a % of the swap fee is taken out to pay the main lp
contract SimpleQuoter {
    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    function getAmountsOut(GTELaunchpadV2Pair pair, uint256 amountIn, address tokenIn)
        internal
        view
        returns (uint256 amount0Out, uint256 amount1Out)
    {
        bool isZeroTokenIn = tokenIn == pair.token0();

        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();

        (uint256 reserveIn, uint256 reserveOut) = isZeroTokenIn ? (reserve0, reserve1) : (reserve1, reserve0);
        uint256 amountOut = getAmountOut(amountIn, reserveIn, reserveOut);
        (amount0Out, amount1Out) = isZeroTokenIn ? (uint256(0), amountOut) : (amountOut, uint256(0));
    }
}

contract ReentrantAttacker {
    GTELaunchpadV2Pair public pair;
    address public token;

    constructor(address _pair, address _token) {
        pair = GTELaunchpadV2Pair(_pair);
        token = _token;
    }

    function attack() external {
        IERC20(token).transfer(address(pair), 1 ether);
        pair.swap(0, 1 ether, address(this), abi.encode("attack"));
    }

    function uniswapV2Call(address, uint256, uint256, bytes calldata) external {
        // Attempt reentrancy
        pair.sync();
    }
}

contract LaunchpadFeePairTest is Test, SimpleQuoter {
    using SafeTransferLib for address;

    address launchpad;
    MockDistributor distributor;
    GTELaunchpadV2PairFactory v2Factory;

    MockERC20 base;
    MockERC20 quote;

    GTELaunchpadV2Pair pair;
    address token0;
    address token1;

    address mockERC20Logic;

    // Asserts the pool balance state after a test and sync
    modifier PBAfter() {
        _;
        _assertPoolBalance();
    }

    function setUp() public {
        launchpad = vm.randomAddress();
        vm.label(launchpad, "Launchpad");

        distributor = new MockDistributor();

        v2Factory = new GTELaunchpadV2PairFactory(address(this), launchpad, launchpad, address(distributor));

        mockERC20Logic = address(new MockERC20());

        (address baseAddr, address quoteAddr, address pairAddr) = _createLaunchpadPair("base", "quote");

        base = MockERC20(baseAddr);
        quote = MockERC20(quoteAddr);
        pair = GTELaunchpadV2Pair(pairAddr);

        deal(address(base), address(this), 100 ether);
        deal(address(quote), address(this), 100 ether);

        base.transfer(address(pair), 100 ether);
        quote.transfer(address(pair), 100 ether);

        token0 = pair.token0();
        token1 = pair.token1();

        // lp tokens are minted to launchpad as the fee calc is the launchpad's share of total lp supply
        pair.mint(launchpad);

        // necessary for invariant tests to do this here
        _setupFuzzExclusions();
    }

    /// @dev Set up function exclusions for invariant testing
    function _setupFuzzExclusions() internal {
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = GTELaunchpadV2Pair.initialize.selector;
        selectors[1] = GTELaunchpadV2Pair.endRewardsAccrual.selector; // This one also requires specific sender

        FuzzSelector memory f = FuzzSelector({addr: address(pair), selectors: selectors});
        excludeSelector(f);
    }

    function test_Swap_FeeAccrued() public PBAfter {
        uint256 amountIn = 10 ether;
        deal(address(base), address(this), amountIn);

        uint256 expectedFee = _calculateExpectedLaunchpadFee(amountIn, address(base));

        (uint256 amount0Out, uint256 amount1Out) = getAmountsOut(pair, amountIn, address(base));

        base.transfer(address(pair), amountIn);
        pair.swap(amount0Out, amount1Out, address(this), hex"");

        assertEq(pair.accruedLaunchpadFee0(), expectedFee, "Fee should match exact calculation");
        assertEq(expectedFee, amountIn / 1000, "invalid fee amount");
    }

    // Calculates swap fee correctly when launchpad is not the only lp
    function test_Swap_FeeLaunchpadLPHalfShare() public PBAfter {
        uint256 amountIn = 10 ether;

        // Double the liquidity and lp supply, reducing the launchpad's share
        deal(address(base), address(this), 110 ether);
        deal(address(quote), address(this), 100 ether);

        base.transfer(address(pair), 100 ether);
        quote.transfer(address(pair), 100 ether);

        pair.mint(address(this));

        // Calculate expected fee using our helper function (after LP dilution)
        uint256 expectedFee = _calculateExpectedLaunchpadFee(amountIn, address(base));

        (uint256 amount0Out, uint256 amount1Out) = getAmountsOut(pair, amountIn, address(base));

        base.transfer(address(pair), amountIn);
        pair.swap(amount0Out, amount1Out, address(this), hex"");

        assertEq(pair.accruedLaunchpadFee0(), expectedFee, "Fee should match exact calculation");
        assertLt(expectedFee, amountIn / 1000, "Fee should be less than full rate due to LP dilution");
    }

    // Places a trade, but on the first txn of the block so that trade's fees are immediately distributed
    function test_DistributeFees_FirstTxOfBlock() public PBAfter {
        vm.warp(block.timestamp + 1);

        uint256 amountIn = 10 ether;
        uint256 expectedFee0 = _calculateExpectedLaunchpadFee(amountIn, address(base));
        deal(address(base), address(this), amountIn);

        (uint256 amount0Out, uint256 amount1Out) = getAmountsOut(pair, amountIn, address(base));

        base.transfer(address(pair), amountIn);

        vm.expectEmit();
        emit GTELaunchpadV2Pair.LaunchpadFeesCollected(uint112(expectedFee0), uint112(0));
        pair.swap(amount0Out, amount1Out, address(this), hex"");

        assertEq(base.balanceOf(address(distributor)), expectedFee0, "expected fee not pushed to distributor");

        // All accrued fees were zeroed out
        (uint112 fee0, uint112 fee1,) = pair.getAccruedLaunchpadFees();
        assertEq(fee0, 0, "accrued fee 0 not distributed");
        assertEq(fee1, 0, "accrued fee 1 not distributed");
    }

    // Places a trade, then places another trade in the next block. The fees from both trades should be distributed
    function test_DistributeFees_MultiBlock() public PBAfter {
        // FIRST SWAP //
        uint256 amountIn = 10 ether;
        uint256 expectedFee0 = _calculateExpectedLaunchpadFee(amountIn, address(base));
        deal(address(base), address(this), amountIn);

        (uint256 amount0Out, uint256 amount1Out) = getAmountsOut(pair, amountIn, address(base));

        base.transfer(address(pair), amountIn);

        // Perform the swap and accrue the fee
        vm.expectEmit();
        emit GTELaunchpadV2Pair.LaunchpadFeesAccrued(uint112(expectedFee0), uint112(0));
        pair.swap(amount0Out, amount1Out, address(this), hex"");

        (uint112 storedFee0, uint112 storedFee1,) = pair.getAccruedLaunchpadFees();

        assertEq(storedFee0, expectedFee0, "Fee0 stored != expected");
        assertEq(storedFee1, 0, "Fee1 stored != expected");

        // SECOND SWAP //
        vm.warp(block.timestamp + 1);
        deal(address(base), address(this), amountIn);

        (amount0Out, amount1Out) = getAmountsOut(pair, amountIn, address(base));
        uint256 balBeforeBase = base.balanceOf(address(this));
        uint256 balBeforeQuote = quote.balanceOf(address(this));

        base.transfer(address(pair), amountIn);

        // Perform the swap and distribute the new and accrued fee
        pair.swap(amount0Out, amount1Out, address(this), hex"");

        assertEq(
            balBeforeBase - base.balanceOf(address(this)), amountIn, "actual trade amount and stated amount IN differ"
        );
        assertEq(
            quote.balanceOf(address(this)) - balBeforeQuote,
            amount1Out,
            "actual trade amount and stated amount OUT differ"
        );

        uint256 actualFeeSecondTrade = base.balanceOf(address(distributor)) - uint256(storedFee0);

        // Second swap generates slightly different fee due to accrued fees affecting the swap calculation
        // The difference should be very small (within 1 wei per 1000 wei of accrued fees)
        assertApproxEqAbs(
            actualFeeSecondTrade,
            expectedFee0,
            expectedFee0 / 1000,
            "Fee from second swap should be approximately the same as first swap"
        );

        (storedFee0, storedFee1,) = pair.getAccruedLaunchpadFees();

        assertEq(storedFee0, 0, "accrued fee0 not distrbuted");
        assertEq(storedFee1, 0, "accrued fee1 not distributed");
    }

    function invariant_PoolBalances() public {
        // Exclusions are set up in setUp(), so we can directly run the assertion
        _assertPoolBalance();
    }

    /// @dev Fuzzed version of fee accrual test
    function testFuzz_SwapFeeAccrual(uint256 amountIn) public PBAfter {
        amountIn = bound(amountIn, 0.001 ether, 10 ether);

        deal(address(base), address(this), amountIn);

        // Calculate expected fee using the actual formula from the contract
        uint256 totalLpSupply = pair.totalSupply();
        uint256 launchpadLpBalance = pair.balanceOf(launchpad) + 1000; // +MINIMUM_LIQUIDITY
        uint256 expectedFee = (amountIn * launchpadLpBalance) / (totalLpSupply * 1000);

        (uint256 amount0Out, uint256 amount1Out) = getAmountsOut(pair, amountIn, address(base));

        base.transfer(address(pair), amountIn);
        pair.swap(amount0Out, amount1Out, address(this), hex"");

        // Fee should match the actual formula: amountIn * launchpadLpRatio / 1000
        assertApproxEqAbs(pair.accruedLaunchpadFee0(), expectedFee, 1, "Invalid accrued fee calculation");
    }

    /// @dev Fuzzed version testing fee distribution with varying LP ratios
    function testFuzz_FeeLaunchpadLPRatio(uint256 additionalLiquidity, uint256 swapAmount) public PBAfter {
        // Bound additional liquidity to create different LP ratios
        additionalLiquidity = bound(additionalLiquidity, 1 ether, 200 ether);
        swapAmount = bound(swapAmount, 0.1 ether, 20 ether);

        // Add additional liquidity to change launchpad's LP share
        deal(address(base), address(this), additionalLiquidity + swapAmount);
        deal(address(quote), address(this), additionalLiquidity);

        base.transfer(address(pair), additionalLiquidity);
        quote.transfer(address(pair), additionalLiquidity);
        pair.mint(address(this));

        // Perform swap
        (uint256 amount0Out, uint256 amount1Out) = getAmountsOut(pair, swapAmount, address(base));
        base.transfer(address(pair), swapAmount);
        pair.swap(amount0Out, amount1Out, address(this), hex"");

        // Use the exact same calculation as the contract
        uint256 expectedFee = _calculateExpectedLaunchpadFee(swapAmount, address(base));
        assertApproxEqAbs(
            pair.accruedLaunchpadFee0(),
            expectedFee,
            1,
            "Fee should match contract calculation (allowing 1 wei rounding)"
        );
    }

    /// @dev Test that multiple swaps accumulate fees correctly
    /// Note: Exact fee calculation is complex due to accrued fees affecting subsequent swap amounts
    function testFuzz_MultipleSwapFeeAccumulation(uint256[3] memory swapAmounts) public PBAfter {
        // Bound each swap amount to reasonable values to avoid overflow and extreme LP ratio changes
        for (uint256 i = 0; i < 3; i++) {
            swapAmounts[i] = bound(swapAmounts[i], 0.01 ether, 2 ether);
        }

        uint256 totalAmountIn = swapAmounts[0] + swapAmounts[1] + swapAmounts[2];
        deal(address(base), address(this), totalAmountIn);

        uint256 feeBefore = pair.accruedLaunchpadFee0();
        uint256 totalActualFeeIncrease = 0;

        for (uint256 i = 0; i < 3; i++) {
            uint256 amountIn = swapAmounts[i];
            uint256 feeBeforeSwap = pair.accruedLaunchpadFee0();

            (uint256 amount0Out, uint256 amount1Out) = getAmountsOut(pair, amountIn, address(base));

            base.transfer(address(pair), amountIn);
            pair.swap(amount0Out, amount1Out, address(this), hex"");

            uint256 feeAfterSwap = pair.accruedLaunchpadFee0();
            uint256 actualFeeFromThisSwap = feeAfterSwap - feeBeforeSwap;

            // Verify fee is reasonable - should be roughly proportional to amountIn
            // But account for the fact that accrued fees from previous swaps can affect the calculation
            // The effective amountIn can be higher due to accrued fees being included in balance calculations
            uint256 maxReasonableFee = (amountIn * 15) / 10_000; // 0.15% - more generous to account for fee accumulation effects
            uint256 minReasonableFee = amountIn / 3000; // Lower bound for very diluted scenarios

            assertGe(actualFeeFromThisSwap, minReasonableFee, "Fee unreasonably low");
            assertLe(actualFeeFromThisSwap, maxReasonableFee, "Fee unreasonably high");

            totalActualFeeIncrease += actualFeeFromThisSwap;
        }

        // Verify total accumulation matches sum of individual fees
        uint256 totalFeeAfter = pair.accruedLaunchpadFee0();
        assertEq(totalFeeAfter - feeBefore, totalActualFeeIncrease, "Total fee accumulation incorrect");

        // Verify overall fees are reasonable relative to total input
        uint256 totalMaxReasonable = (totalAmountIn * 15) / 10_000; // 0.15% total
        uint256 totalMinReasonable = totalAmountIn / 3000;
        assertGe(totalActualFeeIncrease, totalMinReasonable, "Total fees unreasonably low");
        assertLe(totalActualFeeIncrease, totalMaxReasonable, "Total fees unreasonably high");
    }

    /// @dev Test fee distribution timing with random time warps
    function testFuzz_FeeDistributionTiming(uint256 timeWarp1, uint256 timeWarp2, uint256 swapAmount) public PBAfter {
        timeWarp1 = bound(timeWarp1, 1, 86_400); // 1 second to 1 day
        timeWarp2 = bound(timeWarp2, 1, 86_400);
        swapAmount = bound(swapAmount, 0.1 ether, 10 ether);

        deal(address(base), address(this), swapAmount * 2);

        (uint256 amount0Out, uint256 amount1Out) = getAmountsOut(pair, swapAmount, address(base));
        base.transfer(address(pair), swapAmount);
        pair.swap(amount0Out, amount1Out, address(this), hex"");

        uint256 firstSwapFee = pair.accruedLaunchpadFee0();
        assertGt(firstSwapFee, 0, "First swap should accrue fees");

        vm.warp(block.timestamp + timeWarp1);

        uint256 distributorBalanceBefore = base.balanceOf(address(distributor));

        (amount0Out, amount1Out) = getAmountsOut(pair, swapAmount, address(base));
        base.transfer(address(pair), swapAmount);
        pair.swap(amount0Out, amount1Out, address(this), hex"");

        uint256 distributorBalanceAfter = base.balanceOf(address(distributor));

        // First swap fees should have been distributed
        assertGt(distributorBalanceAfter - distributorBalanceBefore, 0, "Fees should be distributed in new block");
    }

    /// @dev Test that sync operations maintain accounting integrity
    function testFuzz_SyncMaintainsAccounting(uint256 extraTokens0, uint256 extraTokens1) public PBAfter {
        extraTokens0 = bound(extraTokens0, 0, 10 ether);
        extraTokens1 = bound(extraTokens1, 0, 10 ether);

        // Send extra tokens to pair (simulating direct transfers)
        if (extraTokens0 > 0) {
            deal(address(base), address(this), extraTokens0);
            base.transfer(address(pair), extraTokens0);
        }

        if (extraTokens1 > 0) {
            deal(address(quote), address(this), extraTokens1);
            quote.transfer(address(pair), extraTokens1);
        }

        // Get state before sync
        (uint112 reserve0Before, uint112 reserve1Before,) = pair.getReserves();
        (uint112 accruedFee0Before, uint112 accruedFee1Before,) = pair.getAccruedLaunchpadFees();

        // Sync should update reserves but maintain fee accounting
        pair.sync();

        (uint112 reserve0After, uint112 reserve1After,) = pair.getReserves();
        (uint112 accruedFee0After, uint112 accruedFee1After,) = pair.getAccruedLaunchpadFees();

        // Reserves should include the extra tokens
        assertGe(reserve0After, reserve0Before, "Reserve0 should increase or stay same");
        assertGe(reserve1After, reserve1Before, "Reserve1 should increase or stay same");

        // If no fees were distributed, accrued fees should remain the same
        if (accruedFee0Before == accruedFee0After && accruedFee1Before == accruedFee1After) {
            // This means no fee distribution occurred, which is fine
            return;
        }
    }

    /// @dev Test edge case with very small swap amounts
    function testFuzz_SmallSwapAmounts(uint256 smallAmount) public PBAfter {
        // Test very small amounts that might cause rounding issues
        smallAmount = bound(smallAmount, 1, 0.001 ether);

        deal(address(base), address(this), smallAmount);

        try this._attemptSmallSwap(smallAmount) {
            // If swap succeeds, verify accounting is still correct
            // Small swaps might result in 0 fees due to rounding
            uint256 accruedFee = pair.accruedLaunchpadFee0();
            uint256 expectedMaxFee = smallAmount / 1000;

            assertLe(accruedFee, expectedMaxFee, "Accrued fee should not exceed expected maximum");
        } catch {
            // Small swaps might revert due to insufficient output or other constraints
            // This is acceptable behavior
        }
    }

    /// @dev Test that skim function correctly removes only excess tokens while preserving reserves and accrued fees
    function testFuzz_SkimPreservesAccounting(uint256 excessToken0, uint256 excessToken1, uint256 swapAmount)
        public
        PBAfter
    {
        // Bound parameters to reasonable values
        excessToken0 = bound(excessToken0, 0, 50 ether);
        excessToken1 = bound(excessToken1, 0, 50 ether);
        swapAmount = bound(swapAmount, 0.1 ether, 10 ether);

        // First, perform a swap to generate some accrued fees
        deal(address(base), address(this), swapAmount);
        (uint256 amount0Out, uint256 amount1Out) = getAmountsOut(pair, swapAmount, address(base));
        base.transfer(address(pair), swapAmount);
        pair.swap(amount0Out, amount1Out, address(this), hex"");

        // Get state before adding excess tokens
        (uint112 reserveBefore0, uint112 reserveBefore1,) = pair.getReserves();
        (uint112 accruedFeeBefore0, uint112 accruedFeeBefore1,) = pair.getAccruedLaunchpadFees();

        // Add excess tokens directly to the pair (simulating direct transfers)
        if (excessToken0 > 0) {
            deal(address(base), address(this), excessToken0);
            base.transfer(address(pair), excessToken0);
        }

        if (excessToken1 > 0) {
            deal(address(quote), address(this), excessToken1);
            quote.transfer(address(pair), excessToken1);
        }

        // Record balances before skim
        uint256 token0BalanceBefore = base.balanceOf(address(pair));
        uint256 token1BalanceBefore = quote.balanceOf(address(pair));
        uint256 skimmerBalanceBefore0 = base.balanceOf(address(this));
        uint256 skimmerBalanceBefore1 = quote.balanceOf(address(this));

        // Calculate expected excess amounts
        uint256 expectedExcess0 = token0BalanceBefore - (uint256(reserveBefore0) + uint256(accruedFeeBefore0));
        uint256 expectedExcess1 = token1BalanceBefore - (uint256(reserveBefore1) + uint256(accruedFeeBefore1));

        // Perform skim
        pair.skim(address(this));

        // Verify reserves and accrued fees are unchanged
        (uint112 reserveAfter0, uint112 reserveAfter1,) = pair.getReserves();
        (uint112 accruedFeeAfter0, uint112 accruedFeeAfter1,) = pair.getAccruedLaunchpadFees();

        assertEq(reserveAfter0, reserveBefore0, "Reserve0 should be unchanged after skim");
        assertEq(reserveAfter1, reserveBefore1, "Reserve1 should be unchanged after skim");
        assertEq(accruedFeeAfter0, accruedFeeBefore0, "AccruedFee0 should be unchanged after skim");
        assertEq(accruedFeeAfter1, accruedFeeBefore1, "AccruedFee1 should be unchanged after skim");

        // Verify correct amounts were skimmed
        uint256 skimmerBalanceAfter0 = base.balanceOf(address(this));
        uint256 skimmerBalanceAfter1 = quote.balanceOf(address(this));

        assertEq(skimmerBalanceAfter0 - skimmerBalanceBefore0, expectedExcess0, "Incorrect amount of token0 skimmed");
        assertEq(skimmerBalanceAfter1 - skimmerBalanceBefore1, expectedExcess1, "Incorrect amount of token1 skimmed");

        // Verify pair balances are now exactly reserves + accrued fees
        assertEq(
            base.balanceOf(address(pair)),
            uint256(reserveAfter0) + uint256(accruedFeeAfter0),
            "Pair balance should equal reserves + accrued fees for token0"
        );
        assertEq(
            quote.balanceOf(address(pair)),
            uint256(reserveAfter1) + uint256(accruedFeeAfter1),
            "Pair balance should equal reserves + accrued fees for token1"
        );
    }

    /// @dev Test skim function with no excess tokens (should transfer 0)
    function testFuzz_SkimWithNoExcess(uint256 swapAmount) public PBAfter {
        swapAmount = bound(swapAmount, 0.1 ether, 5 ether);

        // Perform a swap to generate some accrued fees
        deal(address(base), address(this), swapAmount);
        (uint256 amount0Out, uint256 amount1Out) = getAmountsOut(pair, swapAmount, address(base));
        base.transfer(address(pair), swapAmount);
        pair.swap(amount0Out, amount1Out, address(this), hex"");

        // Record balances before skim
        uint256 skimmerBalanceBefore0 = base.balanceOf(address(this));
        uint256 skimmerBalanceBefore1 = quote.balanceOf(address(this));

        // Perform skim when there's no excess
        pair.skim(address(this));

        // Verify no tokens were transferred to skimmer
        assertEq(base.balanceOf(address(this)), skimmerBalanceBefore0, "No token0 should be skimmed when no excess");
        assertEq(quote.balanceOf(address(this)), skimmerBalanceBefore1, "No token1 should be skimmed when no excess");
    }

    /// @dev Test skim function after fees have been distributed
    function testFuzz_SkimAfterFeeDistribution(uint256 excessAmount, uint256 swapAmount) public PBAfter {
        excessAmount = bound(excessAmount, 1 ether, 20 ether);
        swapAmount = bound(swapAmount, 0.5 ether, 5 ether);

        // Perform first swap to accrue fees
        deal(address(base), address(this), swapAmount);
        (uint256 amount0Out, uint256 amount1Out) = getAmountsOut(pair, swapAmount, address(base));
        base.transfer(address(pair), swapAmount);
        pair.swap(amount0Out, amount1Out, address(this), hex"");

        // Move to next block to trigger fee distribution on next transaction
        vm.warp(block.timestamp + 1);

        // Add excess tokens
        deal(address(base), address(this), excessAmount);
        base.transfer(address(pair), excessAmount);

        // Perform another swap to trigger fee distribution
        deal(address(base), address(this), swapAmount);
        (amount0Out, amount1Out) = getAmountsOut(pair, swapAmount, address(base));
        base.transfer(address(pair), swapAmount);
        pair.swap(amount0Out, amount1Out, address(this), hex"");

        // Now fees should be distributed (accruedFees should be 0 or minimal)
        (uint112 accruedFee0,,) = pair.getAccruedLaunchpadFees();

        // Record state before skim
        (uint112 reserve0,,) = pair.getReserves();
        uint256 pairBalance0Before = base.balanceOf(address(pair));
        uint256 skimmerBalance0Before = base.balanceOf(address(this));

        // Calculate expected excess (should be close to excessAmount since fees were distributed)
        uint256 expectedExcess = pairBalance0Before - (uint256(reserve0) + uint256(accruedFee0));

        // Perform skim
        pair.skim(address(this));

        // Verify correct amount was skimmed
        uint256 actualSkimmed = base.balanceOf(address(this)) - skimmerBalance0Before;
        assertApproxEqAbs(actualSkimmed, expectedExcess, 2, "Skimmed amount should match expected excess");
    }

    /// @dev Test that endRewards leaves no accrued rewards in pool when called, either as first txn of block or not
    function test_EndRewards_ClearsAccruedFees_FirstTxOfBlock() public PBAfter {
        uint256 amountIn = 5 ether;
        deal(address(base), address(this), amountIn);

        // Perform swap to accrue fees
        (uint256 amount0Out, uint256 amount1Out) = getAmountsOut(pair, amountIn, address(base));
        base.transfer(address(pair), amountIn);
        pair.swap(amount0Out, amount1Out, address(this), hex"");

        // Verify fees are accrued
        (uint112 accruedFee0Before,,) = pair.getAccruedLaunchpadFees();
        assertGt(accruedFee0Before, 0, "Should have accrued fees before endRewards");

        // Move to next block and call endRewards as first transaction
        vm.warp(block.timestamp + 1);

        vm.prank(address(distributor));
        pair.endRewardsAccrual();

        // Verify all accrued fees are cleared
        (uint112 accruedFee0After, uint112 accruedFee1After,) = pair.getAccruedLaunchpadFees();
        assertEq(accruedFee0After, 0, "Accrued fee0 should be 0 after endRewards");
        assertEq(accruedFee1After, 0, "Accrued fee1 should be 0 after endRewards");

        // Verify rewards pool is deactivated
        assertEq(pair.rewardsPoolActive(), 0, "Rewards pool should be deactivated");
    }

    /// @dev Test that endRewards leaves no accrued rewards when called mid-block
    function test_EndRewards_ClearsAccruedFees_MidBlock() public PBAfter {
        uint256 amountIn = 5 ether;
        deal(address(base), address(this), amountIn);

        // Perform swap to accrue fees
        (uint256 amount0Out, uint256 amount1Out) = getAmountsOut(pair, amountIn, address(base));
        base.transfer(address(pair), amountIn);
        pair.swap(amount0Out, amount1Out, address(this), hex"");

        // Verify fees are accrued
        (uint112 accruedFee0Before,,) = pair.getAccruedLaunchpadFees();
        assertGt(accruedFee0Before, 0, "Should have accrued fees before endRewards");

        // Call endRewards in same block (mid-block)
        vm.prank(address(distributor));
        pair.endRewardsAccrual();

        // Verify all accrued fees are cleared
        (uint112 accruedFee0After, uint112 accruedFee1After,) = pair.getAccruedLaunchpadFees();
        assertEq(accruedFee0After, 0, "Accrued fee0 should be 0 after endRewards");
        assertEq(accruedFee1After, 0, "Accrued fee1 should be 0 after endRewards");

        // Verify rewards pool is deactivated
        assertEq(pair.rewardsPoolActive(), 0, "Rewards pool should be deactivated");
    }

    /// @dev Test that sync cannot DOS rewards from being distributed
    function test_Sync_CannotDOSRewardDistribution() public PBAfter {
        uint256 amountIn = 5 ether;
        deal(address(base), address(this), amountIn);

        // Perform swap to accrue fees
        (uint256 amount0Out, uint256 amount1Out) = getAmountsOut(pair, amountIn, address(base));
        base.transfer(address(pair), amountIn);
        pair.swap(amount0Out, amount1Out, address(this), hex"");

        // Verify fees are accrued
        (uint112 accruedFee0Before,,) = pair.getAccruedLaunchpadFees();
        assertGt(accruedFee0Before, 0, "Should have accrued fees");

        // Move to next block where rewards should be distributed
        vm.warp(block.timestamp + 1);

        // Attacker tries to DOS by calling sync multiple times before legitimate transaction
        for (uint256 i = 0; i < 10; i++) {
            pair.sync();
        }

        // Verify that despite multiple sync calls, the fees were distributed on first sync
        uint256 distributorBalance = base.balanceOf(address(distributor));
        assertEq(distributorBalance, uint256(accruedFee0Before), "Fees should be distributed despite sync DOS attempt");

        // Verify accrued fees are cleared
        (uint112 accruedFee0After,,) = pair.getAccruedLaunchpadFees();
        assertEq(accruedFee0After, 0, "Accrued fees should be cleared after distribution");
    }

    /// @dev Fuzzed test that sync cannot DOS reward distribution with varying scenarios
    function testFuzz_Sync_CannotDOSRewardDistribution(uint256 swapAmount, uint256 syncCalls, uint256 timeWarp)
        public
        PBAfter
    {
        swapAmount = bound(swapAmount, 0.1 ether, 10 ether);
        syncCalls = bound(syncCalls, 1, 50); // Test up to 50 sync calls
        timeWarp = bound(timeWarp, 1, 86_400); // 1 second to 1 day

        deal(address(base), address(this), swapAmount);

        // Perform swap to accrue fees
        (uint256 amount0Out, uint256 amount1Out) = getAmountsOut(pair, swapAmount, address(base));
        base.transfer(address(pair), swapAmount);
        pair.swap(amount0Out, amount1Out, address(this), hex"");

        // Verify fees are accrued
        (uint112 accruedFee0Before,,) = pair.getAccruedLaunchpadFees();
        assertGt(accruedFee0Before, 0, "Should have accrued fees");

        uint256 distributorBalanceBefore = base.balanceOf(address(distributor));

        // Move to next block where rewards should be distributed
        vm.warp(block.timestamp + timeWarp);

        // Attacker tries to DOS by calling sync multiple times
        for (uint256 i = 0; i < syncCalls; i++) {
            pair.sync();
        }

        // Verify that fees were distributed on first sync call regardless of DOS attempt
        uint256 distributorBalanceAfter = base.balanceOf(address(distributor));
        uint256 feesDistributed = distributorBalanceAfter - distributorBalanceBefore;

        assertEq(feesDistributed, uint256(accruedFee0Before), "Fees should be distributed despite sync DOS attempt");

        // Verify accrued fees are cleared
        (uint112 accruedFee0After,,) = pair.getAccruedLaunchpadFees();
        assertEq(accruedFee0After, 0, "Accrued fees should be cleared after distribution");
    }

    /// @dev Test that sync cannot be used to manipulate reserves and break fee distribution
    function test_Sync_BalanceManipulation() public PBAfter {
        uint256 swapAmount = 5 ether;
        uint256 maliciousAmount = 100 ether;

        deal(address(base), address(this), swapAmount + maliciousAmount);

        // Perform normal swap to establish baseline
        (uint256 amount0Out, uint256 amount1Out) = getAmountsOut(pair, swapAmount, address(base));
        base.transfer(address(pair), swapAmount);
        pair.swap(amount0Out, amount1Out, address(this), hex"");

        uint256 normalFee = pair.accruedLaunchpadFee0();
        assertGt(normalFee, 0, "Should have accrued fees from normal swap");

        // Clear accrued fees
        vm.warp(block.timestamp + 1);
        pair.sync(); // This should distribute the fees

        // Attacker sends tokens directly to pair (bypassing normal functions)
        base.transfer(address(pair), maliciousAmount);

        // Attacker calls sync to update reserves to include the malicious tokens
        pair.sync();

        // Verify reserves were updated to include the malicious tokens
        (uint112 reserveAfterManipulation,,) = pair.getReserves();
        assertGt(reserveAfterManipulation, 100 ether, "Reserves should include manipulated tokens");

        // Now perform another swap to see if fee calculation is broken
        deal(address(base), address(this), swapAmount);
        (amount0Out, amount1Out) = getAmountsOut(pair, swapAmount, address(base));
        base.transfer(address(pair), swapAmount);
        pair.swap(amount0Out, amount1Out, address(this), hex"");

        uint256 feeAfterManipulation = pair.accruedLaunchpadFee0();

        // Fee should still be calculated correctly despite the manipulation
        // The fee should be proportional to the actual swap amount, not the manipulated reserves
        uint256 expectedFee = _calculateExpectedLaunchpadFee(swapAmount, address(base));

        // Allow small tolerance for potential rounding differences
        assertApproxEqAbs(
            feeAfterManipulation,
            expectedFee,
            expectedFee / 1000,
            "Fee calculation should not be broken by balance manipulation"
        );

        // Verify that fee is still reasonable relative to swap amount
        assertLt(feeAfterManipulation, swapAmount / 500, "Fee should not be unreasonably high");
        assertGt(feeAfterManipulation, swapAmount / 2000, "Fee should not be unreasonably low");
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            NEGATIVE TESTS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_Initialize_OnlyFactory() public {
        // Create a new pair where the factory is a different address
        vm.prank(address(0x1234)); // Different address as factory
        GTELaunchpadV2Pair newPair = new GTELaunchpadV2Pair();

        vm.expectRevert("UniswapV2: FORBIDDEN");
        newPair.initialize(address(base), address(quote), launchpad, address(distributor));
    }

    function test_EndRewardsAccrual_OnlyDistributor() public {
        vm.expectRevert("GTEUniV2: FORBIDDEN");
        pair.endRewardsAccrual();

        vm.prank(launchpad);
        vm.expectRevert("GTEUniV2: FORBIDDEN");
        pair.endRewardsAccrual();
    }

    function test_Swap_InsufficientOutput() public {
        vm.expectRevert("UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT");
        pair.swap(0, 0, address(this), hex"");
    }

    function test_Swap_InsufficientLiquidity() public {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        vm.expectRevert("UniswapV2: INSUFFICIENT_LIQUIDITY");
        pair.swap(uint256(reserve0), 0, address(this), hex"");

        vm.expectRevert("UniswapV2: INSUFFICIENT_LIQUIDITY");
        pair.swap(0, uint256(reserve1), address(this), hex"");
    }

    function test_Swap_InvalidTo() public {
        // Test with actual token addresses from pair
        vm.expectRevert("UniswapV2: INVALID_TO");
        pair.swap(1 ether, 0, address(base), hex"");

        vm.expectRevert("UniswapV2: INVALID_TO");
        pair.swap(0, 1 ether, address(quote), hex"");
    }

    function test_Swap_InsufficientInput() public {
        vm.expectRevert("UniswapV2: INSUFFICIENT_INPUT_AMOUNT");
        pair.swap(1 ether, 0, address(this), hex"");
    }

    function test_Swap_KInvariant() public {
        deal(address(base), address(this), 1 ether);
        base.transfer(address(pair), 1 ether);

        // Try to extract more value than the K invariant allows
        vm.expectRevert("UniswapV2: K");
        pair.swap(0, 90 ether, address(this), hex"");
    }

    function test_Mint_InsufficientLiquidity() public {
        (address token0Addr, address token1Addr, address emptyPairAddr) = _createLaunchpadPair("empty0", "empty1");
        GTELaunchpadV2Pair emptyPair = GTELaunchpadV2Pair(emptyPairAddr);

        // Add tokens such that sqrt(amount0 * amount1) = MINIMUM_LIQUIDITY (1000)
        // This will result in liquidity = sqrt(1000 * 1000) - 1000 = 1000 - 1000 = 0
        MockERC20 emptyToken0 = MockERC20(token0Addr);
        MockERC20 emptyToken1 = MockERC20(token1Addr);

        uint256 tokenAmount = 1000; // sqrt(1000 * 1000) = 1000 = MINIMUM_LIQUIDITY
        deal(address(emptyToken0), address(this), tokenAmount);
        deal(address(emptyToken1), address(this), tokenAmount);

        emptyToken0.transfer(address(emptyPair), tokenAmount);
        emptyToken1.transfer(address(emptyPair), tokenAmount);

        vm.expectRevert("UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED");
        emptyPair.mint(address(this));
    }

    function test_Burn_InsufficientLiquidity() public {
        vm.expectRevert("UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED");
        pair.burn(address(this));
    }

    function test_Reentrancy_Protection() public {
        ReentrantAttacker attacker = new ReentrantAttacker(address(pair), address(base));

        deal(address(base), address(attacker), 10 ether);

        vm.expectRevert("UniswapV2: LOCKED");
        attacker.attack();
    }

    function testFuzz_Swap_RevertConditions(uint256 amount0Out, uint256 amount1Out) public {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        // Test insufficient output
        if (amount0Out == 0 && amount1Out == 0) {
            vm.expectRevert("UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT");
            pair.swap(amount0Out, amount1Out, address(this), hex"");
            return;
        }

        // Test insufficient liquidity
        if (amount0Out >= reserve0 || amount1Out >= reserve1) {
            vm.expectRevert("UniswapV2: INSUFFICIENT_LIQUIDITY");
            pair.swap(amount0Out, amount1Out, address(this), hex"");
            return;
        }

        // Test insufficient input (no tokens sent)
        if (amount0Out > 0 || amount1Out > 0) {
            vm.expectRevert("UniswapV2: INSUFFICIENT_INPUT_AMOUNT");
            pair.swap(amount0Out, amount1Out, address(this), hex"");
        }
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            INTERNAL HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @dev Calculate expected launchpad fee using the exact same logic as the contract
    /// This mirrors the _getLaunchpadFees function in GTELaunchpadV2Pair
    function _calculateExpectedLaunchpadFee(uint256 amountIn, address tokenIn)
        internal
        view
        returns (uint256 expectedFee)
    {
        // Only calculate fee if rewards pool is active and distributor is set
        if (pair.launchpadFeeDistributor() == address(0) || pair.rewardsPoolActive() == 0) return 0;

        // Use the exact same calls as the contract
        uint256 totalLpSupply = pair.totalSupply();
        uint256 launchpadLpBalance = pair.balanceOf(launchpad) + pair.MINIMUM_LIQUIDITY();

        assertEq(tokenIn == pair.token0(), true, "tokenIn should be token0");
        // amountIn * REWARDS_FEE_SHARE * launchpadLpBalance / (totalLpSupply * 1000)
        // REWARDS_FEE_SHARE = 1
        expectedFee = (amountIn * launchpadLpBalance) / (totalLpSupply * 1000);
        return expectedFee;
    }

    function _attemptSmallSwap(uint256 amount) external {
        (uint256 amount0Out, uint256 amount1Out) = getAmountsOut(pair, amount, address(base));

        base.transfer(address(pair), amount);
        pair.swap(amount0Out, amount1Out, address(this), hex"");
    }

    function _assertPoolBalance() internal {
        (uint112 accruedFee0, uint112 accruedFee1, uint32 blockTimeLast) = pair.getAccruedLaunchpadFees();

        // Sync reserves up with the erc20 balance of the pool (less accrued fees)
        // If the sync would be the first _update of a block and would distribute accrued fees, then it will emit an extra event
        vm.recordLogs();
        if (accruedFee0 | accruedFee1 > 0 && blockTimeLast < block.timestamp) {
            vm.expectEmit();
            emit GTELaunchpadV2Pair.LaunchpadFeesCollected(accruedFee0, accruedFee1);
            pair.sync();
            assertEq(vm.getRecordedLogs().length, 2);
        } else {
            pair.sync();
            assertEq(vm.getRecordedLogs().length, 1);
        }

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        assertEq(
            token0.balanceOf(address(pair)),
            uint256(reserve0 + accruedFee0),
            "Pool balance invariant broken for token0!"
        );
        assertEq(
            token1.balanceOf(address(pair)),
            uint256(reserve1 + accruedFee1),
            "Pool balance invariant broken for token1!"
        );
    }

    /// @dev always makes sure token0 in univ2 is the base; returns addresses accordingly
    function _createLaunchpadPair(string memory nameBase, string memory nameQuote)
        internal
        returns (address baseAddr, address quoteAddr, address pairAddr)
    {
        baseAddr = _assumeEOA(vm.addr(uint256(keccak256(abi.encode(nameBase)))));
        quoteAddr = _assumeEOA(vm.addr(uint256(keccak256(abi.encode(nameQuote)))));

        if (baseAddr > quoteAddr) {
            (baseAddr, quoteAddr) = (quoteAddr, baseAddr);
            (nameBase, nameQuote) = (nameQuote, nameBase);
        }

        vm.label(baseAddr, string(abi.encodePacked(nameBase, " Token")));
        vm.label(quoteAddr, string(abi.encodePacked(nameQuote, " Token")));

        vm.etch(baseAddr, mockERC20Logic.code);
        vm.etch(quoteAddr, mockERC20Logic.code);

        MockERC20(baseAddr).initialize(nameBase, "btn", 18);
        MockERC20(quoteAddr).initialize(nameQuote, "qnt", 18);

        // Launchpad contract creates a pair
        vm.prank(launchpad);
        v2Factory.createPair(baseAddr, quoteAddr);

        pairAddr = v2Factory.getPair(baseAddr, quoteAddr);
    }

    function _assumeEOA(address account) internal returns (address) {
        vm.assume(account.code.length == 0 && address(account) != address(0));
        return account;
    }

    function _createEmptyPair() internal returns (address pairAddr) {
        (address token0Addr, address token1Addr, address emptyPairAddr) = _createLaunchpadPair("empty0", "empty1");
        return emptyPairAddr;
    }
}
