// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TestPlus} from "lib/solady/test/utils/TestPlus.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {CLOBTestBase, MatchQuantities} from "test/clob/utils/CLOBTestBase.sol";
import {ICLOB} from "contracts/clob/ICLOB.sol";
import {Side} from "contracts/clob/types/Order.sol";
import {CLOB} from "contracts/clob/CLOB.sol";
import {MarketSettings, MarketConfig, Book, BookLib} from "contracts/clob/types/Book.sol";
import "forge-std/console.sol";

contract CLOBPostFillOrderTest is CLOBTestBase, TestPlus {
    using FixedPointMathLib for uint256;

    struct State {
        uint256 baseOpenInterest;
        uint256 quoteOpenInterest;
        uint256 lotSize;
        uint256 price;
        uint256 makerAmount;
        Side side;
    }

    State state;

    function testPostFillOrder_FOK_Success_Buy_AmountOut_Account(uint128 amountInBase, uint256 price) public {
        price = bound(price, TICK_SIZE, 100_000 ether);
        price -= price % TICK_SIZE;
        vm.assume(amountInBase >= MIN_LIMIT_ORDER_AMOUNT_IN_BASE);
        testPostFillOrder_FOK_Success_Buy_AmountOut_Helper(price, amountInBase);
    }

    function testPostFillOrder_FOK_Success_Buy_AmountIn_Account(uint128 amountInQuote, uint256 price) public {
        price = bound(price, TICK_SIZE, 100_000 ether);
        price -= price % TICK_SIZE;
        vm.assume(baseTokenAmount(price, amountInQuote) >= MIN_LIMIT_ORDER_AMOUNT_IN_BASE);
        testPostFillOrder_FOK_Success_Buy_AmountIn_Helper(price, amountInQuote);
    }

    function testPostFillOrder_FOK_Success_Sell_AmountIn_Account(uint128 amountInBase, uint256 price) public {
        price = bound(price, TICK_SIZE, 100_000 ether);
        price -= price % TICK_SIZE;
        vm.assume(amountInBase >= MIN_LIMIT_ORDER_AMOUNT_IN_BASE);
        testPostFillOrder_FOK_Success_Sell_AmountIn_Helper(amountInBase, price);
    }

    function testPostFillOrder_FOK_Success_Sell_AmountOut_Account(uint128 amountInQuote, uint256 price) public {
        price = bound(price, TICK_SIZE, 100_000 ether);
        price -= price % TICK_SIZE;
        vm.assume(baseTokenAmount(price, amountInQuote) >= MIN_LIMIT_ORDER_AMOUNT_IN_BASE);
        testPostFillOrder_FOK_Success_Sell_AmountOut_Helper(amountInQuote, price);
    }

    /// For benchmarking large limits
    function testPostFillOrder_FOK_LargeLimit_Success_Buy() public {
        address taker = users[0];
        address maker = users[1];
        uint256 makerAmount = 1 ether;
        uint256 price = 1 ether / 100;
        uint256 takerAmount;

        for (uint256 i = 0; i < 50; i++) {
            setupOrder(Side.SELL, maker, 1 ether, price);
            takerAmount += quoteTokenAmount(price, makerAmount);
        }

        setupTokens(Side.BUY, taker, takerAmount, price, false);

        ICLOB.PlaceOrderArgs memory fillArgs = ICLOB.PlaceOrderArgs({
            side: Side.BUY,
            clientOrderId: 0,
            tif: ICLOB.TiF.IOC,
            expiryTime: 0,
            limitPrice: price,
            amount: takerAmount,
            baseDenominated: false
        });

        vm.prank(taker);
        clob.placeOrder(taker, fillArgs);
    }

    /// For benchmarking large limits
    function testPostFillOrder_IOC_LargeLimit_Success_Sell() public {
        address taker = users[0];
        address maker = users[1];
        uint256 makerAmount = 1 ether;
        uint256 price = 1 ether / 100;
        uint256 takerAmount;

        for (uint256 i = 0; i < 50; i++) {
            setupOrder(Side.BUY, maker, 1 ether, price);
            takerAmount += baseTokenAmount(price, makerAmount);
        }

        setupTokens(Side.SELL, taker, takerAmount, price, true);

        ICLOB.PlaceOrderArgs memory fillArgs = ICLOB.PlaceOrderArgs({
            side: Side.SELL,
            clientOrderId: 0,
            tif: ICLOB.TiF.IOC,
            expiryTime: 0,
            limitPrice: price,
            amount: takerAmount,
            baseDenominated: true
        });

        vm.prank(taker);
        clob.placeOrder(taker, fillArgs);
    }

    function testPostFillOrder_FOK_Failure_Sell() public {
        address taker = users[0];
        address maker = users[1];
        uint256 amountInQuoteLimit = 1 ether;

        MarketSettings memory s = clob.getMarketSettings();
        uint256 price = s.tickSize;
        // The limit wont have enough size to satisfy the fill
        uint256 amountInBaseFill = baseTokenAmount(price, amountInQuoteLimit) + 1;

        uint256 amountInBaseLimit = baseTokenAmount(price, amountInQuoteLimit);

        setupOrder(Side.BUY, maker, amountInBaseLimit, price);
        setupTokens(Side.SELL, taker, amountInBaseFill, price, false);

        ICLOB.PlaceOrderArgs memory fillArgs = ICLOB.PlaceOrderArgs({
            side: Side.SELL,
            clientOrderId: 0,
            tif: ICLOB.TiF.FOK,
            expiryTime: 0,
            limitPrice: price,
            amount: amountInBaseFill,
            baseDenominated: true
        });

        vm.expectRevert(abi.encodeWithSelector(CLOB.FOKOrderNotFilled.selector));
        vm.prank(taker);
        clob.placeOrder(taker, fillArgs);
    }

    function testPostFillOrder_FOK_Failure_Buy() public {
        address taker = users[0];
        address maker = users[1];
        uint256 amountInBaseLimit = 1 ether;

        MarketSettings memory s = clob.getMarketSettings();
        uint256 price = s.tickSize;

        // The limit wont have enough size to satisfy the fill
        uint256 amountInQuoteFill = baseTokenAmount(price, amountInBaseLimit) + 1;

        setupOrder(Side.SELL, maker, amountInBaseLimit, price);
        setupTokens(Side.BUY, taker, amountInQuoteFill, price, false);

        ICLOB.PlaceOrderArgs memory fillArgs = ICLOB.PlaceOrderArgs({
            side: Side.BUY,
            clientOrderId: 0,
            tif: ICLOB.TiF.FOK,
            expiryTime: 0,
            limitPrice: price,
            amount: amountInQuoteFill,
            baseDenominated: false
        });

        vm.expectRevert(abi.encodeWithSelector(CLOB.FOKOrderNotFilled.selector));
        vm.prank(taker);
        clob.placeOrder(taker, fillArgs);
    }

    function testPostFillOrder_EatExpiredAskOrders() public {
        address maker0 = users[0];
        address maker1 = users[1];
        address maker2 = users[2];
        address maker3 = users[3];
        address taker = users[4];

        MarketSettings memory s = clob.getMarketSettings();
        uint256 tickSize = s.tickSize;
        uint256 amountInBase = 1 ether;

        // first 2 makers are expired
        setupOrderExpiry = NOW + 1; // 2
        setupOrder(Side.SELL, maker0, amountInBase, tickSize);

        setupOrderExpiry += 1; // 3
        setupOrder(Side.SELL, maker1, amountInBase, tickSize * 2);

        setupOrderExpiry += 1; // 4
        // Set up maker2 with 1 ether (matches taker's amount)
        setupOrder(Side.SELL, maker2, amountInBase, tickSize * 3); // 1 ether at tickSize * 3

        setupOrderExpiry += 1; // 5
        // Set up maker3 with 2 ether at highest price (won't get filled)
        setupOrder(Side.SELL, maker3, amountInBase * 2, tickSize * 4); // 2 ether at tickSize * 4

        vm.warp(uint256(NOW + 3)); // Make first 2 makers expired

        // Taker buys 1 ether - this will traverse expired orders and fill maker2's order
        setupTokens(Side.BUY, taker, amountInBase, tickSize * 4, true);
        ICLOB.PlaceOrderArgs memory fillArgs = ICLOB.PlaceOrderArgs({
            side: Side.BUY,
            clientOrderId: 0,
            tif: ICLOB.TiF.IOC,
            expiryTime: 0,
            limitPrice: tickSize * 4,
            amount: amountInBase,
            baseDenominated: true
        });

        vm.prank(taker);
        clob.placeOrder(taker, fillArgs);

        // First 2 orders (ids 1 and 2) should both be removed after the post fill order call (expired)
        assertEq(clob.getOrder(1).owner, address(0));
        assertEq(clob.getOrder(2).owner, address(0));

        // Order 3 (maker2) should be fully filled and removed
        assertEq(clob.getOrder(3).owner, address(0));

        // Order 4 (maker3) should not have been filled
        assertEq(clob.getOrder(4).owner, maker3);
        assertEq(clob.getOrder(4).amount, amountInBase * 2); // 2 ether remaining

        // Base open interest should equal maker3's order amount
        (, uint256 baseOI) = clob.getOpenInterest();
        assertEq(baseOI, amountInBase * 2);
    }

    function testPostFillOrder_EatExpiredBidOrders() public {
        address maker0 = users[0];
        address maker1 = users[1];
        address maker2 = users[2];
        address maker3 = users[3];
        address taker = users[4];

        MarketSettings memory s = clob.getMarketSettings();
        uint256 tickSize = s.tickSize;
        uint256 amountInBase = 1 ether;

        // first 2 makers are expired
        setupOrderExpiry = NOW + 1; // 2
        setupOrder(Side.BUY, maker0, amountInBase, tickSize * 4);

        setupOrderExpiry += 1; // 3
        setupOrder(Side.BUY, maker1, amountInBase, tickSize * 3);

        setupOrderExpiry += 1; // 4
        // Set up maker2 with 1 ether (matches taker's amount)
        setupOrder(Side.BUY, maker2, amountInBase, tickSize * 2); // 1 ether at tickSize * 2

        setupOrderExpiry += 1; // 5
        // Set up maker3 with 2 ether at lowest price (won't get filled)
        setupOrder(Side.BUY, maker3, amountInBase * 2, tickSize); // 2 ether at tickSize

        vm.warp(uint256(NOW + 3)); // Make first 2 makers expired

        // Taker sells 1 ether - this will traverse expired orders and fill maker2's order
        setupTokens(Side.SELL, taker, amountInBase, tickSize, true);
        ICLOB.PlaceOrderArgs memory fillArgs = ICLOB.PlaceOrderArgs({
            side: Side.SELL,
            clientOrderId: 0,
            tif: ICLOB.TiF.IOC,
            expiryTime: 0,
            limitPrice: tickSize,
            amount: amountInBase,
            baseDenominated: true
        });

        vm.prank(taker);
        clob.placeOrder(taker, fillArgs);

        // First 2 orders (ids 1 and 2) should both be removed after the post fill order call (expired)
        assertEq(clob.getOrder(1).owner, address(0));
        assertEq(clob.getOrder(2).owner, address(0));

        // Order 3 (maker2) should be fully filled and removed
        assertEq(clob.getOrder(3).owner, address(0));

        // Order 4 (maker3) should not have been filled
        assertEq(clob.getOrder(4).owner, maker3);
        assertEq(clob.getOrder(4).amount, amountInBase * 2); // 2 ether remaining

        // Quote open interest should equal maker3's order amount * price
        (uint256 quoteOI,) = clob.getOpenInterest();
        uint256 expectedQuoteOI = clob.getQuoteTokenAmount(tickSize, amountInBase * 2); // 2 ether * tickSize
        assertEq(quoteOI, expectedQuoteOI);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @dev Test that a FILL_OR_KILL fill order succeeds
    function testPostFillOrder_FOK_Success_Buy_AmountOut_Helper(uint256 price, uint256 amountInBase) private {
        // Simulate the order book reaching max number of orders
        address taker = users[0];
        address maker = users[1];
        uint256 makerAmount = amountInBase - amountInBase % uint128(clob.getLotSizeInBase()) + clob.getLotSizeInBase();

        makerAmount -= makerAmount % clob.getLotSizeInBase();
        setupOrder(Side.SELL, maker, makerAmount, price);

        setupTokens(Side.BUY, taker, amountInBase, price, true);

        // Place FOK order (Fill Or Kill) - must fill completely or revert
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: Side.BUY,
            clientOrderId: 0,
            tif: ICLOB.TiF.FOK, // Fill Or Kill
            expiryTime: 0,
            limitPrice: price,
            amount: amountInBase,
            baseDenominated: true
        });

        MatchQuantities memory matchQuantities =
            computeMatchQuantities(Side.BUY, amountInBase, makerAmount, price, taker, maker, true);

        // Expect emit OrderProcessed event (replaces FillOrderSubmitted/Processed)
        vm.expectEmit(true, true, true, true);
        emit CLOB.OrderProcessed(
            clob.getEventNonce() + 1,
            taker,
            2,
            args.tif,
            args.limitPrice,
            0, // basePosted (FOK doesn't post)
            -int256(matchQuantities.matchedQuote),
            int256(matchQuantities.matchedBase),
            matchQuantities.takerFeeInBase
        );

        // Place order
        uint256 orderId = clob.getNextOrderId();
        vm.prank(taker);
        ICLOB.PlaceOrderResult memory result = clob.placeOrder(taker, args);

        // Verify results
        assertEq(result.orderId, orderId, "Order ID should increment");
        assertEq(result.account, taker, "Account should match");
        assertEq(result.basePosted, 0, "FOK should not post any amount");
        assertEq(result.wasMarketOrder, false, "Should not be market order");
        assertEq(
            result.quoteTokenAmountTraded, -int256(matchQuantities.matchedQuote), "Quote token change should match"
        );
        assertEq(result.baseTokenAmountTraded, int256(matchQuantities.matchedBase), "Base token change should match");
        assertEq(result.takerFee, matchQuantities.takerFeeInBase, "Taker fee should match");

        // Taker should have successfully purchased base tokens
        assertTokenBalance(taker, Side.BUY, matchQuantities.matchedBase - matchQuantities.takerFeeInBase);
        assertTokenBalance(taker, Side.SELL, quoteTokenAmount(price, amountInBase) - matchQuantities.matchedQuote);
        // Maker should have successfully sold quote tokens
        assertTokenBalance(maker, Side.BUY, 0);
        assertTokenBalance(maker, Side.SELL, matchQuantities.matchedQuote - matchQuantities.makerFeeInQuote);
    }

    function testPostFillOrder_FOK_Success_Buy_AmountIn_Helper(uint256 price, uint256 amountInQuote) private {
        // Simulate the order book reaching max number of orders
        address taker = users[0];
        address maker = users[1];

        // note: we make the maker order a bit larger to account for rounding error and ensure FOK succeeds
        uint256 amountInBase = baseTokenAmount(price, amountInQuote) + 1;

        // Round maker amount to lot size multiple
        uint256 lotSize = clob.getLotSizeInBase();
        amountInBase = ((amountInBase + lotSize - 1) / lotSize) * lotSize;

        setupOrder(Side.SELL, maker, amountInBase, price);
        setupTokens(Side.BUY, taker, amountInQuote, price, false);

        // Place FOK order (Fill Or Kill) - quote denominated
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: Side.BUY,
            clientOrderId: 0,
            tif: ICLOB.TiF.FOK, // Fill Or Kill
            expiryTime: 0,
            limitPrice: price,
            amount: amountInQuote,
            baseDenominated: false // Quote denominated
        });

        MatchQuantities memory matchQuantities =
            computeMatchQuantities(Side.BUY, amountInQuote, amountInBase, price, taker, maker, false);

        // Expect emit OrderProcessed event (replaces FillOrderSubmitted/Processed)
        vm.expectEmit(true, true, true, true);
        emit CLOB.OrderProcessed(
            clob.getEventNonce() + 1,
            taker,
            2,
            args.tif,
            args.limitPrice,
            0, // basePosted (FOK doesn't post)
            -int256(matchQuantities.matchedQuote),
            int256(matchQuantities.matchedBase),
            matchQuantities.takerFeeInBase
        );

        // Place order
        uint256 orderId = clob.getNextOrderId();
        vm.prank(taker);
        ICLOB.PlaceOrderResult memory result = clob.placeOrder(taker, args);

        // Verify results
        assertEq(result.orderId, orderId, "Order ID should increment");
        assertEq(result.account, taker, "Account should match");
        assertEq(result.basePosted, 0, "FOK should not post any amount");
        assertEq(result.wasMarketOrder, false, "Should not be market order");
        assertEq(
            result.quoteTokenAmountTraded, -int256(matchQuantities.matchedQuote), "Quote token change should match"
        );
        assertEq(result.baseTokenAmountTraded, int256(matchQuantities.matchedBase), "Base token change should match");
        assertEq(result.takerFee, matchQuantities.takerFeeInBase, "Taker fee should match");

        // Taker should have successfully purchased base tokens
        assertTokenBalance(taker, Side.BUY, matchQuantities.matchedBase - matchQuantities.takerFeeInBase);
        assertTokenBalance(taker, Side.SELL, amountInQuote - matchQuantities.matchedQuote);
        // Maker should have successfully sold quote tokens
        assertTokenBalance(maker, Side.BUY, 0);
        assertTokenBalance(maker, Side.SELL, matchQuantities.matchedQuote - matchQuantities.makerFeeInQuote);
    }

    /// @notice Test that a FILL_OR_KILL fill order succeeds
    function testPostFillOrder_FOK_Success_Sell_AmountIn_Helper(uint128 amountInBase, uint256 price) private {
        // Simulate the order book reaching max number of orders
        address taker = users[0];
        address maker = users[1];

        // Ensure maker has enough liquidity to buy all of taker's amountInBase
        // Round up the taker amount to next lot size multiple to ensure maker has enough
        uint256 lotSize = clob.getLotSizeInBase();
        uint256 makerAmount = ((amountInBase + lotSize - 1) / lotSize) * lotSize;

        // Calculate what the taker should actually be able to sell (lot size multiples only)
        uint256 actualSellAmount = (amountInBase / lotSize) * lotSize;
        uint256 expectedRemainder = amountInBase - actualSellAmount;

        setupOrder(Side.BUY, maker, makerAmount, price);
        setupTokens(Side.SELL, taker, amountInBase, price, true);

        // Place FOK order (Fill Or Kill) - base denominated sell
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: Side.SELL,
            clientOrderId: 0,
            tif: ICLOB.TiF.FOK, // Fill Or Kill
            expiryTime: 0,
            limitPrice: price,
            amount: amountInBase,
            baseDenominated: true
        });

        MatchQuantities memory matchQuantities =
            computeMatchQuantities(Side.SELL, amountInBase, makerAmount, price, taker, maker, true);

        // Expect emit OrderProcessed event (replaces FillOrderSubmitted/Processed)
        vm.expectEmit(true, true, true, true);
        emit CLOB.OrderProcessed(
            clob.getEventNonce() + 1,
            taker,
            2,
            args.tif,
            args.limitPrice,
            0, // basePosted (FOK doesn't post)
            int256(matchQuantities.matchedQuote),
            -int256(matchQuantities.matchedBase),
            matchQuantities.takerFeeInQuote
        );

        // Place order
        uint256 orderId = clob.getNextOrderId();
        vm.prank(taker);
        ICLOB.PlaceOrderResult memory result = clob.placeOrder(taker, args);

        // Verify results
        assertEq(result.orderId, orderId, "Order ID should increment");
        assertEq(result.account, taker, "Account should match");
        assertEq(result.basePosted, 0, "FOK should not post any amount");
        assertEq(result.wasMarketOrder, false, "Should not be market order");
        assertEq(result.quoteTokenAmountTraded, int256(matchQuantities.matchedQuote), "Quote token change should match");
        assertEq(result.baseTokenAmountTraded, -int256(matchQuantities.matchedBase), "Base token change should match");
        assertEq(result.takerFee, matchQuantities.takerFeeInQuote, "Taker fee should match");

        // Taker should have successfully purchased quote tokens
        // The taker should have the remainder of base tokens that couldn't be sold due to lot size truncation
        assertTokenBalance(taker, Side.BUY, expectedRemainder);
        assertTokenBalance(taker, Side.SELL, matchQuantities.matchedQuote - matchQuantities.takerFeeInQuote);
        // Maker should have successfully sold quote tokens
        assertTokenBalance(maker, Side.BUY, matchQuantities.matchedBase - matchQuantities.makerFeeInBase);
        assertTokenBalance(maker, Side.SELL, 0);
    }

    function testPostFillOrder_FOK_Success_Sell_AmountOut_Helper(uint128 amountInQuote, uint256 price) private {
        // Simulate the order book reaching max number of orders
        address taker = users[0];
        address maker = users[1];

        // note: we make the maker order a bit larger to account for rounding error and ensure FOK succeeds
        uint256 amountInBase = baseTokenAmount(price, amountInQuote) + 1;

        // Round maker amount to lot size multiple
        uint256 lotSize = clob.getLotSizeInBase();
        amountInBase = ((amountInBase + lotSize - 1) / lotSize) * lotSize;

        // The taker will deposit baseTokenAmount(price, amountInQuote) base tokens
        uint256 takerBaseDeposit = baseTokenAmount(price, amountInQuote);
        uint256 actualSellAmount = (takerBaseDeposit / lotSize) * lotSize;
        uint256 expectedRemainder = takerBaseDeposit - actualSellAmount;

        setupOrder(Side.BUY, maker, amountInBase, price);
        setupTokens(Side.SELL, taker, amountInQuote, price, false);

        // Place FOK order (Fill Or Kill) - quote denominated sell
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: Side.SELL,
            clientOrderId: 0,
            tif: ICLOB.TiF.FOK, // Fill Or Kill
            expiryTime: 0,
            limitPrice: price,
            amount: amountInQuote,
            baseDenominated: false // Quote denominated
        });

        MatchQuantities memory matchQuantities =
            computeMatchQuantities(Side.SELL, amountInQuote, amountInBase, price, taker, maker, false);

        // Expect emit OrderProcessed event (replaces FillOrderSubmitted/Processed)
        vm.expectEmit(true, true, true, true);
        emit CLOB.OrderProcessed(
            clob.getEventNonce() + 1,
            taker,
            2,
            args.tif,
            args.limitPrice,
            0, // basePosted (FOK doesn't post)
            int256(matchQuantities.matchedQuote),
            -int256(matchQuantities.matchedBase),
            matchQuantities.takerFeeInQuote
        );

        // Place order
        uint256 orderId = clob.getNextOrderId();
        vm.prank(taker);
        ICLOB.PlaceOrderResult memory result = clob.placeOrder(taker, args);

        // Verify results
        assertEq(result.orderId, orderId, "Order ID should increment");
        assertEq(result.account, taker, "Account should match");
        assertEq(result.basePosted, 0, "FOK should not post any amount");
        assertEq(result.wasMarketOrder, false, "Should not be market order");
        assertEq(result.quoteTokenAmountTraded, int256(matchQuantities.matchedQuote), "Quote token change should match");
        assertEq(result.baseTokenAmountTraded, -int256(matchQuantities.matchedBase), "Base token change should match");
        assertEq(result.takerFee, matchQuantities.takerFeeInQuote, "Taker fee should match");

        // Taker should have successfully purchased quote tokens
        // The taker should have the remainder of base tokens that couldn't be sold due to lot size truncation
        assertTokenBalance(taker, Side.BUY, expectedRemainder);
        assertTokenBalance(taker, Side.SELL, matchQuantities.matchedQuote - matchQuantities.takerFeeInQuote);
        // Maker should have successfully sold quote tokens
        assertTokenBalance(maker, Side.BUY, matchQuantities.matchedBase - matchQuantities.makerFeeInBase);
        assertTokenBalance(maker, Side.SELL, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            LOT SIZE TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_LotSizeBounding(uint256) public {
        address taker = users[0];
        address maker = users[1];

        state.price = _hem(_random(), 1, 1e9) * TICK_SIZE;
        state.lotSize = _hem(_random(), 1, 1e18) * LOT_SIZE_IN_BASE;
        vm.assume(TICK_SIZE.fullMulDiv(state.lotSize, 1e18) > 0);

        state.makerAmount = _hem(_random(), state.lotSize, 10 * state.lotSize);
        state.side = _random() % 2 == 0 ? Side.BUY : Side.SELL;

        state.makerAmount -= state.makerAmount % state.lotSize;
        vm.assume(state.makerAmount > clob.getMarketSettings().minLimitOrderAmountInBase);

        setupOrder(state.side == Side.BUY ? Side.SELL : Side.BUY, maker, state.makerAmount, state.price);
        setupTokens(state.side, taker, state.makerAmount, state.price, true);

        if (state.lotSize > clob.getMarketSettings().minLimitOrderAmountInBase) {
            vm.prank(address(clobManager));
            clob.setMinLimitOrderAmountInBase(state.lotSize + 1);
        }

        vm.prank(address(clobManager));
        clob.setLotSizeInBase(state.lotSize);

        (state.baseOpenInterest, state.quoteOpenInterest) = clob.getOpenInterest();

        // Place IOC order (Immediate Or Cancel) - fills what it can, cancels the rest
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: state.side,
            clientOrderId: 0,
            tif: ICLOB.TiF.IOC, // Immediate Or Cancel
            expiryTime: 0,
            limitPrice: state.price,
            amount: state.makerAmount,
            baseDenominated: true
        });

        vm.prank(taker);
        ICLOB.PlaceOrderResult memory result = clob.placeOrder(taker, args);

        uint256 remainder = state.makerAmount % state.lotSize;
        int256 baseTokenAmountTraded =
            state.side == Side.BUY ? result.baseTokenAmountTraded : -result.baseTokenAmountTraded;

        assertEq(clob.getOrder(1).amount, 0, "Maker order should be cleared");
        assertEq(result.account, taker, "Account should match");
        assertEq(result.basePosted, 0, "IOC should not post any amount");
        assertEq(result.wasMarketOrder, false, "Should not be market order");

        (uint256 openInterestBase, uint256 openInterestQuote) = clob.getOpenInterest();
        assertEq(openInterestBase, 0, "Base open interest should 0");
        assertEq(openInterestQuote, 0, "Quote open interest should be 0");
        assertEq(
            baseTokenAmountTraded,
            int256(state.makerAmount - remainder),
            "Fill amount should be maker amount - remainder"
        );
    }

    function testPostFillOrder_LotSizeTruncation_Fill_AmountBase(uint256) public {
        address taker = users[0];
        address maker = users[1];

        Side takerSide = _random() % 2 == 0 ? Side.BUY : Side.SELL;
        Side makerSide = takerSide == Side.BUY ? Side.SELL : Side.BUY;

        uint256 makerAmount = 0.751 ether; // Not a multiple of lot size initially
        uint256 takerAmount = 0.681 ether; // Not a multiple of lot size

        uint256 price = _hem(_random(), 1, 1000) * TICK_SIZE;
        uint256 lotSize = _hem(_random(), LOT_SIZE_IN_BASE, takerAmount);

        lotSize -= lotSize % LOT_SIZE_IN_BASE;

        // Round maker amount to lot size multiple
        makerAmount = ((makerAmount + lotSize - 1) / lotSize) * lotSize;

        setupOrder(makerSide, maker, makerAmount, price);

        vm.prank(address(clobManager));
        clob.setMinLimitOrderAmountInBase(lotSize);

        vm.prank(address(clobManager));
        clob.setLotSizeInBase(lotSize); // Set specific lot size for fill

        setupTokens(takerSide, taker, takerAmount, price, true);

        // Place IOC order (Immediate Or Cancel) - base denominated
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: takerSide,
            clientOrderId: 0,
            tif: ICLOB.TiF.IOC, // Immediate Or Cancel
            expiryTime: 0,
            limitPrice: price,
            amount: takerAmount,
            baseDenominated: true
        });

        uint256 expectedFillAmount = (takerAmount / lotSize) * lotSize;

        vm.prank(taker);
        ICLOB.PlaceOrderResult memory result = clob.placeOrder(taker, args);

        // Verify the fill was truncated to lot size multiple
        int256 baseTokenAmountTraded =
            takerSide == Side.BUY ? result.baseTokenAmountTraded : -result.baseTokenAmountTraded;
        assertEq(
            uint256(baseTokenAmountTraded), expectedFillAmount, "Base amount should be truncated to lot size multiple"
        );
        assertGt(uint256(baseTokenAmountTraded), 0, "Should have traded some amount");
        assertLt(uint256(baseTokenAmountTraded), takerAmount, "Should have truncated the original amount");

        // Verify new result fields
        assertEq(result.account, taker, "Account should match");
        assertEq(result.basePosted, 0, "IOC should not post any amount");
        assertEq(result.wasMarketOrder, false, "Should not be market order");

        // Verify the maker order still has remaining size, truncated back to the new lot size
        uint256 remainingMakerAmount = makerAmount - expectedFillAmount;
        remainingMakerAmount -= remainingMakerAmount % lotSize;
        assertEq(clob.getOrder(1).amount, remainingMakerAmount, "Maker amount mismatch");
    }

    function testPostFillOrder_LotSizeTruncation_Fill_AmountQuote(uint256) public {
        address taker = users[0];
        address maker = users[1];

        Side takerSide = _random() % 2 == 0 ? Side.BUY : Side.SELL;
        Side makerSide = takerSide == Side.BUY ? Side.SELL : Side.BUY;

        uint256 price = _hem(_random(), 1, 1000) * TICK_SIZE;
        uint256 makerAmount = 2 ether;
        uint256 takerQuoteAmount = 0.000556 ether;

        uint256 baseFromQuote = baseTokenAmount(price, takerQuoteAmount);
        uint256 lotSize = (LOT_SIZE_IN_BASE < baseFromQuote)
            ? _hem(_random(), LOT_SIZE_IN_BASE, baseFromQuote - 1)
            : _hem(_random(), baseFromQuote - 1, LOT_SIZE_IN_BASE);
        lotSize -= lotSize % LOT_SIZE_IN_BASE;

        vm.assume(lotSize > 0);

        // Round maker amount to lot size multiple
        makerAmount = ((makerAmount + lotSize - 1) / lotSize) * lotSize;

        vm.assume((makerAmount < baseFromQuote ? makerAmount : baseFromQuote) >= lotSize);

        setupOrder(makerSide, maker, makerAmount, price);

        vm.prank(address(clobManager));
        clob.setMinLimitOrderAmountInBase(lotSize);

        vm.prank(address(clobManager));
        clob.setLotSizeInBase(lotSize); // Set specific lot size for fill

        setupTokens(takerSide, taker, takerQuoteAmount, price, false);

        // Place IOC order (Immediate Or Cancel) - quote denominated
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: takerSide,
            clientOrderId: 0,
            tif: ICLOB.TiF.IOC, // Immediate Or Cancel
            expiryTime: 0,
            limitPrice: price,
            amount: takerQuoteAmount,
            baseDenominated: false // Quote denominated
        });

        uint256 availableBase = makerAmount < baseFromQuote ? makerAmount : baseFromQuote;
        uint256 expectedFillAmount = (availableBase / lotSize) * lotSize;

        vm.prank(taker);
        ICLOB.PlaceOrderResult memory result = clob.placeOrder(taker, args);

        // Verify the fill was truncated to lot size multiple
        int256 baseTokenAmountTraded =
            takerSide == Side.BUY ? result.baseTokenAmountTraded : -result.baseTokenAmountTraded;
        assertEq(
            uint256(baseTokenAmountTraded), expectedFillAmount, "Base amount should be truncated to lot size multiple"
        );
        assertLe(uint256(baseTokenAmountTraded), baseFromQuote, "Should have truncated from the calculated base amount");

        // Verify new result fields
        assertEq(result.account, taker, "Account should match");
        assertEq(result.basePosted, 0, "IOC should not post any amount");
        assertEq(result.wasMarketOrder, false, "Should not be market order");
    }

    function testPostFillOrder_LotSizeTruncation_ZeroAmount() public {
        address taker = users[0];
        address maker = users[1];
        uint256 lotSize = 1 ether;
        uint256 price = TICK_SIZE;
        uint256 makerAmount = 2 ether;
        uint256 takerAmount = 0.5 ether; // Less than lot size, should result in zero fill

        setupOrder(Side.SELL, maker, makerAmount, price);

        vm.prank(address(clobManager));
        clob.setMinLimitOrderAmountInBase(lotSize);

        vm.prank(address(clobManager));
        clob.setLotSizeInBase(lotSize); // Set specific lot size for fill

        setupTokens(Side.BUY, taker, takerAmount, price, true);

        // Place IOC order (Immediate Or Cancel) - should revert when zero amount after lot size truncation
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: Side.BUY,
            clientOrderId: 0,
            tif: ICLOB.TiF.IOC, // Immediate Or Cancel
            expiryTime: 0,
            limitPrice: price,
            amount: takerAmount,
            baseDenominated: true
        });

        // Should revert with ZeroOrder when lot size truncation results in zero amount (no effective trade)
        vm.expectRevert(abi.encodeWithSelector(CLOB.ZeroOrder.selector));
        vm.prank(taker);
        clob.placeOrder(taker, args);

        // Maker order should remain unchanged since no trade occurred
        assertEq(clob.getOrder(1).amount, makerAmount, "Maker order should be unchanged");
    }

    function testPostFillOrder_LotSizeTruncation_MultipleOrders() public {
        address taker = users[0];
        address maker1 = users[1];
        address maker2 = users[2];
        uint256 lotSize = 0.3 ether;
        uint256 price = TICK_SIZE;
        uint256 maker1Amount = 0.3 ether; // Exactly 1 lot
        uint256 maker2Amount = 0.6 ether; // Exactly 2 lots
        uint256 takerAmount = 1.1 ether; // Should fill 0.9 ether total (3 lots)

        setupOrder(Side.SELL, maker1, maker1Amount, price);
        setupOrder(Side.SELL, maker2, maker2Amount, price);

        vm.prank(address(clobManager));
        clob.setMinLimitOrderAmountInBase(lotSize);

        vm.prank(address(clobManager));
        clob.setLotSizeInBase(lotSize); // Set specific lot size for fill

        setupTokens(Side.BUY, taker, takerAmount, price, true);

        // Place IOC order (Immediate Or Cancel) - should fill across multiple orders
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: Side.BUY,
            clientOrderId: 0,
            tif: ICLOB.TiF.IOC, // Immediate Or Cancel
            expiryTime: 0,
            limitPrice: price,
            amount: takerAmount,
            baseDenominated: true
        });

        vm.prank(taker);
        ICLOB.PlaceOrderResult memory result = clob.placeOrder(taker, args);

        // Should have filled 0.9 ether total (3 lots) across both makers
        uint256 expectedFillAmount = lotSize * 3; // 0.9 ether (3 lots)
        assertEq(uint256(result.baseTokenAmountTraded), expectedFillAmount, "Should fill exactly 3 lots");
        assertEq(result.account, taker, "Account should match");
        assertEq(result.basePosted, 0, "IOC should not post any amount");
        assertEq(result.wasMarketOrder, false, "Should not be market order");

        // Both maker orders should be cleared entirely
        assertEq(clob.getOrder(1).amount, 0, "First maker order should be cleared");
        assertEq(clob.getOrder(2).amount, 0, "Second maker order should be cleared");
    }

    function testPostFillOrder_ZeroOrder_EmptyBook(uint256) public {
        address maker = users[0];
        address taker = users[1];
        uint256 amount = MIN_LIMIT_ORDER_AMOUNT_IN_BASE;
        uint256 price = TICK_SIZE;
        Side makerSide = _random() % 2 == 0 ? Side.BUY : Side.SELL;
        Side takerSide = makerSide == Side.BUY ? Side.SELL : Side.BUY;

        setupTokens(takerSide, maker, amount, price, true);

        // Place IOC order (Immediate Or Cancel) - should revert when no orders to match
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: takerSide,
            clientOrderId: 0,
            tif: ICLOB.TiF.IOC, // Immediate Or Cancel
            expiryTime: 0,
            limitPrice: price,
            amount: amount,
            baseDenominated: true
        });

        // this should trigger ZeroOrder due to no trades present in the orderbook at all (empty book = noop)
        vm.expectRevert(CLOB.ZeroOrder.selector);
        vm.prank(taker);
        clob.placeOrder(taker, args);
    }

    function testPostFillOrder_ZeroOrder_NoMatchingOrders(uint256) public {
        address taker = users[0];
        address maker = users[1];
        uint256 amount = MIN_LIMIT_ORDER_AMOUNT_IN_BASE;
        Side makerSide = _random() % 2 == 0 ? Side.BUY : Side.SELL;
        Side takerSide = makerSide == Side.BUY ? Side.SELL : Side.BUY;
        uint256 makerPrice = makerSide == Side.BUY ? TICK_SIZE : TICK_SIZE * 2;
        uint256 takerPrice = takerSide == Side.BUY ? TICK_SIZE : TICK_SIZE * 2;

        setupOrder(makerSide, maker, amount, makerPrice);
        setupTokens(takerSide, taker, amount, takerPrice, true);

        // Place IOC order (Immediate Or Cancel) - should revert when no matching orders at price level
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: takerSide,
            clientOrderId: 0,
            tif: ICLOB.TiF.IOC, // Immediate Or Cancel
            expiryTime: 0,
            limitPrice: takerPrice,
            amount: amount,
            baseDenominated: true
        });

        // this should trigger ZeroOrder due to no trades found at that price level (no matching orders)
        vm.expectRevert(CLOB.ZeroOrder.selector);
        vm.prank(taker);
        clob.placeOrder(taker, args);
    }

    function testPostFillOrder_ZeroOrder_PriceZero(uint256) public {
        address taker = users[0];
        address maker = users[1];
        uint256 amount = MIN_LIMIT_ORDER_AMOUNT_IN_BASE;
        uint256 price = TICK_SIZE;
        uint256 tinyAmount = 1;
        Side makerSide = _random() % 2 == 0 ? Side.BUY : Side.SELL;
        Side takerSide = makerSide == Side.BUY ? Side.SELL : Side.BUY;

        setupOrder(makerSide, maker, amount, price);
        setupTokens(takerSide, taker, tinyAmount, price, true);

        // Place IOC order (Immediate Or Cancel) with tiny amount - should trigger ZeroCostTrade due to rounding
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: takerSide,
            clientOrderId: 0,
            tif: ICLOB.TiF.IOC, // Immediate Or Cancel
            expiryTime: 0,
            limitPrice: price,
            amount: tinyAmount,
            baseDenominated: true
        });

        // this should trigger ZeroOrder due to tiny amount resulting in zero values after processing
        vm.expectRevert(CLOB.ZeroOrder.selector);
        vm.prank(taker);
        clob.placeOrder(taker, args);
    }

    function testPostFillOrder_Orderbook_Swipe(uint256) public {
        address taker = users[0];
        address maker = users[1];
        uint256 amount = 1 ether;
        uint256 price = 1 ether;
        Side makerSide = _random() % 2 == 0 ? Side.BUY : Side.SELL;
        Side takerSide = makerSide == Side.BUY ? Side.SELL : Side.BUY;

        for (uint256 i = 0; i < 10; i++) {
            price = makerSide == Side.BUY ? price + i * TICK_SIZE : price - i * TICK_SIZE;
            setupOrder(makerSide, maker, amount, price);
        }

        setupTokens(takerSide, taker, amount * 11, price, true);

        // Place large IOC order to sweep through multiple orders in the book
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: takerSide,
            clientOrderId: 0,
            tif: ICLOB.TiF.IOC, // Immediate Or Cancel
            expiryTime: 0,
            limitPrice: price,
            amount: amount * 11, // more than the orderbook has
            baseDenominated: true
        });

        vm.prank(taker);
        clob.placeOrder(taker, args);
    }

    /// For benchmarking multiple different maker addresses

    function testPostFillOrder_BenchmarkMultipleMakers() public {
        address taker = users[0];
        uint256 makerAmount = 1 ether;
        uint256 price = 1 ether / 100;
        uint256 numMakers = 50;
        uint256 takerAmount;

        for (uint256 i = 0; i < numMakers; i++) {
            // Create a new maker address for each order
            address maker = vm.addr(100 + i);
            // Set max limit whitelist for the new maker
            _setMaxLimitWhitelist(maker, true);
            // Setup order with the new maker
            setupOrder(Side.SELL, maker, makerAmount, price);
            takerAmount += quoteTokenAmount(price, makerAmount);
        }

        setupTokens(Side.BUY, taker, takerAmount, price, false);

        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: Side.BUY,
            clientOrderId: 0,
            tif: ICLOB.TiF.IOC, // Immediate Or Cancel
            expiryTime: 0,
            limitPrice: price,
            amount: takerAmount, // more than the orderbook has
            baseDenominated: true
        });

        vm.prank(taker);
        clob.placeOrder(taker, args);
    }

    /// @notice Test that dust from partial fills is properly handled with the break logic
    /// This test specifically addresses the scenario where matchedAmount == 0 due to lot size truncation
    function testPostFillOrder_LotSizeTruncation_DustHandling() public {
        address taker = users[0];
        address maker = users[1];

        // Setup a scenario where dust will be created
        uint256 lotSize = 1 ether;
        uint256 price = 1 ether; // 1 base = 1 quote
        uint256 makerAmount = 1 ether; // Exactly 1 lot (no dust needed with lot size enforcement)
        uint256 takerQuoteAmount = 2.5 ether; // Wants 2.5 base but should only get 1 lot

        // Setup maker order (selling base)
        setupOrder(Side.SELL, maker, makerAmount, price);

        vm.prank(address(clobManager));
        clob.setMinLimitOrderAmountInBase(lotSize + 1);

        // Set lot size that will cause truncation
        vm.prank(address(clobManager));
        clob.setLotSizeInBase(lotSize);

        // Setup taker tokens (quote denominated fill)
        setupTokens(Side.BUY, taker, takerQuoteAmount, price, false);

        // Create IOC order (quote denominated)
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: Side.BUY,
            clientOrderId: 0,
            tif: ICLOB.TiF.IOC, // Immediate Or Cancel
            expiryTime: 0,
            limitPrice: price,
            amount: takerQuoteAmount,
            baseDenominated: false // quote denominated
        });

        // Execute fill order
        vm.prank(taker);
        ICLOB.PlaceOrderResult memory result = clob.placeOrder(taker, args);

        // Verify only 1 lot was filled (no dust)
        assertEq(uint256(result.baseTokenAmountTraded), lotSize, "Should fill exactly 1 lot");
        assertEq(uint256(-result.quoteTokenAmountTraded), lotSize, "Should pay exactly 1 quote per base");

        // Verify maker order is matched for exactly 1 lot (dust gone)
        assertEq(clob.getOrder(1).amount, 0, "Maker order should be cleared");

        // Verify taker's remaining quote tokens are still in account manager
        uint256 takerQuoteRemaining = clobManager.accountManager().getAccountBalance(taker, address(quoteToken));
        assertEq(takerQuoteRemaining, takerQuoteAmount - lotSize, "Taker should have remaining quote tokens");

        // Verify maker received quote tokens for exactly 1 lot (not including dust)
        uint256 makerQuoteReceived = clobManager.accountManager().getAccountBalance(maker, address(quoteToken));
        assertGt(makerQuoteReceived, 0, "Maker should have received quote tokens");
        assertLe(makerQuoteReceived, lotSize, "Maker should not receive more than 1 lot worth of quote");
    }

    /// @notice Test scenario where baseDelta == 0 but matchedAmount != 0 (quote-denominated case)
    /// This tests the edge case in _matchIncomingOrder where matchedAmount = takerOrder.amount
    /// even when no actual trade occurs due to lot size truncation
    function testPostFillOrder_BaseDeltaZero_MatchedAmountNonZero() public {
        address taker = users[0];
        address maker = users[1];

        // Setup: lot size larger than maker's available amount
        uint256 lotSize = 2 ether;
        uint256 price = 1 ether;
        uint256 makerAmount = 1 ether; // Less than lot size
        uint256 takerQuoteAmount = 0.5 ether; // Small quote amount

        // Setup maker order
        setupOrder(Side.SELL, maker, makerAmount, price);

        vm.prank(address(clobManager));
        clob.setMinLimitOrderAmountInBase(lotSize + 1);

        // Set large lot size
        vm.prank(address(clobManager));
        clob.setLotSizeInBase(lotSize);

        // Setup taker tokens (quote denominated)
        setupTokens(Side.BUY, taker, takerQuoteAmount, price, false);

        // Create quote-denominated IOC order
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: Side.BUY,
            clientOrderId: 0,
            tif: ICLOB.TiF.IOC,
            expiryTime: 0,
            limitPrice: price,
            amount: takerQuoteAmount,
            baseDenominated: false // quote denominated
        });

        // This should revert because baseDelta == 0 (no lots can be filled due to lot size)
        vm.expectRevert(CLOB.ZeroOrder.selector);
        vm.prank(taker);
        clob.placeOrder(taker, args);

        // Verify maker order is unchanged (no trade occurred)
        assertEq(clob.getOrder(1).amount, makerAmount, "Maker order should be unchanged");

        // Verify taker's quote tokens remain in account manager
        uint256 takerQuoteInAccount = clobManager.accountManager().getAccountBalance(taker, address(quoteToken));
        assertEq(takerQuoteInAccount, takerQuoteAmount, "Taker quote should remain in account");
    }

    // ============ PLACEHOLDER TESTS ============

    // /// @dev TODO: Test partial fill scenario that triggers lot size assertion in assertMakeAmountInBounds
    // /// This test should create a scenario where after matching, the remaining amount is too small
    // /// and fails the lot size check, exposing the missing lot size validation
    // function testPlaceFill_PartialFill_LotSizeAssertion() public {
    //     // TODO: Implement test that:
    //     // 1. Places a maker order
    //     // 2. Places a taker order that partially fills the maker
    //     // 3. The remaining amount after fill should be < MIN_LIMIT_ORDER_AMOUNT_IN_BASE but not comply with lot size
    //     // 4. Should trigger assertMakeAmountInBounds lot size assertion
    //     revert("TODO: Implement partial fill lot size test");
    // }

    // ============ MATCH TESTS (Moved from CLOBPost) ============

    /// @dev Fuzz test placing a limit order that matches with existing ask orders
    function testFuzz_PostLimitOrder_MatchBid_Account(uint128 amountInBase, uint128 matchedBase, uint256 price)
        public
    {
        price = bound(price, TICK_SIZE, 100_000 ether);
        price -= price % TICK_SIZE;
        amountInBase -= amountInBase % uint128(clob.getLotSizeInBase());
        matchedBase -= matchedBase % uint128(clob.getLotSizeInBase());
        _assumeLimitOrderParams(amountInBase, matchedBase);
        testPostLimitOrder_MatchBid_Helper(amountInBase, matchedBase, price);
    }

    /// @dev Fuzz test placing a limit order that matches with existing bid orders
    function testFuzz_PostLimitOrder_MatchAsk_Account(uint128 amountInBase, uint128 matchedBase, uint256 price)
        public
    {
        price = bound(price, TICK_SIZE, 100_000 ether);
        price -= price % TICK_SIZE;
        amountInBase -= amountInBase % uint128(clob.getLotSizeInBase());
        matchedBase -= matchedBase % uint128(clob.getLotSizeInBase());
        _assumeLimitOrderParams(amountInBase, matchedBase);
        testPostLimitOrder_MatchAsk_Helper(amountInBase, matchedBase, price);
    }

    function testPostLimitOrder_MatchBid_Helper(uint128 amountInBase, uint128 matchedBase, uint256 price) internal {
        address taker = users[0];
        address maker = users[1];

        if (matchedBase > 0) setupOrder(Side.SELL, maker, matchedBase, price);

        setupTokens(Side.BUY, taker, amountInBase, price, true);

        uint256 balBefore = clobManager.accountManager().getAccountBalance(taker, address(quoteToken));

        // Submit user's order to match with
        vm.prank(taker);
        ICLOB.PlaceOrderResult memory result = clob.placeOrder(
            taker,
            ICLOB.PlaceOrderArgs({
                side: Side.BUY,
                clientOrderId: 0,
                tif: ICLOB.TiF.GTC,
                expiryTime: NEVER,
                limitPrice: price,
                amount: amountInBase,
                baseDenominated: true
            })
        );

        MatchQuantities memory matchQuantities =
            computeMatchQuantities(Side.BUY, amountInBase, matchedBase, price, taker, maker, true);

        // Verify results
        assertEq(result.orderId, matchedBase == 0 ? 1 : 2, "Order ID should increment");
        // If the order was partially filled, the amount posted should match as long as it's above the minimum
        assertEq(
            result.basePosted,
            matchQuantities.postedQuoteInBase >= MIN_LIMIT_ORDER_AMOUNT_IN_BASE ? matchQuantities.postedQuoteInBase : 0,
            "Amount posted should match"
        );
        assertEq(
            result.quoteTokenAmountTraded,
            -int256(matchQuantities.matchedQuote),
            "Quote token amount traded should match"
        );
        assertEq(
            result.baseTokenAmountTraded, int256(matchQuantities.matchedBase), "Base token amount traded should match"
        );

        assertEq(result.takerFee, matchQuantities.takerFeeInBase, "Taker fee should match");

        uint256 expectedQuoteTokenBalance =
            balBefore - uint256(-result.quoteTokenAmountTraded) - quoteTokenAmount(price, result.basePosted);
        assertTokenBalance(taker, Side.BUY, matchQuantities.matchedBase - matchQuantities.takerFeeInBase);
        assertTokenBalance(taker, Side.SELL, expectedQuoteTokenBalance);
        assertTokenBalance(maker, Side.BUY, 0);
        assertTokenBalance(maker, Side.SELL, matchQuantities.matchedQuote - matchQuantities.makerFeeInQuote);
    }

    function testPostLimitOrder_MatchAsk_Helper(uint128 amountInBase, uint128 matchedBase, uint256 price) internal {
        address taker = users[0];
        address maker = users[1];

        if (matchedBase > 0) setupOrder(Side.BUY, maker, matchedBase, price);

        setupTokens(Side.SELL, taker, amountInBase, price, true);

        // Submit user's order to match with
        vm.prank(taker);
        ICLOB.PlaceOrderResult memory result = clob.placeOrder(
            taker,
            ICLOB.PlaceOrderArgs({
                side: Side.SELL,
                clientOrderId: 0,
                tif: ICLOB.TiF.GTC,
                expiryTime: NEVER,
                limitPrice: price,
                amount: amountInBase,
                baseDenominated: true
            })
        );

        MatchQuantities memory matchQuantities =
            computeMatchQuantities(Side.SELL, amountInBase, matchedBase, price, taker, maker, true);

        // Verify results
        assertEq(result.orderId, matchedBase == 0 ? 1 : 2, "Order ID should increment");
        // If the order was partially filled, the amount posted should match as long as it's above the minimum
        assertEq(
            result.basePosted,
            matchQuantities.postedBase >= MIN_LIMIT_ORDER_AMOUNT_IN_BASE ? matchQuantities.postedBase : 0,
            "Amount posted should match"
        );
        assertEq(
            result.quoteTokenAmountTraded,
            int256(matchQuantities.matchedQuote),
            "Quote token amount traded should match"
        );
        assertEq(
            result.baseTokenAmountTraded, -int256(matchQuantities.matchedBase), "Base token amount traded should match"
        );

        assertEq(result.takerFee, matchQuantities.takerFeeInQuote, "Taker fee should match");

        // All base tokens should have been spent UNLESS the order was partially filled
        // and could not post the difference due to min order constraints.
        assertTokenBalance(
            taker,
            Side.BUY,
            matchQuantities.postedBase >= MIN_LIMIT_ORDER_AMOUNT_IN_BASE ? 0 : matchQuantities.postedBase
        );

        assertTokenBalance(taker, Side.SELL, matchQuantities.matchedQuote - matchQuantities.takerFeeInQuote);
        assertTokenBalance(maker, Side.BUY, matchedBase - matchQuantities.makerFeeInBase);
        assertTokenBalance(maker, Side.SELL, 0);
    }

    function _assumeLimitOrderParams(uint256 amountInBase, uint256 matchedBase) internal view {
        bool amountInBaseIsAboveMin = amountInBase >= MIN_LIMIT_ORDER_AMOUNT_IN_BASE;
        bool matchedBaseValid =
            matchedBase <= amountInBase && (matchedBase >= MIN_LIMIT_ORDER_AMOUNT_IN_BASE || matchedBase == 0);
        vm.assume(amountInBaseIsAboveMin && matchedBaseValid);
    }
}
