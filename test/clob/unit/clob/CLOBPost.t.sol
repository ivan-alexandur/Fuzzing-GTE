// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CLOBTestBase, MatchQuantities} from "test/clob/utils/CLOBTestBase.sol";
import {CLOBManager} from "contracts/clob/CLOBManager.sol";
import {AccountManager} from "contracts/account-manager/AccountManager.sol";
import {CLOB} from "contracts/clob/CLOB.sol";
import {ICLOB} from "contracts/clob/ICLOB.sol";
import {Side, Order, OrderLib} from "contracts/clob/types/Order.sol";
import {BookLib, Limit} from "contracts/clob/types/Book.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {TestPlus} from "lib/solady/test/utils/TestPlus.sol";
import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {IERC20Errors} from "@openzeppelin/interfaces/draft-IERC6093.sol";
import "forge-std/console.sol";

contract CLOBPostOrderTest is CLOBTestBase, TestPlus {
    function testPostMake_BuyOrder_GTC_Success_Account() public {
        testPostMake_BuyOrder_GTC_Success_Helper();
    }

    /// @dev Test posting a valid make buy order with sufficient balance and approvals
    function testPostMake_BuyOrder_GTC_Success_Helper() private {
        address user = users[0];
        uint256 amountInBase = 2 ether;
        uint256 price = 100 ether;
        setupTokens(Side.BUY, user, amountInBase, price, true);

        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: Side.BUY,
            clientOrderId: 0,
            tif: ICLOB.TiF.MOC,
            expiryTime: NEVER,
            limitPrice: price,
            amount: amountInBase,
            baseDenominated: true
        });

        // Expect events - should emit OrderProcessed with correct basePosted
        vm.expectEmit(true, true, true, true);
        emit CLOB.OrderProcessed({
            eventNonce: 2, // After LimitOrderCreated (nonce 1)
            account: user,
            orderId: 1,
            tif: args.tif,
            limitPrice: price,
            basePosted: amountInBase, // This should match the actual amount posted (not filled)
            quoteDelta: -int256(0),
            baseDelta: int256(0),
            takerFee: 0
        });

        // Post limit order
        vm.prank(user);
        ICLOB.PlaceOrderResult memory result = clob.placeOrder(user, args);

        // Verify results
        assertEq(result.orderId, 1, "Order ID should be 1");
        assertEq(result.basePosted, amountInBase, "Remaining amount should match");
        assertEq(result.quoteTokenAmountTraded, -int256(0), "Quote token change should be zero");
        assertEq(result.baseTokenAmountTraded, int256(0), "Base token change should be zero");
        // Check order book state
        Order memory order = clob.getOrder(1);
        assertEq(order.owner, user, "Order owner should be user");
        assertEq(order.amount, amountInBase, "Order amount should match");
        assertEq(order.price, price, "Order price should match");
        // User has deposited all tokens and should have no balance left
        assertTokenBalance(user, Side.BUY, 0);
        assertTokenBalance(user, Side.SELL, 0);
    }

    function testPostMake_SellOrder_GTC_Success_Account() public {
        testPostMake_SellOrder_GTC_Success_Helper();
    }

    /// @dev Test posting a valid limit sell order with sufficient balance and approvals
    function testPostMake_SellOrder_GTC_Success_Helper() private {
        address user = users[0];
        uint256 amountInBase = 2 ether;
        uint256 price = 100 ether;

        setupTokens(Side.SELL, user, amountInBase, price, true);

        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: Side.SELL,
            clientOrderId: 0,
            tif: ICLOB.TiF.MOC,
            expiryTime: NEVER,
            limitPrice: price,
            amount: amountInBase,
            baseDenominated: true
        });

        // Expect events - should emit OrderProcessed with correct basePosted
        vm.expectEmit(true, true, true, true);
        emit CLOB.OrderProcessed({
            eventNonce: 2, // After LimitOrderCreated (nonce 1)
            account: user,
            orderId: 1,
            tif: args.tif,
            limitPrice: price,
            basePosted: amountInBase, // This should match the actual amount posted (not filled)
            quoteDelta: int256(0),
            baseDelta: -int256(0),
            takerFee: 0
        });

        // Post limit order
        vm.prank(user);
        ICLOB.PlaceOrderResult memory result = clob.placeOrder(user, args);

        // Verify results
        assertEq(result.orderId, 1, "Order ID should be 1");
        assertEq(result.basePosted, amountInBase, "Remaining amount should match");
        assertEq(result.quoteTokenAmountTraded, int256(0), "Quote token change should be zero");
        assertEq(result.baseTokenAmountTraded, -int256(0), "Base token change should be zero");

        // Check order book state
        Order memory order = clob.getOrder(1);
        assertEq(order.owner, user, "Order owner should be user");
        assertEq(order.amount, amountInBase, "Order amount should match");
        assertEq(order.price, price, "Order price should match");

        // User has deposited all tokens and should have no balance left
        assertTokenBalance(user, Side.BUY, 0);
        assertTokenBalance(user, Side.SELL, 0);
    }

    error OrderIdInUse();

    function testPostMake_OrderCustomClientID(address account, uint96 id) public {
        vm.assume(id != 0);
        vm.assume(account != address(0));
        vm.assume(account != address(clob));
        vm.assume(account != address(clobManager));
        vm.assume(account.code.length == 0);

        uint256 amountInBase = 2 ether;
        uint256 price = 100 ether;

        setupTokens(Side.SELL, account, amountInBase, price, true);

        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: Side.SELL,
            clientOrderId: id,
            tif: ICLOB.TiF.MOC,
            expiryTime: NEVER,
            limitPrice: price,
            amount: amountInBase,
            baseDenominated: true
        });

        uint256 expectedId = uint256(bytes32(abi.encodePacked(account, id)));

        // Expect events - should emit OrderProcessed with custom client order ID
        vm.expectEmit(true, true, true, true);
        emit CLOB.OrderProcessed({
            eventNonce: 2, // After LimitOrderCreated (nonce 1)
            account: account,
            orderId: expectedId,
            tif: args.tif,
            limitPrice: price,
            basePosted: amountInBase,
            quoteDelta: int256(0),
            baseDelta: -int256(0),
            takerFee: 0
        });

        // Post limit order
        vm.startPrank(account);

        uint256 orderId = clob.placeOrder(account, args).orderId;
        assertEq(orderId, expectedId, "Order ID should match the expected ID");

        vm.expectRevert(OrderIdInUse.selector);
        clob.placeOrder(account, args);
    }

    /// @dev Test posting a limit order with invalid price (price out of bounds)
    // function testPostLimitOrder_InvalidPrice_ZeroPrice() public {
    //     address user = users[0];
    //     uint256 amountInBase = 2 ether;
    //     uint256 price = 0;
    //
    //     // Deposit sufficient tokens
    //     setupTokens(Side.BUY, user, amountInBase, price, true);
    //
    //     // Prepare arguments with invalid price
    //     ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
    //         amountInBase: amountInBase,
    //         clientOrderId: 0,
    //         price: price, // Invalid price
    //         cancelTimestamp: TOMORROW,
    //         side: Side.BUY,
    //     });
    //
    //     // Expect revert
    //     vm.expectRevert(BookLib.LimitPriceInvalid.selector);
    //     vm.startPrank(user);
    //
    //     clob.placeOrder(user, args);
    //     vm.stopPrank();
    // }

    function testPostMake_InvalidPrice_TickConfirmation(uint256 price) public {
        // Assume price is not zero (not a market order)
        vm.assume(price != 0);
        // Assume price is not divisible by tick size (invalid)
        vm.assume(price % TICK_SIZE != 0);
        // Bound price to reasonable range to avoid overflow in setupTokens
        vm.assume(price > TICK_SIZE && price < 1e30);

        address user = users[0];
        uint256 amountInBase = 2 ether;

        // Deposit sufficient tokens
        setupTokens(Side.BUY, user, amountInBase, price, true);


        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: Side.BUY,
            clientOrderId: 0,
            tif: ICLOB.TiF.MOC,
            expiryTime: NEVER,
            limitPrice: price,
            amount: amountInBase,
            baseDenominated: true
        });

        // Expect revert due to invalid price
        vm.expectRevert(BookLib.LimitPriceInvalid.selector);
        vm.prank(user);
        clob.placeOrder(user, args);
    }


    function testPostMake_InvalidAmount_TooSmall(uint256 amountInBase) public {
        /// @dev Test posting a limit order with invalid amount (amount < MIN_LIMIT_ORDER_AMOUNT_IN_BASE)
        // Assume amount is less than minimum limit order amount
        vm.assume(amountInBase < MIN_LIMIT_ORDER_AMOUNT_IN_BASE);
        // Assume amount is greater than 0 to avoid other issues
        vm.assume(amountInBase > 0);

        address user = users[0];
        uint256 price = 100 ether;

        // Deposit sufficient tokens
        setupTokens(Side.BUY, user, amountInBase, price, true);

        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: Side.BUY,
            clientOrderId: 0,
            tif: ICLOB.TiF.MOC,
            expiryTime: TOMORROW,
            limitPrice: price,
            amount: amountInBase, // Invalid amount - too small
            baseDenominated: true
        });

        // Expect revert due to invalid amount (should trigger assertLimitOrderAmountInBounds)
        vm.expectRevert(BookLib.LimitOrderAmountInvalid.selector);
        vm.prank(user);
        clob.placeOrder(user, args);
    }

    /// @dev Test posting a make with invalid lot size (amount not divisible by LOT_SIZE_IN_BASE)
    /// this no longer reverts as lots are bound for both base and quote
    // function testPostMake_InvalidLotSize(uint256 amountInBase) public {
    //     // Ensure amount is >= minimum (passes amount check)
    //     vm.assume(amountInBase >= MIN_LIMIT_ORDER_AMOUNT_IN_BASE);
    //     // Ensure amount is NOT divisible by lot size (should fail lot check)
    //     vm.assume(amountInBase % LOT_SIZE_IN_BASE != 0);
    //     // Bound to reasonable range
    //     vm.assume(amountInBase < 1000 ether);

    //     address user = users[0];
    //     uint256 price = 100 ether;

    //     // Deposit sufficient tokens
    //     setupTokens(Side.BUY, user, amountInBase, price, true);

    //     ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
    //         side: Side.BUY,
    //         clientOrderId: 0,
    //         tif: ICLOB.TiF.MOC,
    //         expiryTime: TOMORROW,
    //         limitPrice: price,
    //         amount: amountInBase, // Invalid amount - not divisible by lot size
    //         baseDenominated: true
    //     });

    //     vm.expectRevert(BookLib.LotSizeInvalid.selector);
    //     vm.prank(user);
    //     clob.placeOrder(user, args);
    // }

    function testPostLimitOrder_PostOnlyWouldBeFilled_BuyAccount() public {
        testPostLimitOrder_PostOnlyWouldBeFilled_Helper(Side.BUY);
    }

    function testPostLimitOrder_PostOnlyWouldBeFilled_SellAccount() public {
        testPostLimitOrder_PostOnlyWouldBeFilled_Helper(Side.SELL);
    }

    /// @dev Test posting a post-only limit order that would be immediately filled (should revert)
    function testPostLimitOrder_PostOnlyWouldBeFilled_Helper(Side side) internal {
        address user = users[0];
        uint256 amountInBase = 2 ether;
        uint256 price = 100 ether;

        // First, place an existing opposite-side order to create a match scenario
        address otherUser = users[1];

        // Deposit base tokens for sell order
        Side reverseSide = side == Side.BUY ? Side.SELL : Side.BUY;

        setupTokens(reverseSide, otherUser, amountInBase, price, true);
        setupTokens(side, user, amountInBase, price, true);

        // Place opposite order at the same price using placeOrder with MOC
        ICLOB.PlaceOrderArgs memory oppositeOrderArgs = ICLOB.PlaceOrderArgs({
            side: reverseSide,
            clientOrderId: 0,
            tif: ICLOB.TiF.MOC,
            expiryTime: TOMORROW,
            limitPrice: price,
            amount: amountInBase,
            baseDenominated: true
        });

        vm.prank(otherUser);
        clob.placeOrder(otherUser, oppositeOrderArgs);

        // Now, attempt to place a post-only order that would be filled
        ICLOB.PlaceOrderArgs memory postOnlyArgs = ICLOB.PlaceOrderArgs({
            side: side,
            clientOrderId: 0,
            tif: ICLOB.TiF.MOC, // MOC = Maker Or Cancel (post-only)
            expiryTime: TOMORROW,
            limitPrice: price,
            amount: amountInBase,
            baseDenominated: true
        });

        // Expect revert due to post-only order being filled immediately
        vm.expectRevert(CLOB.PostOnlyOrderWouldFill.selector);
        vm.prank(user);
        clob.placeOrder(user, postOnlyArgs);
    }

    /// @dev Test posting a limit order when max number of orders is reached and new order is not competitive (should revert)
    function testPostLimitOrder_MaxOrdersNotCompetitive_BuyAccount() public {
        testPostLimitOrder_MaxOrdersNotCompetitive_Helper(Side.BUY);
    }

    /// @dev Test posting a limit order when max number of orders is reached and new order is not competitive (should revert) - Sell Side
    function testPostLimitOrder_MaxOrdersNotCompetitive_SellAccount() public {
        testPostLimitOrder_MaxOrdersNotCompetitive_Helper(Side.SELL);
    }

    function testPostLimitOrder_MaxOrdersNotCompetitive_Helper(Side side) internal {
        // Simulate the order book reaching max number of orders
        address user = users[0];
        uint256 amountInBase = 2 ether;
        uint256 price = 100 ether;

        setupTokens(side, user, amountInBase * (MAX_NUM_LIMITS_PER_SIDE + 1), price, true);

        // Place MAX_NUM_LIMITS_PER_SIDE at different prices to fill the order book
        vm.startPrank(user);
        for (uint256 i = 0; i < MAX_NUM_LIMITS_PER_SIDE; i++) {
            // Create different prices for each order to fill up the tree
            side == Side.BUY ? price -= TICK_SIZE : price += TICK_SIZE;
            ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
                side: side,
                clientOrderId: 0,
                tif: ICLOB.TiF.GTC, // GTC = Good Till Cancelled
                expiryTime: NEVER,
                limitPrice: price,
                amount: amountInBase,
                baseDenominated: true
            });
            clob.placeOrder(user, args);
        }

        // Attempt to place a new order at an even less competitive price
        uint256 nonCompetitivePrice = side == Side.BUY ? price - TICK_SIZE : price + TICK_SIZE;

        ICLOB.PlaceOrderArgs memory newOrderArgs = ICLOB.PlaceOrderArgs({
            side: side,
            clientOrderId: 0,
            tif: ICLOB.TiF.GTC, // GTC = Good Till Cancelled
            expiryTime: NEVER,
            limitPrice: nonCompetitivePrice,
            amount: amountInBase,
            baseDenominated: true
        });

        // Expect revert due to max orders in book and order not being competitive
        vm.expectRevert(CLOB.MaxOrdersInBookPostNotCompetitive.selector);
        clob.placeOrder(user, newOrderArgs);
        vm.stopPrank();
    }

    /// @dev Test posting a limit order when max number of orders is reached and new order is competitive (should replace existing order) - Buy Side
    function testPostLimitOrder_MaxOrdersCompetitive_BuyAccount() public {
        testPostLimitOrder_MaxOrdersCompetitive_Helper(Side.BUY);
    }

    /// @dev Test posting a limit order when max number of orders is reached and new order is competitive (should replace existing order) - Buy Side
    /// @dev Test posting a limit order when max number of orders is reached and new order is competitive (should replace existing order) - Sell Side
    function testPostLimitOrder_MaxOrdersCompetitive_SellAccount() public {
        testPostLimitOrder_MaxOrdersCompetitive_Helper(Side.SELL);
    }

    struct MaxOrdersParams {
        uint256 orderId;
        address user;
        address moreCompetitiveUser;
        uint256 lessCompetitivePrice;
        uint256 moreCompetitivePrice;
        uint256 amountInBase;
        uint256 amountInQuote;
        uint32 cancelTimestamp;
    }

    struct TailOrderState {
        Limit limitBefore;
        Order tailBefore;
        Order tailPrevBefore;
        uint256 leastCompetitivePrice;
    }

    struct PostReplacementState {
        Limit limitAfter;
        Order newTailAfter;
        uint256 newCompetitiveOrderId;
        Order newCompetitiveOrder;
        Limit competitiveLimitAfter;
    }

    function testPostLimitOrder_MaxOrdersCompetitive_Helper(Side side) internal {
        MaxOrdersParams memory p;
        // Simulate the order book reaching max number of orders
        p.orderId = clob.getNextOrderId();
        p.user = users[0];
        p.moreCompetitiveUser = users[1];
        p.lessCompetitivePrice = 100 ether;
        p.moreCompetitivePrice =
            side == Side.BUY ? p.lessCompetitivePrice + TICK_SIZE : p.lessCompetitivePrice - TICK_SIZE;
        p.amountInBase = 10 ether;
        p.amountInQuote = clob.getQuoteTokenAmount(p.lessCompetitivePrice, p.amountInBase);
        p.cancelTimestamp = TOMORROW;

        setupTokens(side, p.user, p.amountInBase * (MAX_NUM_LIMITS_PER_SIDE), p.lessCompetitivePrice, true);
        setupTokens(side, p.moreCompetitiveUser, p.amountInBase, p.moreCompetitivePrice, true);

        // Place MAX_NUM_LIMITS_PER_SIDE at a less competitive price to fill the order book
        // But place 2 orders at the same least competitive price to test tail order replacement
        vm.startPrank(p.user);
        for (uint256 i = 0; i < MAX_NUM_LIMITS_PER_SIDE - 2; i++) {
            // Creates a new limit that is less competitive than the order
            side == Side.BUY ? p.lessCompetitivePrice -= TICK_SIZE : p.lessCompetitivePrice += TICK_SIZE;
            ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
                side: side,
                clientOrderId: 0,
                tif: ICLOB.TiF.GTC, // GTC = Good Till Cancelled
                expiryTime: p.cancelTimestamp,
                limitPrice: p.lessCompetitivePrice,
                amount: p.amountInBase,
                baseDenominated: true
            });
            clob.placeOrder(p.user, args);
        }

        // Place the final least competitive price level (this will have 2 orders)
        side == Side.BUY ? p.lessCompetitivePrice -= TICK_SIZE : p.lessCompetitivePrice += TICK_SIZE;
        uint256 finalLeastCompetitivePrice = p.lessCompetitivePrice;

        // Place the first order at the least competitive price (this will be head)
        ICLOB.PlaceOrderArgs memory firstOrderAtLeastCompetitive = ICLOB.PlaceOrderArgs({
            side: side,
            clientOrderId: 0,
            tif: ICLOB.TiF.GTC,
            expiryTime: p.cancelTimestamp,
            limitPrice: finalLeastCompetitivePrice,
            amount: p.amountInBase,
            baseDenominated: true
        });
        clob.placeOrder(p.user, firstOrderAtLeastCompetitive);

        // Place the second order at the least competitive price (this will be tail and get replaced)
        ICLOB.PlaceOrderArgs memory secondOrderAtLeastCompetitive = ICLOB.PlaceOrderArgs({
            side: side,
            clientOrderId: 0,
            tif: ICLOB.TiF.GTC,
            expiryTime: p.cancelTimestamp,
            limitPrice: finalLeastCompetitivePrice,
            amount: p.amountInBase,
            baseDenominated: true
        });
        clob.placeOrder(p.user, secondOrderAtLeastCompetitive);

        p.moreCompetitivePrice = side == Side.BUY ? 100 ether + TICK_SIZE : 100 ether - TICK_SIZE;

        // Get tail order info before the replacement
        TailOrderState memory beforeState;
        beforeState.leastCompetitivePrice = finalLeastCompetitivePrice;
        beforeState.limitBefore = clob.getLimit(beforeState.leastCompetitivePrice, side);
        beforeState.tailBefore = clob.getOrder(beforeState.limitBefore.tailOrder.unwrap());
        beforeState.tailPrevBefore = clob.getOrder(beforeState.tailBefore.prevOrderId.unwrap());

        // Verify we have the expected structure: 2 orders at the least competitive price
        assertEq(beforeState.limitBefore.numOrders, 2, "Should have 2 orders at least competitive price before");
        assertEq(
            beforeState.tailPrevBefore.nextOrderId.unwrap(),
            beforeState.tailBefore.id.unwrap(),
            "Tail's previous should point to tail before"
        );

        uint256 quoteBalBefore = clobManager.accountManager().getAccountBalance(p.user, address(clob.getQuoteToken()));
        uint256 baseBalBefore = clobManager.accountManager().getAccountBalance(p.user, address(clob.getBaseToken()));

        // Calculate the quote amount for the least competitive order that will be canceled
        uint256 expectedRefundQuote = clob.getQuoteTokenAmount(beforeState.leastCompetitivePrice, p.amountInBase);

        // Attempt to place a new order at a more competitive price
        ICLOB.PlaceOrderArgs memory newOrderArgs = ICLOB.PlaceOrderArgs({
            side: side,
            clientOrderId: 0,
            tif: ICLOB.TiF.MOC, // MOC = Maker Or Cancel (post-only)
            expiryTime: p.cancelTimestamp,
            limitPrice: p.moreCompetitivePrice,
            amount: p.amountInBase,
            baseDenominated: true
        });

        vm.startPrank(p.moreCompetitiveUser);

        // Expect the new OrderProcessed event instead of old events
        vm.expectEmit(true, true, true, true);
        emit CLOB.OrderProcessed(
            clob.getEventNonce() + 3, // After OrderCanceled + LimitOrderCreated
            p.moreCompetitiveUser,
            p.orderId + MAX_NUM_LIMITS_PER_SIDE, // This will be the new order ID (1001, not 1000)
            ICLOB.TiF.MOC, // MOC = Maker Or Cancel (post-only)
            p.moreCompetitivePrice,
            p.amountInBase, // basePosted
            int256(0), // quoteDelta (no trade occurred)
            int256(0), // baseDelta (no trade occurred)
            0 // takerFee
        );

        // Post the new order which should replace the least competitive one
        clob.placeOrder(p.moreCompetitiveUser, newOrderArgs);
        vm.stopPrank();
        uint256 quoteBalAfter = clobManager.accountManager().getAccountBalance(p.user, address(clob.getQuoteToken()));
        uint256 baseBalAfter = clobManager.accountManager().getAccountBalance(p.user, address(clob.getBaseToken()));

        // Verify that the order book still has MAX_NUM_LIMITS_PER_SIDE
        if (side == Side.BUY) {
            assertEq(quoteBalAfter - quoteBalBefore, expectedRefundQuote, "incorrect quote token bal");
            assertEq(baseBalAfter, baseBalBefore, "incorrect base token bal");
            assertEq(clob.getNumBids(), MAX_NUM_LIMITS_PER_SIDE, "Order book should still have max number of bids");
        } else {
            assertEq(quoteBalAfter, quoteBalBefore, "incorrect quote token bal");
            assertEq(baseBalAfter - baseBalBefore, p.amountInBase, "incorrect base token bal");
            assertEq(clob.getNumAsks(), MAX_NUM_LIMITS_PER_SIDE, "Order book should still have max number of asks");
        }

        // Additional assertions for tail order analysis as requested
        PostReplacementState memory afterState;
        afterState.limitAfter = clob.getLimit(beforeState.leastCompetitivePrice, side);
        afterState.newTailAfter = clob.getOrder(afterState.limitAfter.tailOrder.unwrap());
        afterState.newCompetitiveOrderId = p.orderId + MAX_NUM_LIMITS_PER_SIDE;
        afterState.newCompetitiveOrder = clob.getOrder(afterState.newCompetitiveOrderId);
        afterState.competitiveLimitAfter = clob.getLimit(p.moreCompetitivePrice, side);

        // Verify the structure after replacement:
        // 1. The least competitive limit now has only 1 order (the first order remained, tail was removed)
        assertEq(afterState.limitAfter.numOrders, 1, "Should have 1 order at least competitive price after");

        // 2. The tail order was replaced: the penultimate order is now the tail
        assertEq(
            afterState.newTailAfter.id.unwrap(),
            beforeState.tailPrevBefore.id.unwrap(),
            "Previous order should now be the tail"
        );

        // 3. The new tail order has no next order (since the old tail was removed)
        assertEq(afterState.newTailAfter.nextOrderId.unwrap(), 0, "New tail should have no next order");

        // 4. The new competitive order should be placed at the more competitive price
        assertEq(
            afterState.newCompetitiveOrder.price,
            p.moreCompetitivePrice,
            "New competitive order should be at competitive price"
        );

        // 5. The new competitive order should be properly linked in its limit
        assertEq(afterState.competitiveLimitAfter.numOrders, 1, "Should have 1 order at more competitive price");
        assertEq(
            afterState.competitiveLimitAfter.tailOrder.unwrap(),
            afterState.newCompetitiveOrderId,
            "New order should be tail at competitive price"
        );
        assertEq(
            afterState.competitiveLimitAfter.headOrder.unwrap(),
            afterState.newCompetitiveOrderId,
            "New order should be head at competitive price"
        );
    }

    // @dev Fuzz test posting a make with insufficient token balance (should revert)
    function testPostMake_Buy_InsufficientBalance(uint256 orderAmountInBase, uint256 setupAmountInBase) public {
        address user = users[2];
        uint256 price = 100 ether;

        // Bound orderAmountInBase to pass lot size and minimum amount constraints
        orderAmountInBase = bound(orderAmountInBase, MIN_LIMIT_ORDER_AMOUNT_IN_BASE, 100 ether);
        // Round down to nearest lot size
        orderAmountInBase = (orderAmountInBase / LOT_SIZE_IN_BASE) * LOT_SIZE_IN_BASE;
        // Ensure it's still above minimum after rounding
        if (orderAmountInBase < MIN_LIMIT_ORDER_AMOUNT_IN_BASE) orderAmountInBase = MIN_LIMIT_ORDER_AMOUNT_IN_BASE;

        // Bound setupAmountInBase to be insufficient (less than orderAmountInBase)
        setupAmountInBase = bound(setupAmountInBase, 1, orderAmountInBase - 1);

        // Setup insufficient tokens
        setupTokens(Side.BUY, user, setupAmountInBase, price, true);

        // Prepare arguments
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: Side.BUY,
            clientOrderId: 0,
            tif: ICLOB.TiF.MOC, // MOC = Maker Or Cancel (post-only)
            expiryTime: TOMORROW,
            limitPrice: price,
            amount: orderAmountInBase,
            baseDenominated: true
        });

        vm.startPrank(user);
        // Expect revert due to insufficient token balance
        vm.expectRevert(AccountManager.BalanceInsufficient.selector);
        clob.placeOrder(user, args);
        vm.stopPrank();
    }

    // @dev Fuzz test posting a make with insufficient token balance (should revert)
    function testPostMake_Sell_InsufficientBalance(uint256 orderAmountInBase, uint256 setupAmountInBase) public {
        address user = users[2];
        uint256 price = 100 ether;

        // Bound orderAmountInBase to pass lot size and minimum amount constraints
        orderAmountInBase = bound(orderAmountInBase, MIN_LIMIT_ORDER_AMOUNT_IN_BASE, 100 ether);
        // Round down to nearest lot size
        orderAmountInBase = (orderAmountInBase / LOT_SIZE_IN_BASE) * LOT_SIZE_IN_BASE;
        // Ensure it's still above minimum after rounding
        if (orderAmountInBase < MIN_LIMIT_ORDER_AMOUNT_IN_BASE) orderAmountInBase = MIN_LIMIT_ORDER_AMOUNT_IN_BASE;

        // Bound setupAmountInBase to be insufficient (less than orderAmountInBase)
        setupAmountInBase = bound(setupAmountInBase, 1, orderAmountInBase - 1);

        // Setup insufficient tokens
        setupTokens(Side.SELL, user, setupAmountInBase, price, true);

        // Prepare arguments
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: Side.SELL,
            clientOrderId: 0,
            tif: ICLOB.TiF.MOC,
            expiryTime: TOMORROW,
            limitPrice: price,
            amount: orderAmountInBase,
            baseDenominated: true
        });

        // Should revert with insufficient balance
        vm.prank(user);
        vm.expectRevert(AccountManager.BalanceInsufficient.selector);
        clob.placeOrder(user, args);
        vm.stopPrank();
    }

    /// @dev Test posting a limit order with an expired cancelTimestamp (should revert)
    function testPostMake_Sell_ExpiredCancelTimestamp() public {
        address user = users[4];
        uint256 amountInBase = 1 ether;
        uint256 price = 100 ether;

        vm.warp(uint256(TOMORROW));
        uint32 cancelTimestamp = uint32(block.timestamp - 12 hours); // Expired timestamp

        setupTokens(Side.SELL, user, amountInBase, price, true);

        // Prepare arguments with expired cancelTimestamp
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: Side.SELL,
            clientOrderId: 0,
            tif: ICLOB.TiF.MOC, // MOC = Maker Or Cancel (post-only)
            expiryTime: cancelTimestamp, // Expired
            limitPrice: price,
            amount: amountInBase,
            baseDenominated: true
        });

        vm.expectRevert(OrderLib.MakerOrderExpired.selector);
        vm.startPrank(user);

        clob.placeOrder(user, args);
        vm.stopPrank();
    }

    // @todo
    // /// @dev Test that an ask limit too small to get added to book after matching doesnt't cost the user the dust
    // function test_PostLimitOrder_MatchAsk_NOOPLimit() public {
    //     revert("unimplemented");
    // }
    // /// @dev Test that a bid limit too small to get added to book after matching doesn't cost the user the dust
    // function test_PostLimitOrder_MatchBid_NOOPLimit() public {
    //     revert("unimplemented");
    // }

    // NOTE: Match tests moved to CLOBFill.t.sol since they test matching/filling behavior, not pure posting

    function test_PostLimitOrder_LimitsPlacedExceedsMax_ExpectRevert() public {
        // Create a new user that is not max limit exempt
        address user = makeAddr("nonExemptUser");
        uint256 amountInBase = 1 ether;
        uint256 price = 100 ether;

        // Set maxLimitsPerTx to 1 for easier testing
        vm.prank(address(clobManager));
        clob.setMaxLimitsPerTx(1);

        // Setup tokens for 2 orders (1 allowed + 1 that will fail)
        uint256 quoteAmount = quoteTokenAmount(amountInBase, price);
        setupTokens(Side.BUY, user, quoteAmount * 2, price, true);

        vm.startPrank(user);

        // Post the first order (should succeed)
        ICLOB.PlaceOrderArgs memory firstOrder = ICLOB.PlaceOrderArgs({
            side: Side.BUY,
            clientOrderId: 0,
            tif: ICLOB.TiF.GTC,
            expiryTime: NEVER,
            limitPrice: price,
            amount: amountInBase,
            baseDenominated: true
        });

        clob.placeOrder(user, firstOrder);

        // Attempt to post second order in the same transaction (should fail)
        ICLOB.PlaceOrderArgs memory secondOrder = ICLOB.PlaceOrderArgs({
            side: Side.BUY,
            clientOrderId: 0,
            tif: ICLOB.TiF.GTC,
            expiryTime: NEVER,
            limitPrice: price + TICK_SIZE, // Different price to avoid matching
            amount: amountInBase,
            baseDenominated: true
        });

        // Expect revert due to exceeding max limits per transaction
        vm.expectRevert(BookLib.LimitsPlacedExceedsMax.selector);
        clob.placeOrder(user, secondOrder);

        vm.stopPrank();
    }

    /// @dev tests that max limit exempt external call only happens once
    function test_PostLimitOrder_MaxLimitExemptCaching() public {
        address user = users[0]; // This user is max limit exempt
        uint256 amountInBase = 1 ether;
        uint256 price = 100 ether;

        // Set maxLimitsPerTx to 1 for easier testing
        vm.prank(address(clobManager));
        clob.setMaxLimitsPerTx(1);

        // Setup tokens for 3 orders
        uint256 quoteAmount = quoteTokenAmount(amountInBase, price);
        setupTokens(Side.BUY, user, quoteAmount * 3, price, true);

        // exemption call shiuld only happen once
        vm.expectCall(address(clobManager), abi.encodeCall(clobManager.getMaxLimitExempt, (user)), 1);

        vm.startPrank(user);

        ICLOB.PlaceOrderArgs memory firstOrder = ICLOB.PlaceOrderArgs({
            side: Side.BUY,
            clientOrderId: 0,
            tif: ICLOB.TiF.GTC,
            expiryTime: NEVER,
            limitPrice: price,
            amount: amountInBase,
            baseDenominated: true
        });

        // First order hits max limits
        clob.placeOrder(user, firstOrder);

        ICLOB.PlaceOrderArgs memory secondOrder = ICLOB.PlaceOrderArgs({
            side: Side.BUY,
            clientOrderId: 0,
            tif: ICLOB.TiF.GTC,
            expiryTime: NEVER,
            limitPrice: price + TICK_SIZE,
            amount: amountInBase,
            baseDenominated: true
        });

        // Second order results in a exemption list call
        clob.placeOrder(user, secondOrder);

        ICLOB.PlaceOrderArgs memory thirdOrder = ICLOB.PlaceOrderArgs({
            side: Side.BUY,
            clientOrderId: 0,
            tif: ICLOB.TiF.GTC,
            expiryTime: NEVER,
            limitPrice: price + (2 * TICK_SIZE),
            amount: amountInBase,
            baseDenominated: true
        });

        // third order does not perform external exemption call
        clob.placeOrder(user, thirdOrder);

        vm.stopPrank();

        // Verify all 3 orders were actually posted so its not a false positive
        assertTrue(clob.getOrder(1).owner == user, "First order should exist");
        assertTrue(clob.getOrder(2).owner == user, "Second order should exist");
        assertTrue(clob.getOrder(3).owner == user, "Third order should exist");
    }

    // /// @dev This addresses the c4 S-381 finding that post only orders will revert if the top of book is crossed
    // /// but only cancellations, not matching occur.
    // /// Post only orders should be able to succeed even if the TOB was crossed as long as it only removed expired orders
    // function test_PostLimitOrder_PostOnlyCanClearExpiredOrders_Bid() public {
    //     address expiredMaker = users[0];
    //     address postMaker = users[1];

    //     // Give both users some tokens by setting up for their orders
    //     setupTokens(Side.SELL, expiredMaker, 1e18, 1000e18, true);
    //     setupTokens(Side.BUY, postMaker, 1e18, 1001e18, true);

    //     // First, place an ask order that will expire
    //     vm.startPrank(expiredMaker);
    //     clob.placeOrder(
    //         expiredMaker,
    //         ICLOB.PlaceOrderArgs({
    //             side: Side.SELL,
    //             clientOrderId: 0,
    //             tif: ICLOB.TiF.GTC,
    //             expiryTime: uint32(block.timestamp + 1),
    //             limitPrice: 1000e18,
    //             amount: 1e18,
    //             baseDenominated: true
    //         })
    //     );
    //     vm.stopPrank();

    //     // Move time forward so the order expires
    //     vm.warp(block.timestamp + 2);

    //     // Now test with bid post-only order that crosses the expired ask
    //     vm.startPrank(postMaker);
    //     ICLOB.PlaceOrderResult memory bidResult = clob.placeOrder(
    //         postMaker,
    //         ICLOB.PlaceOrderArgs({
    //             side: Side.BUY,
    //             clientOrderId: 0,
    //             tif: ICLOB.TiF.MOC, // MOC = Maker Or Cancel (post-only)
    //             expiryTime: 0,
    //             limitPrice: 1001e18, // Higher than the expired ask
    //             amount: 1e18,
    //             baseDenominated: true
    //         })
    //     );
    //     vm.stopPrank();

    //     // Verify the bid post-only order was placed successfully
    //     assertEq(bidResult.basePosted, 1e18, "Bid post-only order should be placed");
    //     assertTrue(clob.getOrder(bidResult.orderId).owner == postMaker, "Bid order should exist");
    // }

    // /// @dev Test that ask post-only orders can also clear expired orders without reverting
    // function test_PostLimitOrder_PostOnlyCanClearExpiredOrders_Ask() public {
    //     address expiredMaker = users[0];
    //     address postMaker = users[1];

    //     // Give both users some tokens
    //     setupTokens(Side.BUY, expiredMaker, 1e18, 1000e18, true);
    //     setupTokens(Side.SELL, postMaker, 1e18, 999e18, true);

    //     // Place a bid order that will expire
    //     vm.startPrank(expiredMaker);
    //     clob.placeOrder(
    //         expiredMaker,
    //         ICLOB.PlaceOrderArgs({
    //             side: Side.BUY,
    //             clientOrderId: 0,
    //             tif: ICLOB.TiF.GTC,
    //             expiryTime: uint32(block.timestamp + 1),
    //             limitPrice: 1000e18,
    //             amount: 1e18,
    //             baseDenominated: true
    //         })
    //     );
    //     vm.stopPrank();

    //     // Move time forward so the order expires
    //     vm.warp(block.timestamp + 2);

    //     // Try to place an ask post-only order that crosses the expired bid
    //     vm.startPrank(postMaker);
    //     ICLOB.PlaceOrderResult memory askResult = clob.placeOrder(
    //         postMaker,
    //         ICLOB.PlaceOrderArgs({
    //             side: Side.SELL,
    //             clientOrderId: 0,
    //             tif: ICLOB.TiF.MOC, // MOC = Maker Or Cancel (post-only)
    //             expiryTime: 0,
    //             limitPrice: 999e18, // Lower than the expired bid
    //             amount: 1e18,
    //             baseDenominated: true
    //         })
    //     );
    //     vm.stopPrank();

    //     // Verify the ask post-only order was placed successfully
    //     assertEq(askResult.basePosted, 1e18, "Ask post-only order should be placed");
    //     assertTrue(clob.getOrder(askResult.orderId).owner == postMaker, "Ask order should exist");
    // }
}
