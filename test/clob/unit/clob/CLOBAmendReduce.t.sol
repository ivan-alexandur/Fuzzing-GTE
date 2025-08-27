// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {CLOBTestBase} from "test/clob/utils/CLOBTestBase.sol";
import {CLOB, ICLOB, Order, OrderId, Limit, Side, OrderLib} from "contracts/clob/CLOB.sol";
import {BookLib} from "contracts/clob/types/Book.sol";
import {MarketSettings} from "contracts/clob/types/Book.sol";
/**
 * Cases:
 *
 * Happy paths:
 * - quote refunded account (done)
 * - quote refunded instant (done)
 * - base refunded account (done)
 * - base refunded instant (done)
 *
 * - order is expired, cancel it (done)
 * - new order amount would be less than minimun limit size, cancel it (done)
 *
 * Sad paths:
 * - Order does not exist (done)
 *     - It's not possible for this to revert if the owner check is first
 * - Order is owned by someone else (done)
 * - Reduce amount is 0 (done)
 *
 * Invariants:
 * - Order is reduced by exact amount requested or cancelled
 *     - (this will probably fail, i think this got missed in refactor)
 * - OI only changes by cancel amount in atoms
 *     - (this will probably fail due to oi double reduction problem)
 * - Refund is the amount actually reduced, not requested
 * - if cancelled, same invariants as cancel
 */

contract CLOBAmendReduceTest is CLOBTestBase {
    using SafeTransferLib for address;

    // HAPPY PATHS //
    function test_reduce_base_account() public {
        address user = users[1];
        uint256 amountInBase = 10 ether;
        uint256 price = 100 ether;

        // Deposit sufficient base tokens
        setupTokens(Side.SELL, user, amountInBase, price, true);

        // Prepare arguments
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: Side.SELL,
            clientOrderId: 0,
            tif: ICLOB.TiF.MOC,
            expiryTime: TOMORROW,
            limitPrice: price,
            amount: amountInBase,
            baseDenominated: true
        });

        vm.startPrank(user);
        // Post limit order
        ICLOB.PlaceOrderResult memory result = clob.placeOrder(user, args);

        uint256 newAmount = 6 ether;
        uint256 reduceAmount = amountInBase - newAmount;
        ReduceState memory state = getPreReduceState(result.orderId, reduceAmount);

        assertEq(
            clobManager.accountManager().getAccountBalance(user, address(clob.getBaseToken())),
            0,
            "base token bal != 0 before reduce"
        );

        ICLOB.AmendArgs memory rArgs = ICLOB.AmendArgs({
            orderId: result.orderId,
            amountInBase: newAmount,
            price: price,
            cancelTimestamp: TOMORROW,
            side: Side.SELL
        });

        assertEq(clobManager.accountManager().getAccountBalance(user, address(clob.getBaseToken())), 0);

        clob.amend(user, rArgs);

        assertEq(
            clobManager.accountManager().getAccountBalance(user, address(clob.getBaseToken())),
            reduceAmount,
            "base token account bal != reduce amount"
        );

        assertPostReduceState({s: state, isCancelled: false});
    }

    function test_reduce_quote_account() public {
        address user = users[1];
        uint256 amountInBase = 10 ether;
        uint256 price = 100 ether;

        // Deposit sufficient quote tokens
        setupTokens(Side.BUY, user, amountInBase, price, true);

        // Prepare arguments
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            amount: amountInBase,
            clientOrderId: 0,
            limitPrice: price,
            expiryTime: TOMORROW,
            side: Side.BUY,
            tif: ICLOB.TiF.MOC,
            baseDenominated: true
        });

        vm.startPrank(user);
        // Post limit order
        ICLOB.PlaceOrderResult memory result = clob.placeOrder(user, args);

        uint256 newAmount = 6 ether;
        uint256 reduceAmount = amountInBase - newAmount;
        ReduceState memory state = getPreReduceState(result.orderId, reduceAmount);

        ICLOB.AmendArgs memory rArgs = ICLOB.AmendArgs({
            orderId: result.orderId,
            amountInBase: newAmount,
            price: price,
            cancelTimestamp: TOMORROW,
            side: Side.BUY
        });

        // vm.expectEmit(); // @todo
        // emit CLOB.OrderReduced(
        //     result.orderId,
        //     result.amountPostedInBaseLots - reduceAmount,
        //     reduceAmount,
        //     rArgs.
        //     clob.getEventNonce() + 1
        // );

        assertEq(clobManager.accountManager().getAccountBalance(user, address(clob.getQuoteToken())), 0);

        clob.amend(user, rArgs);

        assertEq(
            clobManager.accountManager().getAccountBalance(user, address(clob.getQuoteToken())),
            clob.getQuoteTokenAmount(price, reduceAmount),
            "incorrect quote amount"
        );

        assertPostReduceState({s: state, isCancelled: false});
    }

    function test_reduce_expired_cancel() public {
        address user = users[1];
        uint256 amountInBase = 10 ether;
        uint256 price = 100 ether;

        // Deposit sufficient quote tokens
        setupTokens(Side.BUY, user, amountInBase, price, true);

        // Prepare arguments
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            amount: amountInBase,
            clientOrderId: 0,
            limitPrice: price,
            expiryTime: TOMORROW,
            side: Side.BUY,
            tif: ICLOB.TiF.MOC,
            baseDenominated: true
        });

        vm.startPrank(user);
        // Post limit order
        ICLOB.PlaceOrderResult memory result = clob.placeOrder(user, args);

        uint256 newAmount = 6 ether;

        ICLOB.AmendArgs memory rArgs = ICLOB.AmendArgs({
            orderId: result.orderId,
            amountInBase: newAmount,
            price: price,
            cancelTimestamp: TOMORROW,
            side: Side.BUY
        });

        vm.warp(block.timestamp + 2 days);
        vm.expectRevert(CLOB.AmendInvalid.selector);
        clob.amend(user, rArgs);
    }

    function test_reduce_amount_equals_order_cancel() public {
        address user = users[1];
        uint256 amountInBase = 10 ether;
        uint256 price = 100 ether;

        // Deposit sufficient quote tokens
        setupTokens(Side.BUY, user, amountInBase, price, true);

        vm.startPrank(user);
        // Prepare arguments
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            amount: amountInBase,
            clientOrderId: 0,
            limitPrice: price,
            expiryTime: TOMORROW,
            side: Side.BUY,
            tif: ICLOB.TiF.MOC,
            baseDenominated: true
        });

        // Post limit order
        ICLOB.PlaceOrderResult memory result = clob.placeOrder(user, args);

        ICLOB.AmendArgs memory rArgs = ICLOB.AmendArgs({
            orderId: result.orderId,
            amountInBase: 0,
            price: price,
            cancelTimestamp: TOMORROW,
            side: Side.BUY
        });

        vm.expectRevert(BookLib.LimitOrderAmountInvalid.selector);
        clob.amend(user, rArgs);
    }

    function test_reduce_new_amount_less_than_min_order_size_cancel() public {
        address user = users[1];
        uint256 amountInBase = 10 ether;
        uint256 price = 100 ether;

        // Deposit sufficient quote tokens
        setupTokens(Side.BUY, user, amountInBase, price, true);

        vm.startPrank(user);
        // Prepare arguments
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            amount: amountInBase,
            clientOrderId: 0,
            limitPrice: price,
            expiryTime: TOMORROW,
            side: Side.BUY,
            tif: ICLOB.TiF.MOC,
            baseDenominated: true
        });

        // Post limit order
        ICLOB.PlaceOrderResult memory result = clob.placeOrder(user, args);

        // Reduce by the whole order size, this should remove the order from book
        MarketSettings memory _settings = clob.getMarketSettings();

        ICLOB.AmendArgs memory rArgs = ICLOB.AmendArgs({
            orderId: result.orderId,
            amountInBase: _settings.minLimitOrderAmountInBase - clob.getLotSizeInBase(),
            price: price,
            cancelTimestamp: TOMORROW,
            side: Side.BUY
        });

        vm.expectRevert(BookLib.LimitOrderAmountInvalid.selector);
        clob.amend(user, rArgs);
    }
    // SAD PATHS //

    function testFuzz_reduce_wrong_owner_expect_revert(address caller) public {
        address user = users[1];
        vm.assume(user != caller);
        uint256 amountInBase = 10 ether;
        uint256 price = 100 ether;

        // Deposit sufficient quote tokens
        setupTokens(Side.BUY, user, amountInBase, price, true);

        // Prepare arguments
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            amount: amountInBase,
            clientOrderId: 0,
            limitPrice: price,
            expiryTime: TOMORROW,
            side: Side.BUY,
            tif: ICLOB.TiF.MOC,
            baseDenominated: true
        });

        // Post limit order
        vm.prank(user);
        ICLOB.PlaceOrderResult memory result = clob.placeOrder(user, args);

        // Reduce order
        ICLOB.AmendArgs memory rArgs;
        rArgs.orderId = result.orderId;
        rArgs.price = 100 ether;

        // `caller` is passing itself as the account to get refunded,
        // but using the users order id
        vm.prank(caller);
        vm.expectRevert(CLOB.AmendUnauthorized.selector);
        clob.amend(caller, rArgs);
    }

    // @todo this shouldnt be able to revert, because a nil order would mean
    // a nil owner, which would fail the owner check
    function test_reduce_order_is_nil_expect_revert() public {
        address user = users[1];

        // Reduce order fully
        ICLOB.AmendArgs memory rArgs =
            ICLOB.AmendArgs({orderId: 20, amountInBase: 50 ether, price: 10, cancelTimestamp: TOMORROW, side: Side.BUY});

        vm.prank(user);
        vm.expectRevert(OrderLib.OrderNotFound.selector);
        clob.amend(user, rArgs);
    }

    // INVARIANTS //
    struct ReduceState {
        Order order;
        uint256 reduceAmount;
        uint256 limitNumOrders;
        uint256 openInterest;
        uint256 numBids;
        uint256 numAsks;
    }

    function getPreReduceState(uint256 id, uint256 reduceAmount) internal view returns (ReduceState memory state) {
        Order memory order = clob.getOrder(id);

        state.order = order;
        state.reduceAmount = reduceAmount;

        Limit memory limit = clob.getLimit(order.price, order.side);
        state.limitNumOrders = limit.numOrders;

        (uint256 quoteOi, uint256 baseOi) = clob.getOpenInterest();
        if (order.side == Side.BUY) {
            state.openInterest = quoteOi;
            state.numBids = clob.getNumBids();
        } else {
            state.openInterest = baseOi;
            state.numAsks = clob.getNumAsks();
        }
    }

    function assertPostReduceState(ReduceState memory s, bool isCancelled) internal view {
        (uint256 quoteOi, uint256 baseOi) = clob.getOpenInterest();
        uint256 amountReduced = isCancelled ? s.order.amount : s.reduceAmount;
        if (s.order.side == Side.BUY) {
            uint256 quoteReduced = clob.getQuoteTokenAmount(s.order.price, amountReduced);
            assertEq(s.openInterest - quoteReduced, quoteOi, "quote oi != expected");
        } else {
            assertEq(s.openInterest - amountReduced, baseOi, "base oi != expected");
        }

        Order memory order = clob.getOrder(s.order.id.unwrap());
        assertEq(order.amount, s.order.amount - amountReduced, "order amount != expected");

        // Cancel assertions
        if (!isCancelled) {
            assertEq(s.numBids, clob.getNumBids());
            assertEq(s.numAsks, clob.getNumAsks());
            return;
        }

        Limit memory limit = clob.getLimit(s.order.price, s.order.side);
        if (limit.headOrder.unwrap() != 0) {
            Order memory o = clob.getOrder(limit.headOrder.unwrap());
            for (uint256 i = 0; i < limit.numOrders; i++) {
                assertFalse(o.nextOrderId.unwrap() == s.order.id.unwrap());
                o = clob.getOrder(o.nextOrderId.unwrap());
            }
        }

        assertEq(s.limitNumOrders, limit.numOrders + 1);

        uint256 prev = s.order.prevOrderId.unwrap();
        uint256 next = s.order.nextOrderId.unwrap();

        if (prev > 0) {
            Order memory p = clob.getOrder(prev);
            assertEq(p.nextOrderId.unwrap(), next);
        }

        if (next > 0) {
            Order memory n = clob.getOrder(next);
            assertEq(n.prevOrderId.unwrap(), prev);
        }

        if (s.order.side == Side.BUY) {
            assertEq(s.numBids - 1, clob.getNumBids());
            assertEq(s.numAsks, clob.getNumAsks());
        } else {
            assertEq(s.numAsks - 1, clob.getNumAsks());
            assertEq(s.numBids, clob.getNumBids());
        }

        Order memory nil = order;
        assertEq(nil.id.unwrap(), 0);
        assertEq(nil.prevOrderId.unwrap(), 0);
        assertEq(nil.nextOrderId.unwrap(), 0);
        assertEq(nil.amount, 0);
        assertEq(nil.price, 0);
        assertEq(nil.owner, address(0));
        assertEq(uint8(nil.side), 0);
    }
}
