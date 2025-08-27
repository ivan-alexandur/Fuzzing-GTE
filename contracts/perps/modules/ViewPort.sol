// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {OwnableRoles} from "@solady/auth/OwnableRoles.sol";
import {EnumerableSetLib} from "@solady/utils/EnumerableSetLib.sol";
import {DynamicArrayLib} from "@solady/utils/DynamicArrayLib.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";

import {Status, BookType, Side} from "../types/Enums.sol";
import {PackedFeeRates} from "../types/PackedFeeRatesLib.sol";
import {Constants} from "../types/Constants.sol";
import {StorageLib} from "../types/StorageLib.sol";

import {IViewPort} from "../interfaces/IViewPort.sol";

import {ClearingHouse} from "../types/ClearingHouse.sol";
import {Market, MarketMetadata} from "../types/Market.sol";
import {FundingRateSettings} from "../types/FundingRateEngine.sol";
import {Book} from "../types/Book.sol";
import {Position} from "../types/Position.sol";
import {Order, OrderIdLib} from "../types/Order.sol";

abstract contract ViewPort is IViewPort, OwnableRoles {
    using EnumerableSetLib for EnumerableSetLib.Bytes32Set;
    using DynamicArrayLib for DynamicArrayLib.DynamicArray;
    using SafeCastLib for uint256;

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                ACCOUNT
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function getPosition(bytes32 asset, address account, uint256 subaccount)
        external
        view
        returns (Position memory position)
    {
        return StorageLib.loadMarket(asset).getPosition(account, subaccount);
    }

    function getPositionLeverage(bytes32 asset, address account, uint256 subaccount)
        external
        view
        returns (uint256 leverage)
    {
        return StorageLib.loadMarket(asset).getPositionLeverage(account, subaccount);
    }

    function getAssets(address account, uint256 subaccount) external view returns (bytes32[] memory positions) {
        return StorageLib.loadClearingHouse().assets[account][subaccount].values();
    }

    function getReduceOnlyOrders(bytes32 asset, address account, uint256 subaccount)
        external
        view
        returns (uint256[] memory orderIds)
    {
        return StorageLib.loadMarket(asset).reduceOnlyOrders[account][subaccount];
    }

    function getMarginBalance(address account, uint256 subaccount) external view returns (int256 marginBalance) {
        return StorageLib.loadCollateralManager().getMarginBalance(account, subaccount);
    }

    function getFreeCollateralBalance(address account) external view returns (uint256 collateralBalance) {
        return StorageLib.loadCollateralManager().getFreeCollateralBalance(account);
    }

    function getPendingFundingPayment(address account, uint256 subaccount)
        external
        view
        returns (int256 pendingFundingPayment)
    {
        return StorageLib.loadClearingHouse().getFundingPayment(account, subaccount);
    }

    function getOrderbookNotional(bytes32 asset, address account, uint256 subaccount)
        external
        view
        returns (uint256 orderbookNotional)
    {
        return StorageLib.loadMarket(asset).orderbookNotional[account][subaccount];
    }

    function getOrderbookCollateral(address account, uint256 subaccount)
        external
        view
        returns (uint256 orderbookCollateral)
    {
        ClearingHouse storage clearingHouse = StorageLib.loadClearingHouse();
        bytes32[] memory assets = clearingHouse.assets[account][subaccount].values();

        for (uint256 i; i < assets.length; ++i) {
            orderbookCollateral += clearingHouse.market[assets[i]].getOrderBookCollateral(account, subaccount);
        }
    }

    function getAccountValue(address account, uint256 subaccount) external view returns (int256 accountValue) {
        ClearingHouse storage clearingHouse = StorageLib.loadClearingHouse();

        (DynamicArrayLib.DynamicArray memory assets, Position[] memory positions, int256 margin) =
            clearingHouse.getAccountAndMargin(account, subaccount);

        int256 fundingPayment = clearingHouse.getFundingPayment(account, subaccount);
        int256 upnl = clearingHouse.getUpnl(assets, positions);

        return margin - fundingPayment + upnl;
    }

    function isLiquidatable(address account, uint256 subaccount) external view returns (bool liquidatable) {
        return StorageLib.loadClearingHouse().isLiquidatable(account, subaccount, BookType.STANDARD);
    }

    function isLiquidatableBackstop(address account, uint256 subaccount) external view returns (bool liquidatable) {
        return StorageLib.loadClearingHouse().isLiquidatable(account, subaccount, BookType.BACKSTOP);
    }

    function getMaintenanceMargin(bytes32 asset, uint256 positionAmount)
        external
        view
        returns (uint256 maintenanceMargin)
    {
        return StorageLib.loadMarket(asset).getMaintenanceMargin(positionAmount);
    }

    function getIntendedMarginAndUpnl(bytes32 asset, Position memory position)
        external
        view
        returns (uint256 intendedMargin, int256 upnl)
    {
        return StorageLib.loadMarket(asset).getIntendedMarginAndUpnl(position);
    }

    function getNextEmptySubaccount(address account) external view returns (uint256 subaccount) {
        ClearingHouse storage clearingHouse = StorageLib.loadClearingHouse();

        for (uint256 i = 1; i < type(uint256).max; ++i) {
            if (clearingHouse.assets[account][i].length() == 0) return i;
        }
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                ORDERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function getLimitOrder(bytes32 asset, uint256 orderId) external view returns (Order memory order) {
        return StorageLib.loadBook(asset).orders[OrderIdLib.wrap(orderId)];
    }

    function getLimitOrderBackstop(bytes32 asset, uint256 orderId) external view returns (Order memory order) {
        return StorageLib.loadBackstopBook(asset).orders[OrderIdLib.wrap(orderId)];
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               PROTOCOL
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function getCollateralAsset() external pure returns (address) {
        return Constants.USDC;
    }

    function getTakerFeeRates() external view returns (PackedFeeRates) {
        return StorageLib.loadFeeManager().takerFeeRates;
    }

    function getMakerFeeRates() external view returns (PackedFeeRates) {
        return StorageLib.loadFeeManager().makerFeeRates;
    }

    function getInsuranceFundBalance() external view returns (uint256 insuranceFundBalance) {
        return StorageLib.loadInsuranceFund().balance;
    }

    function isAdmin(address account) external view returns (bool) {
        return hasAllRoles(account, 7);
    }

    function getNonce() external view returns (uint256 nonce) {
        return StorageLib.loadNonce();
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                              MARKET DATA
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function getMarkPrice(bytes32 asset) external view returns (uint256 markPrice) {
        return StorageLib.loadMarket(asset).markPrice;
    }

    function getIndexPrice(bytes32 asset) external view returns (uint256 indexPrice) {
        return StorageLib.loadMarketMetadata(asset).indexPriceHistory.latest();
    }

    function getFundingRate(bytes32 asset) external view returns (int256 fundingRate) {
        return StorageLib.loadFundingRateEngine(asset).fundingRate;
    }

    function getCumulativeFunding(bytes32 asset) external view returns (int256 cumulativeFunding) {
        return StorageLib.loadFundingRateEngine(asset).cumulativeFundingIndex;
    }

    function getLastFundingTime(bytes32 asset) external view returns (uint256 lastFundingTime) {
        return StorageLib.loadFundingRateEngine(asset).lastFundingTime;
    }

    function getCurrentFundingInterval(bytes32 asset) external view returns (uint256) {
        return StorageLib.loadFundingRateEngine(asset).getFundingInterval(asset);
    }

    function getOpenInterest(bytes32 asset) external view returns (uint256 longOi, uint256 shortOi) {
        MarketMetadata storage metadata = StorageLib.loadMarketMetadata(asset);

        longOi = metadata.longOI;
        shortOi = metadata.shortOI;
    }

    function getOpenInterestBook(bytes32 asset) external view returns (uint256 baseOi, uint256 quoteOi) {
        Book storage book = StorageLib.loadBook(asset);

        baseOi = book.metadata.baseOI;
        quoteOi = book.metadata.quoteOI;
    }

    function getOpenInterestBackstopBook(bytes32 asset) external view returns (uint256 baseOi, uint256 quoteOi) {
        Book storage book = StorageLib.loadBackstopBook(asset);

        baseOi = book.metadata.baseOI;
        quoteOi = book.metadata.quoteOI;
    }

    function getNumBids(bytes32 asset) external view returns (uint256 numBids) {
        return StorageLib.loadBook(asset).metadata.numBids;
    }

    function getNumBidsBackstop(bytes32 asset) external view returns (uint256 numBids) {
        return StorageLib.loadBackstopBook(asset).metadata.numBids;
    }

    function getNumAsks(bytes32 asset) external view returns (uint256 numAsks) {
        return StorageLib.loadBook(asset).metadata.numAsks;
    }

    function getNumAsksBackstop(bytes32 asset) external view returns (uint256 numAsks) {
        return StorageLib.loadBackstopBook(asset).metadata.numAsks;
    }

    function getNextOrderId(bytes32 asset) external view returns (uint96 orderIdCounter) {
        return StorageLib.loadBook(asset).metadata.orderIdCounter + 1;
    }

    function getNextOrderIdBackstop(bytes32 asset) external view returns (uint96 orderIdCounter) {
        return StorageLib.loadBackstopBook(asset).metadata.orderIdCounter + 1;
    }

    function getMidPrice(bytes32 asset) external view returns (uint256 midPrice) {
        return StorageLib.loadMarket(asset).getMidPrice();
    }

    function quoteBookInBase(bytes32 asset, uint256 baseAmount, Side side)
        external
        view
        returns (uint256 quoteAmount, uint256 baseUsed)
    {
        if (side == Side.BUY) return StorageLib.loadBook(asset).quoteBidInBase(baseAmount);
        else return StorageLib.loadBook(asset).quoteAskInBase(baseAmount);
    }

    function quoteBookInQuote(bytes32 asset, uint256 quoteAmount, Side side)
        external
        view
        returns (uint256 baseAmount, uint256 quoteUsed)
    {
        if (side == Side.BUY) return StorageLib.loadBook(asset).quoteBidInQuote(quoteAmount);
        else return StorageLib.loadBook(asset).quoteAskInQuote(quoteAmount);
    }

    function quoteBackstopBookInBase(bytes32 asset, uint256 baseAmount, Side side)
        external
        view
        returns (uint256 quoteAmount, uint256 baseUsed)
    {
        if (side == Side.BUY) return StorageLib.loadBackstopBook(asset).quoteBidInBase(baseAmount);
        else return StorageLib.loadBackstopBook(asset).quoteAskInBase(baseAmount);
    }

    function quoteBackstopBookInQuote(bytes32 asset, uint256 quoteAmount, Side side)
        external
        view
        returns (uint256 baseAmount, uint256 quoteUsed)
    {
        if (side == Side.BUY) return StorageLib.loadBackstopBook(asset).quoteBidInQuote(quoteAmount);
        else return StorageLib.loadBackstopBook(asset).quoteAskInQuote(quoteAmount);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            MARKET SETTINGS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function getMarketStatus(bytes32 asset) external view returns (Status status) {
        return StorageLib.loadMarketSettings(asset).status;
    }

    function isCrossMarginEnabled(bytes32 asset) external view returns (bool crossMarginEnabled) {
        return StorageLib.loadMarketSettings(asset).crossMarginEnabled;
    }

    function getMaxLeverage(bytes32 asset) external view returns (uint256 maxLeverage) {
        return StorageLib.loadMarketSettings(asset).maxOpenLeverage;
    }

    function getMinMarginRatio(bytes32 asset) external view returns (uint256 minMarginRatio) {
        return StorageLib.loadMarket(asset).getMinMarginRatio(BookType.STANDARD);
    }

    function getMinMarginRatioBackstop(bytes32 asset) external view returns (uint256 minMarginRatio) {
        return StorageLib.loadMarket(asset).getMinMarginRatio(BookType.BACKSTOP);
    }

    function getLiquidationFeeRate(bytes32 asset) external view returns (uint256 liquidationFeeRate) {
        return StorageLib.loadMarketSettings(asset).liquidationFeeRate;
    }

    function getDivergenceCap(bytes32 asset) external view returns (uint256 divergenceCap) {
        return StorageLib.loadMarketSettings(asset).divergenceCap;
    }

    function getReduceOnlyCap(bytes32 asset) external view returns (uint256 reduceOnlyCap) {
        return StorageLib.loadMarketSettings(asset).reduceOnlyCap;
    }

    function getPartialLiquidationThreshold(bytes32 asset) external view returns (uint256 threshold) {
        return StorageLib.loadMarketSettings(asset).partialLiquidationThreshold;
    }

    function getPartialLiquidationRate(bytes32 asset) external view returns (uint256 rate) {
        return StorageLib.loadMarketSettings(asset).partialLiquidationRate;
    }

    function getFundingInterval(bytes32 asset) external view returns (uint256 fundingInterval) {
        return StorageLib.loadFundingRateSettings(asset).fundingInterval;
    }

    function getResetInterval(bytes32 asset) external view returns (uint256 resetInterval) {
        return StorageLib.loadFundingRateSettings(asset).resetInterval;
    }

    function getResetIterations(bytes32 asset) external view returns (uint256 resetIterations) {
        return StorageLib.loadFundingRateSettings(asset).resetIterations;
    }

    function getInterestRate(bytes32 asset) external view returns (int256 interestRate) {
        return StorageLib.loadFundingRateSettings(asset).interestRate;
    }

    function getFundingClamps(bytes32 asset) external view returns (uint256 innerClamp, uint256 outerClamp) {
        FundingRateSettings storage settings = StorageLib.loadFundingRateSettings(asset);
        return (settings.innerClamp, settings.outerClamp);
    }

    function getMaxNumOrders(bytes32 asset) external view returns (uint256 maxNumOrders) {
        return StorageLib.loadBookSettings(asset).maxNumOrders;
    }

    function getMaxLimitsPerTx(bytes32 asset) external view returns (uint8 maxLimitsPerTx) {
        return StorageLib.loadBookSettings(asset).maxLimitsPerTx;
    }

    function getMinLimitOrderAmountInBase(bytes32 asset) external view returns (uint256 minLimitOrderAmountInBase) {
        return StorageLib.loadBookSettings(asset).minLimitOrderAmountInBase;
    }

    function getTickSize(bytes32 asset) external view returns (uint256 tickSize) {
        return StorageLib.loadBookSettings(asset).tickSize;
    }

    function getLotSize(bytes32 asset) external view returns (uint256 lotSize) {
        return StorageLib.loadBook(asset).config.lotSize;
    }
}
