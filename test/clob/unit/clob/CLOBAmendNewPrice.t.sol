// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {CLOBTestBase} from "test/clob/utils/CLOBTestBase.sol";
import {CLOB, ICLOB, Order, OrderId, Limit, Side, OrderLib, BookLib} from "contracts/clob/CLOB.sol";
import {MarketSettings} from "contracts/clob/types/Book.sol";
import "forge-std/console.sol";

contract CLOBAmendNewPrice is CLOBTestBase {
    using SafeTransferLib for address;

    struct IncreaseState {
        Order order;
        uint256 limitNumOrders;
        uint256 newPrice;
        uint256 quoteAccountBalance;
        uint256 baseAccountBalance;
        uint256 quoteTokenBalance;
        uint256 baseTokenBalance;
        uint256 quoteOi;
        uint256 baseOi;
        uint256 numBids;
        uint256 numAsks;
    }

    IncreaseState state;
    address user;

    function setUp() public override {
        super.setUp();
        user = users[1];
    }

    function test_Amend_NewPrice_IncreaseBid_Account() public {
        uint256 amountInBase = 10 ether;
        uint256 price = 100 ether;
        uint256 newPrice = state.newPrice = 110 ether;

        // Deposit sufficient base tokens
        setupTokens(Side.BUY, user, amountInBase, newPrice, true);

        // Prepare arguments
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: Side.BUY,
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
        // Cache pre-increase state
        cachePreIncreaseState(result.orderId);

        ICLOB.AmendArgs memory rArgs = ICLOB.AmendArgs({
            orderId: result.orderId,
            amountInBase: amountInBase,
            price: newPrice,
            cancelTimestamp: TOMORROW,
            side: Side.BUY
        });

        // change side
        (int256 quoteDelta, int256 baseDelta) = clob.amend(user, rArgs);
        // Assert post-increase state
        assertPostNewPrice(quoteDelta, baseDelta);
    }

    function test_Amend_NewPrice_IncreaseAsk_Account() public {
        uint256 amountInBase = 10 ether;
        uint256 price = 100 ether;
        uint256 newPrice = state.newPrice = 110 ether;

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

        // Cache pre-increase state
        cachePreIncreaseState(result.orderId);
        ICLOB.AmendArgs memory rArgs = ICLOB.AmendArgs({
            orderId: result.orderId,
            amountInBase: amountInBase,
            price: newPrice,
            cancelTimestamp: TOMORROW,
            side: Side.SELL
        });

        // change side
        (int256 quoteDelta, int256 baseDelta) = clob.amend(user, rArgs);
        // Assert post-increase state
        assertPostNewPrice(quoteDelta, baseDelta);
    }
    // INVARIANTS //

    function cachePreIncreaseState(uint256 id) internal {
        Order memory order = clob.getOrder(id);
        state.order = order;

        Limit memory limit = clob.getLimit(order.price, order.side);
        state.limitNumOrders = limit.numOrders;

        (state.quoteOi, state.baseOi) = clob.getOpenInterest();
        state.numBids = clob.getNumBids();
        state.numAsks = clob.getNumAsks();
        state.quoteAccountBalance = clobManager.accountManager().getAccountBalance(user, address(clob.getQuoteToken()));
        state.baseAccountBalance = clobManager.accountManager().getAccountBalance(user, address(clob.getBaseToken()));
        state.quoteTokenBalance = clob.getQuoteToken().balanceOf(user);
        state.baseTokenBalance = clob.getBaseToken().balanceOf(user);
    }

    function assertPostNewPrice(int256 quoteTokenDelta, int256 baseTokenDelta) internal view {
        (uint256 quoteOi, uint256 baseOi) = clob.getOpenInterest();
        int256 quoteChange;

        if (state.order.side == Side.BUY) {
            int256 oldQuote = int256(clob.getQuoteTokenAmount(state.order.price, state.order.amount));
            int256 newQuote = int256(clob.getQuoteTokenAmount(state.newPrice, state.order.amount));
            quoteChange = oldQuote - newQuote;
        }

        assertEq(quoteTokenDelta, quoteChange, "quote token delta != expected");
        assertEq(baseTokenDelta, 0, "base token delta != expected");

        assertEq(
            state.limitNumOrders,
            clob.getLimit(state.newPrice, state.order.side).numOrders,
            "limit num orders != expected"
        );

        assertEq(uint256(int256(state.quoteOi) - quoteChange), quoteOi, "quote oi != expected");
        assertEq(state.baseOi, baseOi, "base oi != expected");

        assertEq(
            state.quoteAccountBalance,
            uint256(
                int256(clobManager.accountManager().getAccountBalance(user, address(clob.getQuoteToken())))
                    - quoteChange
            ),
            "quote account balance != expected"
        );

        assertEq(state.quoteTokenBalance, clob.getQuoteToken().balanceOf(user), "quote token balance != expected");

        assertEq(
            state.baseAccountBalance,
            clobManager.accountManager().getAccountBalance(user, address(clob.getBaseToken())),
            "base account balance != expected"
        );

        assertEq(state.baseTokenBalance, clob.getBaseToken().balanceOf(user), "base token balance != expected");

        Order memory order = clob.getOrder(state.order.id.unwrap());
        assertEq(order.amount, state.order.amount, "order amount != expected");
    }

    /// @dev C4 spot S-15. Amending ignores the max limit allowlist,
    /// so moving the price of a batch of orders can be used to
    /// send large blocks of spam up to the top oif the book
    function test_Amend_NewPrice_MaxOrdersExceeded_ExpectRevert() public {
        // Since being allowlisted to place many orders is cached in clob, we cant revoke the caller in the same test / txn,
        // or the clob will still think the caller is exempt. so 2 diff operators need to be the caller to test this
        address OPERATOR_POST = vm.randomAddress();
        address OPERATOR_AMEND = vm.randomAddress();

        // @todo abi change here when merging c4 fixes into staging, approve takes the account also
        // give both these operators full privledge to trade on behalf of user
        vm.startPrank(user);
        accountManager.approveOperator(user, OPERATOR_POST, 1);
        accountManager.approveOperator(user, OPERATOR_AMEND, 1);
        vm.stopPrank();

        vm.prank(address(clobManager));
        clob.setMaxLimitsPerTx(10);

        // // OPERATOR_POST can now post
        // bool[] memory ex = new bool[](1);
        // address[] memory usrs = new address[](1);
        // ex[0] = true;
        // usrs[0] = OPERATOR_POST;
        // clobManager.setMaxLimitsExempt(usrs, ex);

        uint256 amountInBase = 10 ether;
        uint256 price = 100 ether;
        uint256 newPrice = state.newPrice = 110 ether;

        // Deposit sufficient base tokens
        setupTokens(Side.SELL, user, amountInBase, price, true);

        // Prepare arguments
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: Side.SELL,
            clientOrderId: 0,
            tif: ICLOB.TiF.MOC,
            expiryTime: TOMORROW,
            limitPrice: price,
            amount: amountInBase / 10,
            baseDenominated: true
        });

        uint256 id;
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(OPERATOR_POST);
            ICLOB.PlaceOrderResult memory res = clob.placeOrder(user, args);
            id = res.orderId;
        }

        ICLOB.AmendArgs memory args2 = ICLOB.AmendArgs({
            orderId: 0,
            amountInBase: args.amount,
            price: newPrice,
            cancelTimestamp: TOMORROW,
            side: Side.SELL
        });

        vm.prank(address(clobManager));
        clob.setMaxLimitsPerTx(19);

        for (uint256 i = 0; i < 9; i++) {
            args2.orderId = i + 1;
            vm.prank(OPERATOR_AMEND);
            clob.amend(user, args2);
        }

        args2.orderId = 10;
        vm.prank(OPERATOR_AMEND);
        vm.expectRevert(BookLib.LimitsPlacedExceedsMax.selector);
        clob.amend(user, args2);
    }
}
