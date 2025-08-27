// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Side, Order, OrderId} from "./types/Order.sol";
import {MarketConfig, MarketSettings, Limit} from "./types/Book.sol";
import {MakerCredit} from "./types/TransientMakerData.sol";
import {ICLOBManager} from "./ICLOBManager.sol";

interface ICLOB {
    struct SettleParams {
        Side side;
        address taker;
        uint256 takerBaseAmount;
        uint256 takerQuoteAmount;
        address baseToken;
        address quoteToken;
        MakerCredit[] makerCredits;
    }

    enum TiF {
        // MAKER
        GTC, // good-till-cancelled
        MOC, // maker-or-cancel (post-only)
        // TAKER-ONLY
        FOK, // fill-or-kill
        IOC // immediate-or-cancel

    }

    struct PlaceOrderArgs {
        // metadata
        Side side; // bid / ask
        uint96 clientOrderId; // Optional user-defined id for makes
        // time / execution
        TiF tif; // time in force
        uint32 expiryTime; // optional auto-cancel time (only for GTC, MOC)
        // price
        uint256 limitPrice; // if 0, market order
        // size
        uint256 amount;
        bool baseDenominated; // which asset the amount denominates
    }

    struct PlaceOrderResult {
        address account;
        uint256 orderId;
        uint256 basePosted; // amount posted in base (for maker orders)
        int256 quoteTokenAmountTraded; // negative if outgoing, positive if incoming
        int256 baseTokenAmountTraded; // negative if outgoing, positive if incoming
        uint256 takerFee;
        bool wasMarketOrder; // true if market order (limitPrice = 0), false if limit order
    }

    enum CancelType {
        USER,
        EXPIRY,
        NON_COMPETITIVE
    }

    struct AmendArgs {
        uint256 orderId;
        uint256 amountInBase;
        uint256 price;
        uint32 cancelTimestamp;
        Side side;
    }

    struct CancelArgs {
        uint256[] orderIds;
    }

    function placeOrder(address account, PlaceOrderArgs calldata args) external returns (PlaceOrderResult memory);

    function amend(address account, AmendArgs memory args) external returns (int256 quoteDelta, int256 baseDelta);

    function cancel(address account, CancelArgs memory args) external returns (uint256, uint256); // quoteToken refunded, baseToken refunded

    // Token Amount Calculators
    function getQuoteTokenAmount(uint256 price, uint256 amountInBaseLots) external view returns (uint256);

    function getBaseTokenAmount(uint256 price, uint256 amountInBaseLots) external view returns (uint256);

    // Getters

    function maxNumOrdersPerSide() external view returns (uint256);

    function gteRouter() external view returns (address);

    function getQuoteToken() external view returns (address);

    function getBaseToken() external view returns (address);

    function getMarketConfig() external view returns (MarketConfig memory);

    function getTickSize() external view returns (uint256);

    function getLotSizeInBase() external view returns (uint256);

    function getOpenInterest() external view returns (uint256, uint256);

    function getOrder(uint256 orderId) external view returns (Order memory);

    function getTOB() external view returns (uint256, uint256);

    function getLimit(uint256 price, Side side) external view returns (Limit memory);

    function getNumBids() external view returns (uint256);

    function getNumAsks() external view returns (uint256);

    function getNextBiggestPrice(uint256 price, Side side) external view returns (uint256);

    function getNextSmallestPrice(uint256 price, Side side) external view returns (uint256);

    function getNextOrders(uint256 startOrderId, uint256 numOrders) external view returns (Order[] memory);

    function getNextOrderId() external view returns (uint256);

    function factory() external view returns (ICLOBManager);

    function getOrdersPaginated(uint256 startPrice, Side side, uint256 pageSize)
        external
        view
        returns (Order[] memory result, Order memory nextOrder);

    function getOrdersPaginated(OrderId startOrderId, uint256 pageSize)
        external
        view
        returns (Order[] memory result, Order memory nextOrder);

    function setLotSizeInBase(uint256 newLotSizeInBase) external;
    function setMaxLimitsPerTx(uint8 newMaxLimits) external;
    function setTickSize(uint256 newTickSize) external;
    function setMinLimitOrderAmountInBase(uint256 newMinLimitOrderAmountInBase) external;

    function adminCancelExpiredOrders(OrderId[] calldata ids, Side side) external returns (bool[] memory);
}
