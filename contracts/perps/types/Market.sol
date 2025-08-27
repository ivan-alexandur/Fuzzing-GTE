// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {DynamicArrayLib} from "@solady/utils/DynamicArrayLib.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";

import {Status, BookType, TiF, Side} from "./Enums.sol";
import {
    PlaceOrderArgs,
    PlaceOrderResult,
    AmendLimitOrderArgs,
    Condition,
    FundingPaymentResult,
    LiquidateData,
    BackstopLiquidateData,
    OIDelta
} from "./Structs.sol";

import {CLOBLib} from "./CLOBLib.sol";
import {StorageLib} from "./StorageLib.sol";

import {Position} from "./Position.sol";
import {FundingRateEngine, FundingRateSettings} from "./FundingRateEngine.sol";
import {PriceHistory} from "./PriceHistory.sol";

struct MarketSettings {
    Status status;
    bool crossMarginEnabled; // true if there can be more than 1 position open per subaccount
    uint256 maxOpenLeverage;
    uint256 maintenanceMarginRatio;
    uint256 liquidationFeeRate;
    uint256 divergenceCap;
    uint256 reduceOnlyCap;
    uint256 partialLiquidationThreshold; // position min position value to partial liquidate
    uint256 partialLiquidationRate; // percentage of position to partially liquidate
}

struct MarketMetadata {
    uint256 longOI;
    uint256 shortOI;
    PriceHistory markPriceHistory;
    PriceHistory indexPriceHistory;
    PriceHistory impactPriceHistory;
    PriceHistory basisSpreadHistory;
}

struct Market {
    bytes32 asset;
    uint256 markPrice;
    mapping(address account => mapping(uint256 subaccount => Position)) position;
    mapping(address account => mapping(uint256 subaccount => uint256[])) reduceOnlyOrders;
    mapping(address account => mapping(uint256 subaccount => uint256[])) reduceOnlyOrdersBackstopBook;
    mapping(address account => mapping(uint256 subaccount => uint256)) orderbookNotional;
}

using MarketLib for Market global;
using MarketLib for MarketSettings global;

library MarketLib {
    using FixedPointMathLib for *;
    using SafeCastLib for *;
    using DynamicArrayLib for uint256[];

    event PositionLiquidated(
        bytes32 asset,
        address indexed account,
        uint256 indexed subaccount,
        int256 quoteDelta,
        int256 baseDelta,
        int256 rpnl,
        Position position,
        BookType liquidationType,
        uint256 nonce
    );

    event FundingSettled(bytes32 indexed asset, int256 funding, int256 cumulativeFunding, uint256 openInterest, uint256 nonce);

    event MarkPriceUpdated(bytes32 indexed asset, uint256 markPrice, uint256 p1, uint256 p2, uint256 p3, uint256 nonce);

    error MarketInactive();
    error InvalidReduceOnlyDenomination();
    error MaxLeverageExceeded();
    error LeverageInvalid();
    error InvalidBackstopOrder();
    error ZeroTrade();
    error ZeroOrder();
    error NotReduceOnly();
    error ReduceOnlyCapExceeded();
    error BackstopOrderNotPostOnly();
    error PartialBackstopLiquidation();
    error InvalidDeleveragePair();

    modifier onlyActiveMarket(bytes32 asset) {
        assertActive(asset);
        _;
    }

    function init(
        Market storage self,
        bytes32 asset,
        MarketSettings memory marketSettings,
        FundingRateSettings memory fundingSettings,
        uint256 initialPrice
    ) internal {
        self.asset = asset;
        self.markPrice = initialPrice;

        StorageLib.loadMarketSettings(asset).init(marketSettings);
        StorageLib.loadFundingRateSettings(asset).init(fundingSettings);
        StorageLib.loadFundingRateEngine(asset).lastFundingTime = block.timestamp;
    }

    function init(MarketSettings storage settings, MarketSettings memory initSettings) internal {
        settings.status = initSettings.status;
        settings.crossMarginEnabled = initSettings.crossMarginEnabled;
        settings.maxOpenLeverage = initSettings.maxOpenLeverage;
        settings.maintenanceMarginRatio = initSettings.maintenanceMarginRatio;
        settings.liquidationFeeRate = initSettings.liquidationFeeRate;
        settings.divergenceCap = initSettings.divergenceCap;
        settings.reduceOnlyCap = initSettings.reduceOnlyCap;
        settings.partialLiquidationThreshold = initSettings.partialLiquidationThreshold;
        settings.partialLiquidationRate = initSettings.partialLiquidationRate;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                             STANDARD BOOK
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function placeOrder(Market storage self, address account, PlaceOrderArgs calldata args, BookType bookType)
        internal
        onlyActiveMarket(args.asset)
        returns (PlaceOrderResult memory result)
    {
        // sanity check: non liquidation taker order can't be placed on the backstop book
        if (bookType == BookType.BACKSTOP && args.tif != TiF.MOC) revert InvalidBackstopOrder();

        if (args.reduceOnly) {
            _validateReduceOnlyOrder({
                self: self,
                account: account,
                subaccount: args.subaccount,
                orderAmount: args.amount,
                side: args.side,
                baseDenominated: args.baseDenominated
            });
        }

        return CLOBLib.placeOrder(account, args, bookType);
    }

    function amendLimitOrder(Market storage self, address account, AmendLimitOrderArgs calldata args, BookType bookType)
        internal
        onlyActiveMarket(args.asset)
        returns (int256 collateralDelta)
    {
        if (args.reduceOnly) _validateReduceOnlyOrder(self, account, args.subaccount, args.baseAmount, args.side, true);

        return CLOBLib.amend(account, args, bookType);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                              LIQUIDATIONS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function liquidate(
        Market storage self,
        address account,
        uint256 subaccount,
        Side side,
        uint256 amount,
        BookType bookType
    ) internal returns (PlaceOrderResult memory result) {
        if (bookType == BookType.STANDARD) amount = _getLiquidationAmount(self, amount);

        result = CLOBLib.placeOrder(
            account,
            PlaceOrderArgs({
                subaccount: subaccount,
                asset: self.asset,
                side: side,
                limitPrice: 0, // max slippage
                amount: amount,
                baseDenominated: true,
                tif: TiF.IOC,
                expiryTime: 0,
                clientOrderId: 0,
                reduceOnly: true
            }),
            bookType
        );
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                              SETTERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function settleFunding(Market storage self) internal {
        bytes32 asset = self.asset;

        FundingRateEngine storage fundingRateEngine = StorageLib.loadFundingRateEngine(asset);
        MarketMetadata storage metadata = StorageLib.loadMarketMetadata(asset);

        uint256 interval = fundingRateEngine.getTimeSinceLastFunding();

        (int256 funding, int256 cumulativeFunding) = fundingRateEngine.settleFunding({
            asset: asset,
            markTwap: metadata.markPriceHistory.twap(interval),
            indexTwap: metadata.indexPriceHistory.twap(interval)
        });

        emit FundingSettled({
            asset: asset,
            funding: funding,
            cumulativeFunding: cumulativeFunding,
            openInterest: metadata.longOI,
            nonce: StorageLib.incNonce()
        });
    }

    function setMarkPrice(Market storage self, uint256 indexPrice) internal returns (uint256 markPrice) {
        MarketMetadata storage metadata = StorageLib.loadMarketMetadata(self.asset);

        _cacheBasisSpread(self, indexPrice);
        _cacheImpactPrice(self);

        uint256 p1 = self.getFundingRateComponent(indexPrice);
        uint256 p2 = (indexPrice.toInt256() + self.getBasisSpreadEMA()).toUint256();
        uint256 p3 = self.getImpactPriceTwap();

        self.markPrice = markPrice = _getMedian(p1, p2, p3);

        metadata.markPriceHistory.snapshot(markPrice);
        metadata.indexPriceHistory.snapshot(indexPrice);

        emit MarkPriceUpdated({
            asset: self.asset,
            markPrice: markPrice,
            p1: p1,
            p2: p2,
            p3: p3,
            nonce: StorageLib.incNonce()
        });
    }

    function realizeFundingPayment(bytes32 asset, Position memory position)
        internal
        view
        returns (int256 fundingPayment)
    {
        return position.realizeFundingPayment(StorageLib.loadFundingRateEngine(asset).getCumulativeFunding());
    }

    function updateOI(bytes32 asset, OIDelta memory oiDelta) internal {
        MarketMetadata storage metadata = StorageLib.loadMarketMetadata(asset);

        if (oiDelta.long > 0) metadata.longOI += oiDelta.long.abs();
        else if (oiDelta.long < 0) metadata.longOI -= oiDelta.long.abs();

        if (oiDelta.short > 0) metadata.shortOI += oiDelta.short.abs();
        else if (oiDelta.short < 0) metadata.shortOI -= oiDelta.short.abs();
    }

    function setPosition(Market storage self, address account, uint256 subaccount, Position memory position) internal {
        self.position[account][subaccount] = position;
    }

    function cancelCloseOrders(Market storage self, address account, uint256 subaccount) internal {
        _cancelReduceOnlyOrdersStandard(self, account, subaccount);
        _cancelReduceOnlyOrdersBackstop(self, account, subaccount);
    }

    function linkReduceOnlyOrder(
        Market storage self,
        address account,
        uint256 subaccount,
        uint256 orderId,
        BookType bookType
    ) internal {
        if (bookType == BookType.STANDARD) _linkReduceOnlyStandard(self, account, subaccount, orderId);
        else _linkReduceOnlyBackstop(self, account, subaccount, orderId);
    }

    function unlinkReduceOnlyOrder(
        Market storage self,
        address account,
        uint256 subaccount,
        uint256 orderId,
        BookType bookType
    ) internal {
        if (bookType == BookType.STANDARD) _unlinkIdFromArray(self.reduceOnlyOrders[account][subaccount], orderId);
        else _unlinkIdFromArray(self.reduceOnlyOrdersBackstopBook[account][subaccount], orderId);
    }

    function updateOrderbookNotional(Market storage self, address account, uint256 subaccount, int256 notionalDelta)
        internal
    {
        if (notionalDelta > 0) self.orderbookNotional[account][subaccount] += notionalDelta.abs();
        else if (notionalDelta < 0) self.orderbookNotional[account][subaccount] -= notionalDelta.abs();
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                GETTERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function getUpnl(Market storage self, address account, uint256 subaccount) internal view returns (int256 upnl) {
        Position storage position = self.position[account][subaccount];

        uint256 currentNotional = position.amount.fullMulDiv(self.markPrice, 1e18);

        return _calcUpnl(position.isLong, position.openNotional, currentNotional);
    }

    function getUpnlAndMinMargin(Market storage self, Position memory position, BookType bookType)
        internal
        view
        returns (int256 upnl, uint256 minMargin)
    {
        if (position.amount == 0) return (0, 0);

        uint256 currentNotional = position.amount.fullMulDiv(self.markPrice, 1e18);

        upnl = _calcUpnl(position.isLong, position.openNotional, currentNotional);
        minMargin = currentNotional.fullMulDiv(self.getMinMarginRatio(bookType), 1e18);
    }

    function getNotionalValue(Market storage self, Position memory position) internal view returns (uint256 notional) {
        return position.amount.fullMulDiv(self.markPrice, 1e18);
    }

    function getIntendedMargin(Market storage self, Position memory position)
        internal
        view
        returns (uint256 intendedMargin)
    {
        if (position.amount == 0) return 0;

        uint256 currentNotional = position.amount.fullMulDiv(self.markPrice, 1e18);

        intendedMargin = currentNotional.fullMulDiv(1e18, position.leverage);
    }

    function getMinOpenMargin(Market storage self, uint256 positionAmount)
        internal
        view
        returns (uint256 minOpenMargin)
    {
        uint256 positionNotional = positionAmount.fullMulDiv(self.markPrice, 1e18);

        minOpenMargin = positionNotional.fullMulDiv(1e18, StorageLib.loadMarketSettings(self.asset).maxOpenLeverage);
    }

    function getIntendedMarginAndUpnl(Market storage self, Position memory position)
        internal
        view
        returns (uint256 intendedMargin, int256 upnl)
    {
        if (position.amount == 0) return (0, 0);

        uint256 currentNotional = position.amount.fullMulDiv(self.markPrice, 1e18);

        upnl = _calcUpnl(position.isLong, position.openNotional, currentNotional);
        intendedMargin = currentNotional.fullMulDiv(1e18, position.leverage);
    }

    function getUpnl(Market storage self, Position memory position) internal view returns (int256 upnl) {
        uint256 currentNotional = position.amount.fullMulDiv(self.markPrice, 1e18);

        return _calcUpnl(position.isLong, position.openNotional, currentNotional);
    }

    function getPosition(Market storage self, address account, uint256 subaccount)
        internal
        view
        returns (Position memory position)
    {
        position = self.position[account][subaccount];

        if (position.leverage == 0) position.leverage = 1e18; // default leverage
    }

    function getPositionLeverage(Market storage self, address account, uint256 subaccount)
        internal
        view
        returns (uint256 leverage)
    {
        leverage = self.position[account][subaccount].leverage;

        if (leverage == 0) leverage = 1e18; // default leverage
    }

    function getMaintenanceMargin(Market storage self, uint256 positionAmount) internal view returns (uint256) {
        return positionAmount.fullMulDiv(self.markPrice, 1e18).fullMulDiv(
            StorageLib.loadMarketSettings(self.asset).maintenanceMarginRatio, 1e18
        );
    }

    function getFundingPayment(Market storage self, address account, uint256 subaccount)
        internal
        view
        returns (int256 fundingPayment)
    {
        Position storage position = self.position[account][subaccount];
        return position.realizeFundingPayment(StorageLib.loadFundingRateEngine(self.asset).getCumulativeFunding());
    }

    function getMaxDivergingBidPrice(Market storage self) internal view returns (uint256) {
        uint256 mark = self.markPrice;
        uint256 maxDivergence = mark.fullMulDiv(StorageLib.loadMarketSettings(self.asset).divergenceCap, 1e18);

        return mark - maxDivergence;
    }

    function getMaxDivergingAskPrice(Market storage self) internal view returns (uint256) {
        uint256 mark = self.markPrice;
        uint256 maxDivergence = mark.fullMulDiv(StorageLib.loadMarketSettings(self.asset).divergenceCap, 1e18);

        return mark + maxDivergence;
    }

    function getImpactPrice(Market storage self, uint256 impactNotional) internal view returns (uint256 impactPrice) {
        (uint256 baseAmount, uint256 quoteUsed) = StorageLib.loadBook(self.asset).quoteBidInQuote(impactNotional);

        if (impactNotional > quoteUsed) baseAmount += (impactNotional - quoteUsed).fullMulDiv(1e18, type(uint256).max);

        uint256 impactBid = baseAmount == 0 ? 0 : impactNotional.fullMulDiv(1e18, baseAmount);

        (baseAmount, quoteUsed) = StorageLib.loadBook(self.asset).quoteAskInQuote(impactNotional);

        if (impactNotional > quoteUsed) baseAmount += (impactNotional - quoteUsed).fullMulDiv(1e18, 1);

        uint256 impactAsk = impactNotional.fullMulDiv(1e18, baseAmount);

        return (impactBid + impactAsk) / 2;
    }

    function getMidPrice(Market storage self) internal view returns (uint256 midPrice) {
        bytes32 asset = self.asset;

        uint256 bestBid = StorageLib.loadBook(asset).getBestBid();
        uint256 bestAsk = StorageLib.loadBook(asset).getBestAsk();

        if (bestAsk == type(uint256).max || bestBid == 0) return 0;

        return (bestBid + bestAsk) / 2;
    }

    function getFundingRateComponent(Market storage self, uint256 indexPrice)
        internal
        view
        returns (uint256 fundingRateComponent)
    {
        bytes32 asset = self.asset;
        FundingRateEngine storage fundingRateEngine = StorageLib.loadFundingRateEngine(asset);

        return indexPrice.fullMulDiv(
            1e18
                + fundingRateEngine.fundingRate.abs().fullMulDiv(
                    block.timestamp - fundingRateEngine.lastFundingTime, fundingRateEngine.getFundingInterval(asset)
                ),
            1e18
        );
    }

    function getBasisSpreadEMA(Market storage self) internal view returns (int256 basisSpreadEMA) {
        return StorageLib.loadMarketMetadata(self.asset).basisSpreadHistory.ema(15 minutes);
    }

    function getImpactPriceTwap(Market storage self) internal view returns (uint256 impactPriceTwap) {
        bytes32 asset = self.asset;
        return StorageLib.loadMarketMetadata(asset).impactPriceHistory.twap(
            StorageLib.loadFundingRateEngine(asset).getFundingInterval(asset)
        );
    }

    /// @dev The subaccount's margin that is locked up in makes
    function getOrderBookCollateral(Market storage self, address account, uint256 subaccount)
        internal
        view
        returns (uint256 orderbookCollateral)
    {
        return
            self.orderbookNotional[account][subaccount].fullMulDiv(1e18, self.getPositionLeverage(account, subaccount));
    }

    function getMinMarginRatio(Market storage self, BookType liquidationType) internal view returns (uint256) {
        uint256 denominator = liquidationType == BookType.STANDARD ? 1 : 3;

        return StorageLib.loadMarketSettings(self.asset).maintenanceMarginRatio / denominator;
    }

    function isTPSLConditionMet(Market storage self, Side side, Condition calldata condition)
        internal
        view
        returns (bool met)
    {
        uint256 mark = self.markPrice;

        if (side == Side.SELL) {
            if (condition.stopLoss ? mark <= condition.triggerPrice : mark >= condition.triggerPrice) return true;
        } else {
            if (condition.stopLoss ? mark >= condition.triggerPrice : mark <= condition.triggerPrice) return true;
        }
    }

    function exists(Market storage self) internal view returns (bool) {
        return self.asset != bytes32(0);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               ASSERTIONS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function assertMaxLeverage(bytes32 asset, uint256 leverage) internal view {
        if (leverage < 1e18) revert LeverageInvalid(); // leverage must be at least 1x
        if (leverage > StorageLib.loadMarketSettings(asset).maxOpenLeverage) revert MaxLeverageExceeded();
    }

    function assertActive(bytes32 asset) internal view {
        if (StorageLib.loadMarketSettings(asset).status != Status.ACTIVE) revert MarketInactive();
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _validateReduceOnlyOrder(
        Market storage self,
        address account,
        uint256 subaccount,
        uint256 orderAmount,
        Side side,
        bool baseDenominated
    ) internal view {
        // not possible to validate reduce only on quote denominated orders
        if (!baseDenominated) revert InvalidReduceOnlyDenomination();

        Position storage position = self.position[account][subaccount];

        if (position.amount < orderAmount) revert NotReduceOnly();

        if (side == Side.BUY && position.isLong) revert NotReduceOnly();
        else if (side == Side.SELL && !position.isLong) revert NotReduceOnly();
    }

    function _linkReduceOnlyStandard(Market storage self, address account, uint256 subaccount, uint256 orderId)
        private
    {
        if (
            self.reduceOnlyOrders[account][subaccount].length >= StorageLib.loadMarketSettings(self.asset).reduceOnlyCap
        ) revert ReduceOnlyCapExceeded();

        if (self.reduceOnlyOrders[account][subaccount].contains(orderId)) return;
        self.reduceOnlyOrders[account][subaccount].push(orderId);
    }

    function _linkReduceOnlyBackstop(Market storage self, address account, uint256 subaccount, uint256 orderId)
        private
    {
        if (
            self.reduceOnlyOrdersBackstopBook[account][subaccount].length
                >= StorageLib.loadMarketSettings(self.asset).reduceOnlyCap
        ) revert ReduceOnlyCapExceeded();

        if (self.reduceOnlyOrdersBackstopBook[account][subaccount].contains(orderId)) return;
        self.reduceOnlyOrdersBackstopBook[account][subaccount].push(orderId);
    }

    function _getLiquidationAmount(Market storage self, uint256 positionAmount) internal view returns (uint256) {
        if (
            positionAmount.fullMulDiv(self.markPrice, 1e18)
                < StorageLib.loadMarketSettings(self.asset).partialLiquidationThreshold
        ) return positionAmount;

        return positionAmount.fullMulDiv(StorageLib.loadMarketSettings(self.asset).partialLiquidationRate, 1e18);
    }

    function _cancelReduceOnlyOrdersStandard(Market storage self, address account, uint256 subaccount) private {
        uint256[] memory orderIds = self.reduceOnlyOrders[account][subaccount];

        if (orderIds.length == 0) return;

        CLOBLib.cancel(self.asset, account, subaccount, orderIds, BookType.STANDARD);

        delete self.reduceOnlyOrders[account][subaccount];
    }

    function _cancelReduceOnlyOrdersBackstop(Market storage self, address account, uint256 subaccount) private {
        uint256[] memory orderIds = self.reduceOnlyOrdersBackstopBook[account][subaccount];

        if (orderIds.length == 0) return;

        CLOBLib.cancel(self.asset, account, subaccount, orderIds, BookType.BACKSTOP);

        delete self.reduceOnlyOrdersBackstopBook[account][subaccount];
    }

    function _calcUpnl(bool isLong, uint256 openNotional, uint256 currentNotional) private pure returns (int256 upnl) {
        if (isLong) upnl = currentNotional.toInt256() - openNotional.toInt256();
        else upnl = openNotional.toInt256() - currentNotional.toInt256();
    }

    function _unlinkIdFromArray(uint256[] storage ids, uint256 id) private {
        uint256 index = ids.indexOf(id);

        if (index == type(uint256).max) return;

        ids[index] = ids[ids.length - 1];

        ids.pop();
    }

    function _isInProfit(uint256 markPrice, uint256 openPrice, bool isLong) private pure returns (bool inProfit) {
        if (isLong) return markPrice >= openPrice;
        else return markPrice <= openPrice;
    }

    function _cacheBasisSpread(Market storage self, uint256 indexPrice) private {
        uint256 midPrice = self.getMidPrice();

        if (midPrice == 0) return; // no valid mid price available

        int256 basisSpread = midPrice.toInt256() - indexPrice.toInt256();

        StorageLib.loadMarketMetadata(self.asset).basisSpreadHistory.snapshotBasisSpread(basisSpread);
    }

    function _cacheImpactPrice(Market storage self) private returns (uint256 impactPrice) {
        // impact notional is 500 * max leverage
        uint256 impactNotional =
            uint256(500e18).fullMulDiv(StorageLib.loadMarketSettings(self.asset).maxOpenLeverage, 1e18);

        impactPrice = self.getImpactPrice(impactNotional);

        StorageLib.loadMarketMetadata(self.asset).impactPriceHistory.snapshot(impactPrice);
    }

    function _getMedian(uint256 a, uint256 b, uint256 c) private pure returns (uint256 median) {
        uint256 maxAB = a.max(b);
        uint256 minAB = a.min(b);

        return minAB.max(maxAB.min(c));
    }
}
