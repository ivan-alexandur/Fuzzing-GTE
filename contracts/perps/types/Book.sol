// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

import {RedBlackTree} from "../../clob/types/RedBlackTree.sol";
import {__TradeData__} from "./Structs.sol";
import {BookType, Side} from "./Enums.sol";
import {Order, OrderLib, OrderId, OrderIdLib} from "./Order.sol";
import {ClearingHouseLib} from "./ClearingHouse.sol";
import {StorageLib} from "./StorageLib.sol";

uint256 constant MIN_LIMIT_PRICE = 1;
uint256 constant MIN_FILL_ORDER_AMOUNT_BASE = 1;
uint256 constant MIN_MIN_LIMIT_ORDER_AMOUNT_BASE = 10;

struct BookConfig {
    bytes32 asset;
    uint256 lotSize;
    BookType bookType;
}

struct BookSettings {
    uint256 maxNumOrders;
    uint8 maxLimitsPerTx;
    uint256 minLimitOrderAmountInBase;
    uint256 tickSize;
}

struct BookMetadata {
    uint96 orderIdCounter;
    uint256 numBids;
    uint256 numAsks;
    uint256 baseOI;
    uint256 quoteOI;
}

struct Limit {
    uint64 numOrders;
    OrderId headOrder;
    OrderId tailOrder;
}

struct Book {
    BookConfig config;
    BookMetadata metadata;
    RedBlackTree bidTree; // header
    RedBlackTree askTree; // header
    mapping(OrderId => Order) orders;
    mapping(uint256 price => Limit) bidLimits; // header
    mapping(uint256 price => Limit) askLimits; // header
}

using BookLib for Book global;

library BookLib {
    using OrderIdLib for uint256;
    using FixedPointMathLib for uint256;

    error OrderPriceOutOfBounds();
    error LimitPriceOutOfBounds();
    error LimitOrderAmountNotOnLotSize();
    error LimitOrderAmountOutOfBounds();
    error NoOrdersAtLimit();
    error LimitsPlacedExceedsMaxThisTx();
    error InvalidMaxLimitsPerTx();
    error InvalidMinLimitOrderAmountInBase();
    error OrderIdInUse();

    bytes32 constant MAX_LIMIT_ALLOWLIST =
        keccak256(abi.encode(uint256(keccak256("MAX_LIMIT_ALLOWLIST")) - 1)) & ~bytes32(uint256(0xff));

    bytes32 constant TRANSIENT_LIMITS_PLACED =
        keccak256(abi.encode(uint256(keccak256("TRANSIENT_LIMITS_PLACED")) - 1)) & ~bytes32(uint256(0xff));

    // ASSERTIONS //

    function exists(Book storage self) internal view returns (bool) {
        return self.config.asset != bytes32(0);
    }

    function assertLimitPriceInBounds(Book storage self, uint256 price) internal view {
        uint256 tickSize = StorageLib.loadBookSettings(self.config.asset).tickSize;

        if (price == 0 || price % tickSize != 0) revert LimitPriceOutOfBounds();
    }

    function assertPriceInBounds(Book storage self, uint256 price) internal view {
        // zero price is ok for market orders
        if (price % StorageLib.loadBookSettings(self.config.asset).tickSize != 0) revert OrderPriceOutOfBounds();
    }

    function assertOrdersAtLimit(Book storage self, uint256 price, Side side) internal view {
        if (self.getLimit(price, side).numOrders == 0) revert NoOrdersAtLimit();
    }

    function assertLimitOrderAmountInBounds(Book storage self, uint256 orderAmountInBase) internal view {
        if (orderAmountInBase < StorageLib.loadBookSettings(self.config.asset).minLimitOrderAmountInBase) {
            revert LimitOrderAmountOutOfBounds();
        }
        if (orderAmountInBase % self.config.lotSize != 0) revert LimitOrderAmountNotOnLotSize();
    }

    function assertUnusedOrderId(Book storage self, uint256 orderId) internal view {
        if (self.orders[orderId.wrap()].owner != address(0)) revert OrderIdInUse();
    }

    // GETTERS //

    /// @dev Returns the highest bid price
    function getBestBid(Book storage self) internal view returns (uint256) {
        return self.bidTree.maximum();
    }

    /// @dev Returns the lowest ask price
    function getBestAsk(Book storage self) internal view returns (uint256) {
        return self.askTree.minimum();
    }

    /// @dev Returns the lowest bid price
    function getMinBidPrice(Book storage self) internal view returns (uint256) {
        return self.bidTree.minimum();
    }

    /// @dev Returns the highest ask price
    function getMaxAskPrice(Book storage self) internal view returns (uint256) {
        return self.askTree.maximum();
    }

    function getMaxLimitExempt(address who) internal view returns (bool allowed) {
        bytes32 slot = keccak256(abi.encode(MAX_LIMIT_ALLOWLIST, who));

        // slither-disable-next-line assembly
        assembly {
            allowed := sload(slot)
        }
    }

    function getLimit(Book storage self, uint256 price, Side side) internal view returns (Limit storage) {
        return side == Side.BUY ? self.bidLimits[price] : self.askLimits[price];
    }

    function getNextBiggestPrice(Book storage self, uint256 price, Side side) internal view returns (uint256) {
        return side == Side.BUY ? self.bidTree.getNextBiggest(price) : self.askTree.getNextBiggest(price);
    }

    function getNextSmallestPrice(Book storage self, uint256 price, Side side) internal view returns (uint256) {
        return side == Side.BUY ? self.bidTree.getNextSmallest(price) : self.askTree.getNextSmallest(price);
    }

    function getTradedAmounts(
        Book storage self,
        uint256 makerBase,
        uint256 takerAmount,
        uint256 price,
        bool baseDenominated
    ) internal view returns (__TradeData__ memory tradeData) {
        uint256 lotSize = self.config.lotSize;

        uint256 takerBase = baseDenominated ? takerAmount : takerAmount.fullMulDiv(1e18, price);

        takerBase -= tradeData.baseTraded = makerBase.min(takerBase) / lotSize * lotSize;
        tradeData.quoteTraded = tradeData.baseTraded.fullMulDiv(price, 1e18);

        if (takerBase < lotSize) {
            // filledAmount is only used to decrease the taker order amount — doesn't represent traded position
            // this prevents FOK orders from reverting on dust from lots & rounding errors when converting
            // quote -> base -> quote in quote denominated orders
            tradeData.filledAmount = takerAmount;
        } else {
            tradeData.filledAmount = baseDenominated ? tradeData.baseTraded : tradeData.quoteTraded;
        }
    }

    function boundToLots(Book storage self, uint256 baseAmount) internal view returns (uint256) {
        uint256 lotSize = self.config.lotSize;

        return baseAmount / lotSize * lotSize;
    }

    function getPostableBaseAmount(Book storage self, uint256 baseAmount)
        internal
        view
        returns (uint256 postableBaseAmount)
    {
        postableBaseAmount = self.boundToLots(baseAmount);

        if (postableBaseAmount < StorageLib.loadBookSettings(self.config.asset).minLimitOrderAmountInBase) return 0;
    }

    function quoteBidInBase(Book storage self, uint256 baseAmount)
        internal
        view
        returns (uint256 quoteAmount, uint256 baseUsed)
    {
        uint256 bestAsk = self.getBestAsk();

        uint256 quoteFromLimit;
        uint256 baseFromLimit;
        while (baseAmount > 0) {
            if (bestAsk == type(uint256).max) break;

            (quoteFromLimit, baseFromLimit) = _getQuoteLimit(self, self.askLimits[bestAsk], bestAsk, baseAmount);

            quoteAmount += quoteFromLimit;
            baseUsed += baseFromLimit;
            baseAmount -= baseFromLimit;
            bestAsk = self.getNextBiggestPrice(bestAsk, Side.SELL);
        }
    }

    function quoteBidInQuote(Book storage self, uint256 quoteAmount)
        internal
        view
        returns (uint256 baseAmount, uint256 quoteUsed)
    {
        uint256 bestAsk = self.getBestAsk();

        uint256 baseFromLimit;
        uint256 quoteFromLimit;
        while (quoteAmount > 0) {
            if (bestAsk == type(uint256).max) break;

            (baseFromLimit, quoteFromLimit) = _getBaseLimit(self, self.askLimits[bestAsk], bestAsk, quoteAmount);

            baseAmount += baseFromLimit;
            quoteUsed += quoteFromLimit;
            quoteAmount -= quoteFromLimit;
            bestAsk = self.getNextBiggestPrice(bestAsk, Side.SELL);
        }
    }

    function quoteAskInBase(Book storage self, uint256 baseAmount)
        internal
        view
        returns (uint256 quoteAmount, uint256 baseUsed)
    {
        uint256 bestBid = self.getBestBid();

        uint256 quoteFromLimit;
        uint256 baseFromLimit;
        while (baseAmount > 0) {
            if (bestBid == 0) break;

            (quoteFromLimit, baseFromLimit) = _getQuoteLimit(self, self.bidLimits[bestBid], bestBid, baseAmount);

            quoteAmount += quoteFromLimit;
            baseUsed += baseFromLimit;
            baseAmount -= baseFromLimit;
            bestBid = self.getNextSmallestPrice(bestBid, Side.BUY);
        }
    }

    function quoteAskInQuote(Book storage self, uint256 quoteAmount)
        internal
        view
        returns (uint256 baseAmount, uint256 quoteUsed)
    {
        uint256 bestBid = self.getBestBid();

        uint256 baseFromLimit;
        uint256 quoteFromLimit;
        while (quoteAmount > 0) {
            if (bestBid == 0) break;

            (baseFromLimit, quoteFromLimit) = _getBaseLimit(self, self.bidLimits[bestBid], bestBid, quoteAmount);

            baseAmount += baseFromLimit;
            quoteUsed += quoteFromLimit;
            quoteAmount -= quoteFromLimit;
            bestBid = self.getNextSmallestPrice(bestBid, Side.BUY);
        }
    }

    function getNextOrders(Book storage self, OrderId startOrderId, uint256 numOrders)
        internal
        view
        returns (Order[] memory)
    {
        Order storage currentOrder = self.orders[startOrderId];
        currentOrder.assertExists();

        uint256 count = 0;
        Order[] memory orders = new Order[](numOrders);

        while (count < numOrders && !currentOrder.isNull()) {
            orders[count] = currentOrder;
            count++;

            if (currentOrder.nextOrderId.unwrap() != 0) {
                currentOrder = self.orders[currentOrder.nextOrderId];
            } else {
                uint256 nextPrice = self.getNextBiggestPrice(currentOrder.price, currentOrder.side);

                if (nextPrice == 0) break;

                Limit storage nextLimit = self.getLimit(nextPrice, currentOrder.side);

                currentOrder = self.orders[nextLimit.headOrder];
            }
        }

        return orders;
    }

    function toOrderId(Book storage self, address account, uint96 clientOrderId) internal returns (uint256 orderId) {
        if (clientOrderId == 0) return self.incrementOrderId();

        orderId = OrderIdLib.getOrderId(account, clientOrderId);

        self.assertUnusedOrderId(orderId);
    }

    /// @dev returns incremented orderId
    function incrementOrderId(Book storage self) internal returns (uint256) {
        return ++self.metadata.orderIdCounter;
    }

    function setMaxLimitExempt(address who, bool toggle) internal {
        bytes32 slot = keccak256(abi.encode(MAX_LIMIT_ALLOWLIST, who));

        // slither-disable-next-line assembly
        assembly {
            sstore(slot, toggle)
        }
    }

    function setMaxLimitsPerTx(Book storage self, uint8 newMax) internal {
        if (newMax == 0) revert InvalidMaxLimitsPerTx();

        StorageLib.loadBookSettings(self.config.asset).maxLimitsPerTx = newMax;
    }

    function setMinLimitOrderAmountInBase(Book storage self, uint256 newLimitOrderAmountInBase) internal {
        if (newLimitOrderAmountInBase < MIN_MIN_LIMIT_ORDER_AMOUNT_BASE) revert InvalidMinLimitOrderAmountInBase();

        StorageLib.loadBookSettings(self.config.asset).minLimitOrderAmountInBase = newLimitOrderAmountInBase;
    }

    function _getTransientLimitsPlaced() private view returns (uint8 limitsPlaced) {
        bytes32 slot = TRANSIENT_LIMITS_PLACED;

        // This solidity version does not support the `transient` identifier
        // slither-disable-next-line assembly
        assembly {
            limitsPlaced := tload(slot)
        }
    }

    function incrementLimitsPlaced(Book storage self, address account) internal {
        uint8 limitsPlaced = _getTransientLimitsPlaced();

        if (limitsPlaced == StorageLib.loadBookSettings(self.config.asset).maxLimitsPerTx) {
            if (getMaxLimitExempt(account)) return;
            revert LimitsPlacedExceedsMaxThisTx();
        }

        bytes32 slot = TRANSIENT_LIMITS_PLACED;

        // This solidity version does not support the `transient` identifier
        // slither-disable-next-line assembly
        assembly {
            tstore(slot, add(limitsPlaced, 1))
        }
    }

    function addOrderToBook(Book storage self, Order memory order) internal {
        if (order.reduceOnly) {
            StorageLib.loadMarket(self.config.asset).linkReduceOnlyOrder(
                order.owner, order.subaccount, order.id.unwrap(), self.config.bookType
            );
        }

        Limit storage limit = _updateBookPostOrder(self, order);
        _updateLimitPostOrder(self, limit, order);

        self.orders[order.id] = order;
    }

    function removeOrderFromBook(Book storage self, Order memory order) internal {
        if (order.reduceOnly) {
            StorageLib.loadMarket(self.config.asset).unlinkReduceOnlyOrder(
                order.owner, order.subaccount, order.id.unwrap(), self.config.bookType
            );
        }

        _updateLimitRemoveOrder(self, order);
        _updateBookRemoveOrder(self, order);
    }

    function _updateBookPostOrder(Book storage self, Order memory order) private returns (Limit storage limit) {
        if (order.side == Side.BUY) {
            limit = self.bidLimits[order.price];
            if (limit.numOrders == 0) self.bidTree.insert(order.price);
            self.metadata.numBids++;
            self.metadata.quoteOI += order.amount.fullMulDiv(order.price, 1e18);
        } else {
            limit = self.askLimits[order.price];
            if (limit.numOrders == 0) self.askTree.insert(order.price);
            self.metadata.numAsks++;
            self.metadata.baseOI += order.amount;
        }
    }

    function _updateLimitPostOrder(Book storage self, Limit storage limit, Order memory order) private {
        limit.numOrders++;

        if (limit.headOrder.unwrap() == 0) {
            limit.headOrder = order.id;
            limit.tailOrder = order.id;
        } else {
            Order storage tailOrder = self.orders[limit.tailOrder];
            tailOrder.nextOrderId = order.id;
            order.prevOrderId = tailOrder.id;
            limit.tailOrder = order.id;
        }
    }

    function _updateBookRemoveOrder(Book storage self, Order memory order) private {
        if (order.side == Side.BUY) {
            self.metadata.numBids--;

            self.metadata.quoteOI -= order.amount.fullMulDiv(order.price, 1e18);
        } else {
            self.metadata.numAsks--;

            self.metadata.baseOI -= order.amount;
        }

        delete self.orders[order.id];
    }

    function _updateLimitRemoveOrder(Book storage self, Order memory order) private {
        Limit storage limit = order.side == Side.BUY ? self.bidLimits[order.price] : self.askLimits[order.price];

        if (limit.numOrders == 1) {
            if (order.side == Side.BUY) {
                delete self.bidLimits[order.price];
                self.bidTree.remove(order.price);
            } else {
                delete self.askLimits[order.price];
                self.askTree.remove(order.price);
            }
            return;
        }

        limit.numOrders--;

        if (order.prevOrderId.unwrap() != 0) self.orders[order.prevOrderId].nextOrderId = order.nextOrderId;
        else limit.headOrder = order.nextOrderId;

        if (order.nextOrderId.unwrap() != 0) self.orders[order.nextOrderId].prevOrderId = order.prevOrderId;
        else limit.tailOrder = order.prevOrderId;
    }

    function _getQuoteLimit(Book storage self, Limit storage limit, uint256 price, uint256 baseAmount)
        private
        view
        returns (uint256 quoteAmount, uint256 baseUsed)
    {
        uint256 numOrders = limit.numOrders;
        OrderId orderId = limit.headOrder;

        uint256 fillAmount;
        for (uint256 i; i < numOrders; ++i) {
            if (baseAmount == 0) break;
            if (orderId.unwrap() == 0) break;

            fillAmount = self.orders[orderId].amount.min(baseAmount);

            quoteAmount += fillAmount.fullMulDiv(price, 1e18);
            baseAmount -= fillAmount;
            baseUsed += fillAmount;

            orderId = self.orders[orderId].nextOrderId;
        }
    }

    function _getBaseLimit(Book storage self, Limit storage limit, uint256 price, uint256 quoteAmount)
        private
        view
        returns (uint256 baseAmount, uint256 quoteUsed)
    {
        uint256 numOrders = limit.numOrders;
        OrderId orderId = limit.headOrder;

        uint256 fillAmount;
        for (uint256 i; i < numOrders; ++i) {
            if (quoteAmount == 0) break;
            if (orderId.unwrap() == 0) break;

            fillAmount = self.orders[orderId].amount.min(quoteAmount.fullMulDiv(1e18, price));

            baseAmount += fillAmount;
            quoteUsed += fillAmount.fullMulDiv(price, 1e18);
            quoteAmount -= fillAmount.fullMulDiv(price, 1e18);

            orderId = self.orders[orderId].nextOrderId;
        }
    }
}
