// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";
import {DynamicArrayLib} from "@solady/utils/DynamicArrayLib.sol";

import {IGTL} from "../interfaces/IGTL.sol";

import {Constants} from "../types/Constants.sol";
import {BookType, TiF} from "../types/Enums.sol";
import {
    PlaceOrderArgs, PlaceOrderResult, __TradeData__, AmendLimitOrderArgs, MakerFillResult
} from "../types/Structs.sol";

import {StorageLib} from "../types/StorageLib.sol";
import {Order, OrderLib, OrderId, OrderIdLib, Side} from "../types/Order.sol";
import {Book, BookLib, Limit, BookConfig, BookSettings} from "../types/Book.sol";
import {ClearingHouse, ClearingHouseLib} from "../types/ClearingHouse.sol";

library CLOBLib {
    using OrderLib for *;
    using OrderLib for uint256;
    using OrderIdLib for *;
    using FixedPointMathLib for *;
    using SafeCastLib for uint256;
    using DynamicArrayLib for uint256[];

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                 EVENTS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    event CancelFailed(
        bytes32 indexed asset, uint256 indexed orderId, address indexed owner, BookType bookType, uint256 nonce
    );

    event OrderProcessed(
        bytes32 indexed asset,
        address indexed account,
        uint256 subaccount,
        uint256 indexed orderId,
        uint256 amountSubmitted,
        bool baseDenominated,
        TiF tif,
        uint32 expiryTime,
        uint256 limitPrice,
        Side side,
        bool reduceOnly,
        uint256 basePosted,
        uint256 quoteTraded,
        uint256 baseTraded,
        BookType bookType,
        uint256 nonce
    );

    event OrderCanceled(
        bytes32 indexed asset,
        uint256 indexed orderId,
        address indexed owner,
        uint256 subaccount,
        uint256 collateralRefunded,
        BookType bookType,
        uint256 nonce
    );

    event OrderAmended(
        bytes32 indexed asset,
        uint256 indexed orderId,
        Order newOrder,
        int256 collateralDelta,
        BookType bookType,
        uint256 nonce
    );

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                 ERRORS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @dev sig: 0x32cc7236
    error NotFactory();
    /// @dev sig: 0x87e393a7
    error FOKNotFilled();
    /// @dev sig: 0xdf7d9ed2
    error UnauthorizedReduce();
    // @dev sig: 0x60ab4840
    error UnauthorizedAmend();
    /// @dev sig: 0x45bb6073
    error UnauthorizedCancel();
    /// @dev sig: 0x3154078e
    error OrderAlreadyExpired();
    /// @dev sig: 0xadaa5d56
    error ReduceAmountOutOfBounds();
    /// @dev sig: 0x3d104567
    error InvalidAccountOrOperator();
    /// @dev sig: 0x52409ba3
    error PostOnlyOrderWouldBeFilled();
    /// @dev sig: 0x315ff5e5
    error MaxOrdersInBookPostNotCompetitive();
    /// @dev sig: 0x4b22649a
    error InvalidAmend();
    error IncorrectSubaccount();
    error ZeroOrder();
    error ZeroAmount();
    error InvalidMakerPrice();
    error InvalidOrderArgs();

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                     CONSTRUCTOR AND INITIALIZATION
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function init(bytes32 asset, BookSettings memory bookSettings, uint256 lotSize) internal {
        Book storage ds = _getStorage(asset, BookType.STANDARD);
        BookSettings storage dsSettings = StorageLib.loadBookSettings(asset);

        dsSettings.maxNumOrders = bookSettings.maxNumOrders;
        dsSettings.maxLimitsPerTx = bookSettings.maxLimitsPerTx;
        dsSettings.minLimitOrderAmountInBase = bookSettings.minLimitOrderAmountInBase;
        dsSettings.tickSize = bookSettings.tickSize;

        ds.config.asset = asset;
        ds.config.bookType = BookType.STANDARD;
        ds.config.lotSize = lotSize;

        ds = _getStorage(asset, BookType.BACKSTOP);

        ds.config.asset = asset;
        ds.config.bookType = BookType.BACKSTOP;
        ds.config.lotSize = lotSize;
    }

    address public constant GTL = Constants.GTL;

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                           EXTERNAL WRITES
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function placeOrder(address account, PlaceOrderArgs memory args, BookType bookType)
        internal
        returns (PlaceOrderResult memory result)
    {
        Book storage ds = _getStorage(args.asset, bookType);

        // time in force below 1 is maker
        if (uint8(args.tif) <= 1 && args.limitPrice == 0) revert InvalidMakerPrice();
        if (args.amount == 0) revert ZeroAmount();
        ds.assertPriceInBounds(args.limitPrice);
        if (args.expiryTime.isExpired()) revert OrderAlreadyExpired();

        uint256 orderId = ds.toOrderId(account, args.clientOrderId);
        Order memory newOrder = args.toOrder(orderId, account);

        if (args.side == Side.BUY) result = _processBuyOrder(ds, newOrder, args);
        else result = _processSellOrder(ds, newOrder, args);

        if (result.baseTraded + result.quoteTraded + result.basePosted == 0) revert ZeroOrder();

        if (!args.reduceOnly && result.basePosted > 0) {
            _updateOrderbookNotional(
                args.asset, account, args.subaccount, result.basePosted.fullMulDiv(newOrder.price, 1e18).toInt256()
            );
        }

        _emitOrderProcessed(account, args, result, bookType);
    }

    /// @notice Amends an existing order for `account`
    function amend(address account, AmendLimitOrderArgs calldata args, BookType bookType)
        internal
        returns (int256 collateralDelta)
    {
        Book storage ds = _getStorage(args.asset, bookType);
        Order storage order = ds.orders[args.orderId.wrap()];

        if (order.id.unwrap() == 0) revert OrderLib.OrderNotFound();
        if (order.owner != account) revert UnauthorizedAmend();
        if (order.subaccount != args.subaccount) revert IncorrectSubaccount();

        ds.assertLimitPriceInBounds(args.price);
        ds.assertLimitOrderAmountInBounds(args.baseAmount);

        int256 notionalDelta;
        (notionalDelta, collateralDelta) = _processAmend(ds, order, args);

        _updateOrderbookNotional(args.asset, account, args.subaccount, notionalDelta);

        emit OrderAmended(args.asset, args.orderId, order, collateralDelta, ds.config.bookType, StorageLib.incNonce());
    }

    function cancel(bytes32 asset, address account, uint256 subaccount, uint256[] memory orderIds, BookType bookType)
        internal
        returns (uint256 collateralRefunded)
    {
        Book storage ds = _getStorage(asset, bookType);

        collateralRefunded = _executeCancel(ds, account, subaccount, orderIds);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                             INTERNAL LOGIC
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _processBuyOrder(Book storage ds, Order memory newOrder, PlaceOrderArgs memory args)
        internal
        returns (PlaceOrderResult memory result)
    {
        result.orderId = newOrder.id.unwrap();

        (result.quoteTraded, result.baseTraded) = _executeBuyOrder(ds, newOrder, args.tif, args.baseDenominated);

        // if maker order
        if (uint8(args.tif) <= 1) result.basePosted = newOrder.amount;
    }

    function _processSellOrder(Book storage ds, Order memory newOrder, PlaceOrderArgs memory args)
        internal
        returns (PlaceOrderResult memory result)
    {
        result.orderId = newOrder.id.unwrap();

        (result.quoteTraded, result.baseTraded) = _executeSellOrder(ds, newOrder, args.tif, args.baseDenominated);

        // if maker order
        if (uint8(args.tif) <= 1) result.basePosted = newOrder.amount;
    }

    function _executeBuyOrder(Book storage ds, Order memory newOrder, TiF tif, bool baseDenominated)
        internal
        returns (uint256 quoteSent, uint256 baseReceived)
    {
        // if price crosses the book
        if (ds.getBestAsk() <= newOrder.price) {
            if (tif == TiF.MOC) revert PostOnlyOrderWouldBeFilled();
            (quoteSent, baseReceived) = _matchIncomingBid(ds, newOrder, baseDenominated);
        }

        if (tif == TiF.FOK && newOrder.amount > 0) revert FOKNotFilled();

        // if taker order
        if (uint8(tif) > 1) return (quoteSent, baseReceived);

        // Max limits per tx is enforced on the caller to allow for whitelisted operators
        // to implement their own max limit logic.
        ds.incrementLimitsPlaced(msg.sender);

        // convert quote denominated to base
        if (!baseDenominated) newOrder.amount = newOrder.amount.fullMulDiv(1e18, newOrder.price);

        /// bound to lots and above min size
        newOrder.amount = ds.getPostableBaseAmount(newOrder.amount);

        if (newOrder.amount == 0) return (quoteSent, baseReceived);

        if (ds.metadata.numBids < StorageLib.loadBookSettings(ds.config.asset).maxNumOrders) {
            // Book has room for new order
            ds.addOrderToBook(newOrder);
        } else if (
            ds.metadata.numBids == StorageLib.loadBookSettings(ds.config.asset).maxNumOrders
                && newOrder.price > ds.getMinBidPrice()
        ) {
            // The max orders are filled, but this order is more competitive
            Order storage removeOrder = ds.orders[ds.bidLimits[ds.getMinBidPrice()].tailOrder];

            _removeUnfillableOrder(ds, removeOrder);

            ds.addOrderToBook(newOrder);
        } else {
            delete newOrder.amount;
        }
    }

    function _executeSellOrder(Book storage ds, Order memory newOrder, TiF tif, bool baseDenominated)
        internal
        returns (uint256 quoteReceived, uint256 baseSent)
    {
        // if price crosses the book
        if (ds.getBestBid() >= newOrder.price) {
            if (tif == TiF.MOC) revert PostOnlyOrderWouldBeFilled();
            (quoteReceived, baseSent) = _matchIncomingAsk(ds, newOrder, baseDenominated);
        }

        if (tif == TiF.FOK && newOrder.amount > 0) revert FOKNotFilled();

        // if taker order
        if (uint8(tif) > 1) return (quoteReceived, baseSent);

        // Max limits per tx is enforced on the caller to allow for whitelisted operators
        // to implement their own max limit logic.
        ds.incrementLimitsPlaced(msg.sender);

        // convert quote denominated to base
        if (!baseDenominated) newOrder.amount = newOrder.amount.fullMulDiv(1e18, newOrder.price);

        // bound to lots and above min size
        newOrder.amount = ds.getPostableBaseAmount(newOrder.amount);

        if (newOrder.amount == 0) return (quoteReceived, baseSent);

        if (ds.metadata.numAsks < StorageLib.loadBookSettings(ds.config.asset).maxNumOrders) {
            ds.addOrderToBook(newOrder);
        } else if (
            ds.metadata.numAsks == StorageLib.loadBookSettings(ds.config.asset).maxNumOrders
                && newOrder.price < ds.getMaxAskPrice()
        ) {
            Order storage removeOrder = ds.orders[ds.askLimits[ds.getMaxAskPrice()].tailOrder];

            _removeUnfillableOrder(ds, removeOrder);

            ds.addOrderToBook(newOrder);
        } else {
            delete newOrder.amount;
        }
    }

    function _removeUnfillableOrder(Book storage ds, Order storage order) internal {
        uint256 quoteTokenAmount = order.amount.fullMulDiv(order.price, 1e18);
        uint256 orderId = order.id.unwrap();
        bytes32 asset = ds.config.asset;
        address owner = order.owner;
        uint256 subaccount = order.subaccount;

        uint256 collateralRefund;
        if (!order.reduceOnly) {
            collateralRefund = quoteTokenAmount.fullMulDiv(1e18, _getLeverage(asset, owner, subaccount));

            _updateOrderbookNotional(asset, owner, subaccount, -quoteTokenAmount.toInt256());
        }

        emit OrderCanceled(
            asset, orderId, owner, subaccount, collateralRefund, ds.config.bookType, StorageLib.incNonce()
        );

        StorageLib.loadCollateralManager().creditAccount(owner, collateralRefund);

        ds.removeOrderFromBook(order);
    }

    /// @notice Match incoming bid order to best asks
    function _matchIncomingBid(Book storage ds, Order memory incomingOrder, bool baseDenominated)
        internal
        returns (uint256 quoteSent, uint256 baseReceived)
    {
        uint256 bestAsk = ds.getBestAsk();
        uint256 maxAsk = StorageLib.loadMarket(ds.config.asset).getMaxDivergingAskPrice();

        while (bestAsk <= incomingOrder.price && incomingOrder.amount > 0) {
            if (bestAsk == type(uint256).max) break;
            if (bestAsk > maxAsk) break;

            Limit storage limit = ds.askLimits[bestAsk];
            Order storage bestAskOrder = ds.orders[limit.headOrder];

            if (bestAskOrder.isExpired()) {
                _removeUnfillableOrder(ds, bestAskOrder);
                bestAsk = ds.getBestAsk();
                continue;
            }

            __TradeData__ memory data = _matchIncomingOrder(ds, bestAskOrder, incomingOrder, baseDenominated);

            incomingOrder.amount -= data.filledAmount;

            baseReceived += data.baseTraded;
            quoteSent += data.quoteTraded;

            if (limit.numOrders == 0) bestAsk = ds.getBestAsk();
        }
    }

    function _matchIncomingAsk(Book storage ds, Order memory incomingOrder, bool baseDenominated)
        internal
        returns (uint256 totalQuoteTokenReceived, uint256 totalBaseTokenSent)
    {
        uint256 bestBid = ds.getBestBid();
        uint256 minBid = StorageLib.loadMarket(ds.config.asset).getMaxDivergingBidPrice();

        while (bestBid >= incomingOrder.price && incomingOrder.amount > 0) {
            if (bestBid == 0) break;
            if (bestBid < minBid) break;

            Limit storage limit = ds.bidLimits[bestBid];
            Order storage bestBidOrder = ds.orders[limit.headOrder];

            if (bestBidOrder.isExpired()) {
                _removeUnfillableOrder(ds, bestBidOrder);
                bestBid = ds.getBestBid();
                continue;
            }

            __TradeData__ memory data = _matchIncomingOrder(ds, bestBidOrder, incomingOrder, baseDenominated);

            incomingOrder.amount -= data.filledAmount;

            totalQuoteTokenReceived += data.quoteTraded;
            totalBaseTokenSent += data.baseTraded;

            if (limit.numOrders == 0) bestBid = ds.getBestBid();
        }
    }

    function _matchIncomingOrder(
        Book storage ds,
        Order storage matchedOrder,
        Order memory incomingOrder,
        bool baseDenominated // true if incomingOrder is in base, false if in quote
    ) internal returns (__TradeData__ memory tradeData) {
        address matchedOwner = matchedOrder.owner;

        if (incomingOrder.owner == matchedOwner) {
            _removeUnfillableOrder(ds, matchedOrder);
            return tradeData;
        }

        if (matchedOrder.reduceOnly) _boundReduceOnlyOrder(ds, matchedOrder);

        tradeData = ds.getTradedAmounts({
            makerBase: matchedOrder.amount,
            takerAmount: incomingOrder.amount,
            price: matchedOrder.price,
            baseDenominated: baseDenominated
        });

        if (tradeData.baseTraded == 0) return tradeData;

        bool orderRemoved = tradeData.baseTraded == matchedOrder.amount;

        // handle maker fill
        bool unfillable = StorageLib.loadClearingHouse().processMakerFill(
            MakerFillResult({
                asset: ds.config.asset,
                bookType: ds.config.bookType,
                orderId: matchedOrder.id.unwrap(),
                maker: matchedOwner,
                subaccount: matchedOrder.subaccount,
                side: matchedOrder.side,
                quoteAmountTraded: tradeData.quoteTraded,
                baseAmountTraded: tradeData.baseTraded,
                reduceOnly: matchedOrder.reduceOnly
            })
        );

        if (unfillable) {
            _removeUnfillableOrder(ds, matchedOrder);
            return __TradeData__(0, 0, 0);
        } else if (!orderRemoved) {
            if (incomingOrder.side == Side.BUY) ds.metadata.baseOI -= tradeData.baseTraded;
            else ds.metadata.quoteOI -= tradeData.quoteTraded;
        }

        if (!matchedOrder.reduceOnly) {
            _updateOrderbookNotional(
                ds.config.asset, matchedOwner, matchedOrder.subaccount, -tradeData.quoteTraded.toInt256()
            );
        }

        if (orderRemoved) ds.removeOrderFromBook(matchedOrder);
        else matchedOrder.amount -= tradeData.baseTraded;
    }

    function _executeCancel(Book storage ds, address account, uint256 subaccount, uint256[] memory orderIds)
        internal
        returns (uint256 totalCollateralRefunded)
    {
        bytes32 asset = ds.config.asset;
        BookType bookType = ds.config.bookType;
        uint256 numOrders = orderIds.length;

        uint256 orderId;
        for (uint256 i; i < numOrders; ++i) {
            orderId = orderIds[i];
            Order storage order = ds.orders[orderId.wrap()];

            // This loads the whole order
            if (order.isNull()) {
                emit CancelFailed(asset, orderId, account, bookType, StorageLib.incNonce());
                continue; // Order may have been matched
            } else if (order.owner != account) {
                revert UnauthorizedCancel();
            } else if (order.subaccount != subaccount) {
                revert IncorrectSubaccount();
            }

            uint256 collateralRefunded;
            if (!order.reduceOnly) {
                uint256 quoteAmount = order.amount.fullMulDiv(order.price, 1e18);
                collateralRefunded = quoteAmount.fullMulDiv(1e18, _getLeverage(asset, account, subaccount));
                _updateOrderbookNotional(asset, account, subaccount, -quoteAmount.toInt256());
            }

            emit OrderCanceled(asset, orderId, account, subaccount, collateralRefunded, bookType, StorageLib.incNonce());

            totalCollateralRefunded += collateralRefunded;

            ds.removeOrderFromBook(order);
        }
    }

    function _boundReduceOnlyOrder(Book storage ds, Order storage order) internal {
        uint256 positionAmount = StorageLib.loadMarket(ds.config.asset).position[order.owner][order.subaccount].amount;

        if (positionAmount < order.amount) {
            uint256 reduceAmount = order.amount - positionAmount;

            order.amount = positionAmount;

            if (order.side == Side.BUY) ds.metadata.quoteOI -= reduceAmount.fullMulDiv(order.price, 1e18);
            else ds.metadata.baseOI -= reduceAmount;
        }
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                          INTERNAL AMEND LOGIC
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @dev Performs the amending of an order
    function _processAmend(Book storage ds, Order storage order, AmendLimitOrderArgs calldata args)
        internal
        returns (int256 notionalDelta, int256 collateralDelta)
    {
        if (
            args.expiryTime.isExpired()
                || args.baseAmount < StorageLib.loadBookSettings(ds.config.asset).minLimitOrderAmountInBase
        ) {
            revert InvalidAmend();
        } else if (order.side != args.side || order.price != args.price) {
            // change place in book
            return _executeAmendNewOrder(ds, order, args);
        } else {
            // change amount
            return _executeAmendAmount(ds, order, args);
        }
    }

    /// @dev Performs the removal and replacement of an amended order with a new price or side
    function _executeAmendNewOrder(Book storage ds, Order storage order, AmendLimitOrderArgs calldata args)
        internal
        returns (int256 notionalDelta, int256 collateralDelta)
    {
        Order memory newOrder = args.toOrder(order);

        uint256 leverage = _getLeverage(args.asset, newOrder.owner, newOrder.subaccount);

        if (!order.reduceOnly) {
            uint256 orderNotional = order.amount.fullMulDiv(order.price, 1e18);

            notionalDelta -= orderNotional.toInt256();
            collateralDelta -= orderNotional.fullMulDiv(1e18, leverage).toInt256();
        }

        ds.removeOrderFromBook(order);

        // amends restricted to post-only
        if (args.side == Side.BUY) _executeBuyOrder(ds, newOrder, TiF.MOC, true);
        else _executeSellOrder(ds, newOrder, TiF.MOC, true);

        if (!newOrder.reduceOnly) {
            uint256 orderNotional = newOrder.amount.fullMulDiv(newOrder.price, 1e18);

            notionalDelta += orderNotional.toInt256();
            collateralDelta += orderNotional.fullMulDiv(1e18, leverage).toInt256();
        }
    }

    /// @dev Performs the updating of an amended order with a new amount
    function _executeAmendAmount(Book storage ds, Order storage order, AmendLimitOrderArgs calldata args)
        internal
        returns (int256 notionalDelta, int256 collateralDelta)
    {
        uint256 price = order.price;
        uint256 newQuoteAmount = args.baseAmount.fullMulDiv(price, 1e18);
        uint256 oldQuoteAmount = order.amount.fullMulDiv(price, 1e18);
        uint256 leverage = _getLeverage(args.asset, order.owner, args.subaccount);

        if (!order.reduceOnly) {
            uint256 orderNotional = order.amount.fullMulDiv(order.price, 1e18);
            notionalDelta -= orderNotional.toInt256();
            collateralDelta -= orderNotional.fullMulDiv(1e18, leverage).toInt256();
        }

        if (!args.reduceOnly) {
            uint256 newOrderNotional = args.baseAmount.fullMulDiv(price, 1e18);
            notionalDelta += newOrderNotional.toInt256();
            collateralDelta += newOrderNotional.fullMulDiv(1e18, leverage).toInt256();
        }

        if (order.side == Side.BUY) {
            int256 quoteDelta = oldQuoteAmount.toInt256() - newQuoteAmount.toInt256();

            ds.metadata.quoteOI = (ds.metadata.quoteOI.toInt256() - quoteDelta).abs();
        } else {
            int256 baseDelta = order.amount.toInt256() - args.baseAmount.toInt256();

            ds.metadata.baseOI = (ds.metadata.baseOI.toInt256() - baseDelta).abs();
        }

        if (order.reduceOnly != args.reduceOnly) {
            if (args.reduceOnly) {
                StorageLib.loadMarket(ds.config.asset).linkReduceOnlyOrder(
                    order.owner, order.subaccount, args.orderId, ds.config.bookType
                );
            } else {
                StorageLib.loadMarket(ds.config.asset).unlinkReduceOnlyOrder(
                    order.owner, order.subaccount, args.orderId, ds.config.bookType
                );
            }
        }

        order.amount = args.baseAmount;
        order.reduceOnly = args.reduceOnly;
        order.expiryTime = args.expiryTime;
    }

    function _emitOrderProcessed(
        address account,
        PlaceOrderArgs memory args,
        PlaceOrderResult memory result,
        BookType bookType
    ) internal {
        emit OrderProcessed({
            asset: args.asset,
            account: account,
            subaccount: args.subaccount,
            orderId: result.orderId,
            amountSubmitted: args.amount,
            baseDenominated: args.baseDenominated,
            tif: args.tif,
            expiryTime: args.expiryTime,
            limitPrice: args.limitPrice,
            side: args.side,
            reduceOnly: args.reduceOnly,
            basePosted: result.basePosted,
            quoteTraded: result.quoteTraded,
            baseTraded: result.baseTraded,
            bookType: bookType,
            nonce: StorageLib.incNonce()
        });
    }

    function _updateOrderbookNotional(bytes32 asset, address account, uint256 subaccount, int256 amount) private {
        StorageLib.loadMarket(asset).updateOrderbookNotional(account, subaccount, amount);
    }

    function _getLeverage(bytes32 asset, address account, uint256 subaccount) internal view returns (uint256) {
        return StorageLib.loadMarket(asset).getPositionLeverage(account, subaccount);
    }

    function _div(int256 a, int256 b) private pure returns (int256) {
        uint256 result = a.abs().fullMulDiv(1e18, b.abs());
        return a < 0 != b < 0 ? -result.toInt256() : result.toInt256();
    }

    function _getStorage(bytes32 asset, BookType bookType) internal pure returns (Book storage) {
        return StorageLib.loadBook(asset, bookType);
    }
}
