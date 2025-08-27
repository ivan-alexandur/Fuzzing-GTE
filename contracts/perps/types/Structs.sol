// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Side, TiF, Status, TradeType, BookType} from "./Enums.sol";
import {Position} from "./Position.sol";

/*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                        MARKET CREATION
▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

struct MarketParams {
    uint256 maxOpenLeverage; // 1e18 = 1x
    uint256 maintenanceMarginRatio; // 0.5e18 = 50%
    uint256 liquidationFeeRate; // .01e18 = 1%
    uint256 divergenceCap; // 0.1e18 = trades can occur at max 10% price from mark
    uint256 reduceOnlyCap; // max number of reduce only orders per subaccount
    uint256 partialLiquidationThreshold; // 20_000e18 = positions worth $20k and over will be partially liquidated
    uint256 partialLiquidationRate; // 0.2e18 = 20% of position will be liquidated on partial liquidation
    bool crossMarginEnabled; // true if there can be more than 1 position open per subaccount
    uint256 fundingInterval;
    uint256 resetInterval;
    uint256 resetIterations;
    uint256 innerClamp;
    uint256 outerClamp;
    int256 interestRate;
    uint256 maxNumOrders; // max number of orders per book
    uint8 maxLimitsPerTx; // max number of limit orders per transaction
    uint256 minLimitOrderAmountInBase; // minimum amount in base for limit orders
    uint256 tickSize; // 0.01e18 = 1 cent
    uint256 lotSize;
    uint256 initialPrice; // initial price of the market in quote token
}

/*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            ORDER POST
▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

struct PlaceOrderArgs {
    // account
    uint256 subaccount;
    // metadata
    bytes32 asset;
    Side side;
    // price
    uint256 limitPrice; // if 0, market order (system internally sets 0 ask or +inf bid)
    // size
    uint256 amount;
    bool baseDenominated; // true: amount in base; false: amount in quote
    // time / execution
    TiF tif; // time in force
    uint32 expiryTime; // optional auto-cancel time (only for GTC, MOC)
    // custom id tag
    uint96 clientOrderId;
    bool reduceOnly; // true if order is reduce-only
}

struct AmendLimitOrderArgs {
    bytes32 asset;
    uint256 subaccount;
    uint256 orderId;
    uint256 baseAmount;
    uint256 price;
    uint32 expiryTime;
    Side side;
    bool reduceOnly;
}

struct Condition {
    uint256 triggerPrice;
    bool stopLoss;
}

struct SignData {
    bytes sig;
    uint256 nonce;
    uint256 expiry;
}

/*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                        EXTERNAL RESULT
▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

struct PlaceOrderResult {
    uint256 orderId;
    uint256 basePosted; // base posted on the book
    uint256 quoteTraded;
    uint256 baseTraded;
}

/*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                        INTERNAL HELPERS
▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

struct MakerFillResult {
    bytes32 asset;
    BookType bookType;
    uint256 orderId;
    address maker;
    uint256 subaccount;
    Side side;
    uint256 quoteAmountTraded;
    uint256 baseAmountTraded;
    bool reduceOnly;
}

struct PositionUpdateResult {
    int256 marginDelta;
    int256 rpnl;
    bool sideClose;
    OIDelta oiDelta;
}

struct __TradeData__ {
    uint256 baseTraded;
    uint256 quoteTraded;
    uint256 filledAmount;
}

struct FundingPaymentResult {
    int256 fundingPayment;
    int256 marginDelta;
    uint256 debt;
}

struct TradeExecutedData {
    bytes32 asset;
    address account;
    uint256 subaccount;
    Side side;
    uint256 quoteTraded;
    uint256 baseTraded;
    Position position;
    int256 margin;
    int256 rpnl;
    uint256 fee;
    TradeType tradeType;
}

struct LiquidateData {
    uint256 fee;
    int256 rpnl;
    int256 marginDelta;
    uint256 debt;
}

struct BackstopLiquidateData {
    int256 rpnl;
    int256 marginDelta;
    uint256 debt;
}

struct MakerSettleData {
    address account;
    uint256 subaccount;
    int256 marginDelta;
    int256 collateralDelta;
    uint256 debt;
    uint256 makerFee;
    bool close;
}

struct LiquidateeSettleData {
    address account;
    uint256 subaccount;
    int256 marginDelta;
    uint256 debt;
    uint256 fee;
    bool fullLiquidation;
}

struct LiquidatorData {
    address liquidator;
    uint256 volume; // in quote
}

struct TakerSettleData {
    address account;
    uint256 subaccount;
    int256 marginDelta;
    int256 collateralDelta;
    uint256 debt;
    uint256 takerFee;
    bool close;
}

struct Account {
    address account;
    uint256 subaccount;
}

struct DeleveragePair {
    Account maker; // the underwater account in a deleverage
    Account taker; // the in profit account in a deleverage
}

struct OIDelta {
    int256 long;
    int256 short;
}
