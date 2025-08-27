// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {EnumerableSetLib} from "@solady/utils/EnumerableSetLib.sol";
import {DynamicArrayLib} from "@solady/utils/DynamicArrayLib.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";

import {IGTL} from "../interfaces/IGTL.sol";

import {Constants} from "./Constants.sol";
import {Side, Status, BookType, TradeType} from "./Enums.sol";
import {
    PlaceOrderArgs,
    PlaceOrderResult,
    MakerFillResult,
    PositionUpdateResult,
    FundingPaymentResult,
    OIDelta,
    TradeExecutedData,
    MakerSettleData,
    TakerSettleData
} from "./Structs.sol";

import {BackstopLiquidatorDataLib} from "./BackstopLiquidatorDataLib.sol";

import {StorageLib} from "./StorageLib.sol";

import {Market, MarketLib} from "./Market.sol";
import {Book} from "./Book.sol";
import {InsuranceFund} from "./InsuranceFund.sol";
import {CollateralManager} from "./CollateralManager.sol";
import {FeeManager} from "./FeeManager.sol";
import {Position} from "./Position.sol";

struct ClearingHouse {
    bool active;
    mapping(bytes32 asset => Market) market;
    mapping(address account => mapping(uint256 subaccount => EnumerableSetLib.Bytes32Set)) assets;
    mapping(address account => mapping(address operator => bool)) approvedOperator;
    mapping(address liquidator => uint256) liquidatorPoints;
    mapping(address account => mapping(uint256 nonce => bool)) nonceUsed;
}

using ClearingHouseLib for ClearingHouse global;

// @todo review: for maker: tests on refund for reversing & refund on less margin needed to open

library ClearingHouseLib {
    using FixedPointMathLib for *;
    using SafeCastLib for *;
    using EnumerableSetLib for EnumerableSetLib.Bytes32Set;
    using DynamicArrayLib for *;

    error CrossMarginIsDisabled();
    error Liquidatable();
    error NotLiquidatable();
    error MarginRequirementUnmet();

    struct __ProcessMakerFillCache__ {
        DynamicArrayLib.DynamicArray assets;
        Position[] positions;
        int256 fundingPayment;
        uint256 orderValue;
        PositionUpdateResult positionResult;
        int256 margin;
        bool isNewPosition;
        uint256 fee;
    }

    struct __ProcessTakerFillCache__ {
        DynamicArrayLib.DynamicArray assets;
        Position[] positions;
        PositionUpdateResult positionResult;
        int256 fundingPayment;
        int256 margin;
        uint256 takerFee;
    }

    struct __RebalanceCollateralCache__ {
        uint256 intendedMargin;
        int256 upnl;
        int256 equity;
        int256 overCollateralization;
    }

    struct __FillParams__ {
        bytes32 asset;
        address account;
        uint256 subaccount;
        Side side;
        uint256 quoteAmount;
        uint256 baseAmount;
        uint256 collateralPosted; // Only used for limit orders
    }

    struct __LiquidatableCheckCache__ {
        int256 upnl;
        uint256 minMargin;
        int256 totalUpnl;
        uint256 totalMinMargin;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                              ORDER PLACE
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function placeOrder(ClearingHouse storage self, address account, PlaceOrderArgs calldata args, BookType bookType)
        internal
        returns (PlaceOrderResult memory orderResult)
    {
        Market storage market = self.market[args.asset];

        orderResult = market.placeOrder(account, args, bookType);

        uint256 collateralPosted;
        if (orderResult.basePosted > 0 && !args.reduceOnly) {
            collateralPosted = _getCollateral(
                orderResult.basePosted, args.limitPrice, market.getPositionLeverage(account, args.subaccount)
            );
        }

        if (orderResult.baseTraded == 0) {
            StorageLib.loadCollateralManager().handleCollateralDelta({
                account: account,
                collateralDelta: collateralPosted.toInt256()
            });

            return orderResult;
        }

        _processTakerFill(
            self,
            __FillParams__({
                asset: args.asset,
                account: account,
                subaccount: args.subaccount,
                side: args.side,
                quoteAmount: orderResult.quoteTraded,
                baseAmount: orderResult.baseTraded,
                collateralPosted: collateralPosted
            })
        );
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                              MAKER FILL
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @notice processes a maker fill during CLOBLib._matchIncomingOrder()
    /// @dev if unfillable, must return true while emitting no events and saving nothing to storage
    /// @dev must not revert
    function processMakerFill(ClearingHouse storage self, MakerFillResult memory makerResult)
        internal
        returns (bool unfillable)
    {
        __ProcessMakerFillCache__ memory cache;

        // load assets
        cache.assets = self.getAssets(makerResult.maker, makerResult.subaccount);

        // check if new position
        cache.isNewPosition = !cache.assets.contains(makerResult.asset);

        // if new position, check if asset can be added to account
        // if not, return true to indicate unfillable
        if (cache.isNewPosition) {
            if (!_assetCanBeAddedToAccount(cache.assets, makerResult.asset)) return true;
            // add asset to account
            cache.assets.p(makerResult.asset);
        }

        // load positions
        cache.positions =
            _getPositions(self, cache.assets, makerResult.maker, makerResult.subaccount, cache.isNewPosition);

        // get funding payment & update position.lastCumulativeFunding
        cache.fundingPayment = realizeFundingPayment(cache.assets, cache.positions);

        // get index of traded position
        uint256 positionIdx = cache.assets.indexOf(makerResult.asset);

        // process the trade
        cache.positionResult = cache.positions[positionIdx].processTrade({
            side: makerResult.side,
            quoteTraded: makerResult.quoteAmountTraded,
            baseTraded: makerResult.baseAmountTraded
        });

        cache.fee = makerResult.bookType == BookType.STANDARD
            ? StorageLib.loadFeeManager().getMakerFee(makerResult.maker, makerResult.quoteAmountTraded)
            : 0;

        cache.margin = StorageLib.loadCollateralManager().getMarginBalance(makerResult.maker, makerResult.subaccount);

        // settle rpnl on margin
        cache.margin += cache.positionResult.rpnl - cache.fundingPayment - cache.fee.toInt256();

        // rebalance account
        (cache.margin, cache.positionResult.marginDelta) = self.rebalanceAccount({
            assets: cache.assets,
            positions: cache.positions,
            margin: cache.margin,
            marginDelta: cache.positionResult.marginDelta
        });

        cache.orderValue = makerResult.reduceOnly
            ? 0
            : makerResult.quoteAmountTraded.fullMulDiv(1e18, cache.positions[positionIdx].leverage);

        // check liquidatability
        if (self.isLiquidatable(cache.assets, cache.positions, cache.margin, BookType.STANDARD)) return true;

        if (makerResult.bookType == BookType.BACKSTOP) {
            BackstopLiquidatorDataLib.addLiquidatorVolume(makerResult.maker, makerResult.quoteAmountTraded);
        }

        StorageLib.loadInsuranceFund().pay(cache.fee);

        // settle fill & subtract margin posted from amount owed
        StorageLib.loadCollateralManager().settleFill({
            account: makerResult.maker,
            subaccount: makerResult.subaccount,
            margin: cache.margin,
            marginDelta: cache.positionResult.marginDelta - cache.orderValue.toInt256()
        });

        // unlink reduce only order from account so storage isn't deleted before this function returns to CLOBLib
        if (cache.positionResult.sideClose && makerResult.reduceOnly) {
            self.market[makerResult.asset].unlinkReduceOnlyOrder(
                makerResult.maker, makerResult.subaccount, makerResult.orderId, makerResult.bookType
            );
        }

        self.updateAccount({
            account: makerResult.maker,
            subaccount: makerResult.subaccount,
            assets: cache.assets,
            positions: cache.positions,
            tradedAsset: makerResult.asset,
            positionIdx: positionIdx,
            oiDelta: cache.positionResult.oiDelta,
            sideClose: cache.positionResult.sideClose
        });
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function setAssets(
        ClearingHouse storage self,
        address account,
        uint256 subaccount,
        uint256 newLength,
        bytes32 asset
    ) internal {
        uint256 oldLength = self.assets[account][subaccount].length();

        if (oldLength == newLength) return;

        if (oldLength < newLength) self.assets[account][subaccount].add(asset);
        else self.assets[account][subaccount].remove(asset);

        if (account == Constants.GTL) {
            if (oldLength == 0) IGTL(Constants.GTL).addSubaccount(subaccount);
            else if (newLength == 0) IGTL(Constants.GTL).removeSubaccount(subaccount);
        }
    }

    function setPositions(
        ClearingHouse storage self,
        bytes32 tradedAsset,
        address account,
        uint256 subaccount,
        DynamicArrayLib.DynamicArray memory assets,
        Position[] memory positions
    ) internal {
        uint256 length = assets.length();

        for (uint256 i; i < length; ++i) {
            if (assets.getBytes32(i) == tradedAsset) {
                self.market[assets.getBytes32(i)].setPosition(account, subaccount, positions[i]);
            } else {
                self.market[assets.getBytes32(i)].position[account][subaccount].lastCumulativeFunding =
                    positions[i].lastCumulativeFunding;
            }
        }
    }

    function rebalanceAccount(
        ClearingHouse storage self,
        DynamicArrayLib.DynamicArray memory assets,
        Position[] memory positions,
        int256 margin,
        int256 marginDelta
    ) internal view returns (int256 finalMargin, int256 finalMarginDelta) {
        if (marginDelta >= 0) {
            return self.rebalanceOpen({assets: assets, positions: positions, margin: margin, marginDelta: marginDelta});
        } else {
            return self.rebalanceClose({assets: assets, positions: positions, margin: margin, marginDelta: marginDelta});
        }
    }

    function rebalanceOpen(
        ClearingHouse storage self,
        DynamicArrayLib.DynamicArray memory assets,
        Position[] memory positions,
        int256 margin,
        int256 marginDelta
    ) internal view returns (int256 finalMargin, int256 finalMarginDelta) {
        (uint256 intendedMargin, int256 upnl) = _getIntendedMarginAndUpnl(self, assets, positions);

        int256 equity = margin + upnl;

        // finalMarginDelta = MIN(marginDelta, MAX(intendedMargin - equity, 0))
        // marginDelta on an open is (openedNotional / leverage)
        finalMarginDelta = marginDelta.min((intendedMargin.toInt256() - equity).max(0));

        finalMargin = margin + finalMarginDelta;
    }

    /// @notice on close accounts should receive MAX(closed open notional / leverage, amount left over after meeting intended margin)
    ///         meaning closed margin subsidizes -pnl
    function rebalanceClose(
        ClearingHouse storage self,
        DynamicArrayLib.DynamicArray memory assets,
        Position[] memory positions,
        int256 margin,
        int256 marginDelta
    ) internal view returns (int256 finalMargin, int256 finalMarginDelta) {
        (uint256 intendedMargin, int256 upnl) = _getIntendedMarginAndUpnl(self, assets, positions);

        // full close
        if (intendedMargin == 0) {
            if (margin < 0) return (margin, 0);
            else return (0, -margin);
        }

        int256 equity = margin + upnl;

        // finalMarginDelta = MAX(marginDelta, MIN(intendedMargin - equity, 0))
        // marginDelta on a decrease is -(closedOpenNotional / leverage), where
        // closedOpenNotional = position.openNotional * closedAmount / position.amount
        finalMarginDelta = marginDelta.max((intendedMargin.toInt256() - equity).min(0));

        finalMargin = margin + finalMarginDelta;
    }

    function updateAccount(
        ClearingHouse storage self,
        address account,
        uint256 subaccount,
        DynamicArrayLib.DynamicArray memory assets,
        Position[] memory positions,
        bytes32 tradedAsset,
        uint256 positionIdx,
        OIDelta memory oiDelta,
        bool sideClose
    ) internal {
        self.setPositions(tradedAsset, account, subaccount, assets, positions);

        if (positions[positionIdx].amount == 0) _movePop(assets, tradedAsset);

        self.setAssets(account, subaccount, assets.length(), tradedAsset);

        MarketLib.updateOI(tradedAsset, oiDelta);

        if (sideClose) self.market[tradedAsset].cancelCloseOrders(account, subaccount);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               GETTERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function getAssets(ClearingHouse storage self, address account, uint256 subaccount)
        internal
        view
        returns (DynamicArrayLib.DynamicArray memory assets)
    {
        return self.assets[account][subaccount].values().wrap();
    }

    function getAccount(ClearingHouse storage self, address account, uint256 subaccount)
        internal
        view
        returns (DynamicArrayLib.DynamicArray memory assets, Position[] memory positions)
    {
        assets = self.assets[account][subaccount].values().wrap();
        positions = _getPositions(self, assets, account, subaccount, false);
    }

    function getAccountAndMargin(ClearingHouse storage self, address account, uint256 subaccount)
        internal
        view
        returns (DynamicArrayLib.DynamicArray memory assets, Position[] memory positions, int256 margin)
    {
        (assets, positions) = self.getAccount(account, subaccount);
        margin = StorageLib.loadCollateralManager().getMarginBalance(account, subaccount);
    }

    function getUpnl(
        ClearingHouse storage self,
        DynamicArrayLib.DynamicArray memory assets,
        Position[] memory positions
    ) internal view returns (int256 upnl) {
        uint256 length = assets.length();

        for (uint256 i; i < length; ++i) {
            upnl += self.market[assets.getBytes32(i)].getUpnl(positions[i]);
        }
    }

    function getIntendedMargin(
        ClearingHouse storage self,
        DynamicArrayLib.DynamicArray memory assets,
        Position[] memory positions
    ) internal view returns (uint256 intendedMargin) {
        uint256 length = assets.length();

        for (uint256 i; i < length; ++i) {
            intendedMargin += self.market[assets.getBytes32(i)].getIntendedMargin(positions[i]);
        }
    }

    /// @notice returns margin prorated based on the asset's notional value
    function getProratedMargin(
        ClearingHouse storage self,
        DynamicArrayLib.DynamicArray memory assets,
        Position[] memory positions,
        bytes32 asset,
        int256 margin
    ) internal view returns (int256 proratedMargin) {
        uint256 length = assets.length();

        uint256 notional;
        uint256 assetNotional;
        uint256 totalNotional;
        for (uint256 i; i < length; ++i) {
            notional = self.market[assets.getBytes32(i)].getNotionalValue(positions[i]);
            totalNotional += notional;

            if (assets.getBytes32(i) == asset) assetNotional = notional;
        }

        return _prorateMargin(margin, assetNotional, totalNotional);
    }

    function realizeFundingPayment(DynamicArrayLib.DynamicArray memory assets, Position[] memory positions)
        internal
        view
        returns (int256 fundingPayment)
    {
        uint256 length = assets.length();

        for (uint256 i; i < length; ++i) {
            fundingPayment += MarketLib.realizeFundingPayment(assets.getBytes32(i), positions[i]);
        }
    }

    function getNotionalAccountValue(
        ClearingHouse storage self,
        DynamicArrayLib.DynamicArray memory assets,
        Position[] memory positions
    ) internal view returns (uint256 totalNotional) {
        uint256 length = assets.length();

        for (uint256 i; i < length; ++i) {
            totalNotional += self.market[assets.getBytes32(i)].getNotionalValue(positions[i]);
        }
    }

    function getFundingPayment(ClearingHouse storage self, address account, uint256 subaccount)
        internal
        view
        returns (int256 fundingPayment)
    {
        bytes32[] memory assets = self.assets[account][subaccount].values();

        for (uint256 i; i < assets.length; ++i) {
            fundingPayment += self.market[assets[i]].getFundingPayment(account, subaccount);
        }
    }

    function isLiquidatable(ClearingHouse storage self, address account, uint256 subaccount, BookType bookType)
        internal
        view
        returns (bool liquidatable)
    {
        (DynamicArrayLib.DynamicArray memory assets, Position[] memory positions, int256 margin) =
            self.getAccountAndMargin(account, subaccount);

        int256 fundingPayment = self.getFundingPayment(account, subaccount);

        return self.isLiquidatable(assets, positions, margin - fundingPayment, bookType);
    }

    function isLiquidatable(
        ClearingHouse storage self,
        DynamicArrayLib.DynamicArray memory assets,
        Position[] memory positions,
        int256 margin,
        BookType bookType
    ) internal view returns (bool liquidatable) {
        __LiquidatableCheckCache__ memory cache;
        for (uint256 i; i < assets.length(); ++i) {
            (cache.upnl, cache.minMargin) =
                self.market[assets.getBytes32(i)].getUpnlAndMinMargin(positions[i], bookType);

            cache.totalUpnl += cache.upnl;
            cache.totalMinMargin += cache.minMargin;
        }

        // account close w/ bad debt
        if (cache.totalMinMargin == 0 && margin < 0) return true;

        return (margin + cache.totalUpnl) < cache.totalMinMargin.toInt256();
    }

    function isOpenMarginRequirementMet(
        ClearingHouse storage self,
        DynamicArrayLib.DynamicArray memory assets,
        Position[] memory positions,
        int256 margin
    ) internal view returns (bool met) {
        uint256 minOpenMargin;
        int256 upnl;
        for (uint256 i; i < positions.length; ++i) {
            minOpenMargin += self.market[assets.getBytes32(i)].getMinOpenMargin(positions[i].amount);
            upnl += self.market[assets.getBytes32(i)].getUpnl(positions[i]);
        }

        return margin + upnl >= minOpenMargin.toInt256();
    }

    function hasBadDebt(
        ClearingHouse storage self,
        DynamicArrayLib.DynamicArray memory assets,
        Position[] memory positions,
        int256 margin
    ) internal view returns (bool badDebt) {
        int256 upnl;
        for (uint256 i; i < positions.length; ++i) {
            upnl += self.market[assets.getBytes32(i)].getUpnl(positions[i]);
        }

        return margin + upnl < 0;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            PRIVATE HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _getCollateral(uint256 baseAmount, uint256 price, uint256 leverage)
        private
        pure
        returns (uint256 collateral)
    {
        collateral = baseAmount.fullMulDiv(price, 1e18).fullMulDiv(1e18, leverage);
    }

    function _isClosing(uint256 positionAmount, bool isLong, Side side) internal pure returns (bool closing) {
        if (positionAmount == 0) return false;

        if (isLong) return side == Side.SELL;
        else return side == Side.BUY;
    }

    function _prorateMargin(int256 margin, uint256 assetNotional, uint256 totalNotional)
        internal
        pure
        returns (int256 proratedMargin)
    {
        if (totalNotional == 0) return 0;

        proratedMargin = margin.abs().fullMulDiv(assetNotional, totalNotional).toInt256();

        if (margin < 0) proratedMargin = -proratedMargin;
    }

    function _processTakerFill(ClearingHouse storage self, __FillParams__ memory params) internal {
        __ProcessTakerFillCache__ memory cache;

        // load assets
        cache.assets = self.assets[params.account][params.subaccount].values().wrap();

        // check if new position
        bool isNewPosition = !cache.assets.contains(params.asset);

        // if new position, check if asset can be added to account
        // if not, revert
        if (isNewPosition) {
            if (!_assetCanBeAddedToAccount(cache.assets, params.asset)) revert CrossMarginIsDisabled();
            // add asset to account
            cache.assets.p(params.asset);
        }

        // load positions
        cache.positions = _getPositions(self, cache.assets, params.account, params.subaccount, isNewPosition);

        // get funding payment
        cache.fundingPayment = realizeFundingPayment(cache.assets, cache.positions);

        // get index of traded position
        uint256 positionIdx = cache.assets.indexOf(params.asset);

        // process the trade
        cache.positionResult = cache.positions[positionIdx].processTrade({
            side: params.side,
            quoteTraded: params.quoteAmount,
            baseTraded: params.baseAmount
        });

        cache.takerFee = StorageLib.loadFeeManager().getTakerFee(params.account, params.quoteAmount);

        cache.margin = StorageLib.loadCollateralManager().getMarginBalance(params.account, params.subaccount);

        // settle rpnl on margin
        cache.margin += cache.positionResult.rpnl - cache.fundingPayment - cache.takerFee.toInt256();

        // rebalance account
        (cache.margin, cache.positionResult.marginDelta) = self.rebalanceAccount({
            assets: cache.assets,
            positions: cache.positions,
            margin: cache.margin,
            marginDelta: cache.positionResult.marginDelta
        });

        // check liquidatability
        self.assertNotLiquidatable(cache.assets, cache.positions, cache.margin);

        StorageLib.loadInsuranceFund().pay(cache.takerFee);

        StorageLib.loadCollateralManager().settleFill(
            params.account,
            params.subaccount,
            cache.margin,
            cache.positionResult.marginDelta + params.collateralPosted.toInt256()
        );

        self.updateAccount({
            account: params.account,
            subaccount: params.subaccount,
            assets: cache.assets,
            positions: cache.positions,
            tradedAsset: params.asset,
            positionIdx: positionIdx,
            oiDelta: cache.positionResult.oiDelta,
            sideClose: cache.positionResult.sideClose
        });
    }

    function _getIntendedMarginAndUpnl(
        ClearingHouse storage self,
        DynamicArrayLib.DynamicArray memory assets,
        Position[] memory positions
    ) internal view returns (uint256 totalIntendedMargin, int256 totalUpnl) {
        uint256 length = assets.length();

        uint256 intendedMargin;
        int256 upnl;
        for (uint256 i; i < length; ++i) {
            (intendedMargin, upnl) = self.market[assets.getBytes32(i)].getIntendedMarginAndUpnl(positions[i]);

            totalIntendedMargin += intendedMargin;
            totalUpnl += upnl;
        }
    }

    function _getPositions(
        ClearingHouse storage self,
        DynamicArrayLib.DynamicArray memory assets,
        address account,
        uint256 subaccount,
        bool newPosition
    ) internal view returns (Position[] memory positions) {
        uint256 length = assets.length();

        if (length == 0) return positions;

        positions = new Position[](length);

        for (uint256 i; i < length - 1; ++i) {
            positions[i] = self.market[assets.getBytes32(i)].getPosition(account, subaccount);
        }

        if (newPosition) {
            positions[length - 1].leverage =
                self.market[assets.getBytes32(length - 1)].getPositionLeverage(account, subaccount);
        } else {
            positions[length - 1] = self.market[assets.getBytes32(length - 1)].getPosition(account, subaccount);
        }
    }

    function _assetCanBeAddedToAccount(DynamicArrayLib.DynamicArray memory assets, bytes32 asset)
        private
        view
        returns (bool canBeAdded)
    {
        uint256 numPositions = assets.length();

        // check incoming asset
        if (numPositions == 0) return true;
        if (assets.contains(asset)) return true;
        if (!StorageLib.loadMarketSettings(asset).crossMarginEnabled) return false;

        // check existing assets
        for (uint256 i; i < numPositions; ++i) {
            if (!StorageLib.loadMarketSettings(assets.getBytes32(i)).crossMarginEnabled) return false;
        }

        return true;
    }

    function _getDeltas(Side side, uint256 quoteTraded, uint256 baseTraded)
        private
        pure
        returns (int256 quoteDelta, int256 baseDelta)
    {
        if (side == Side.BUY) {
            quoteDelta = -quoteTraded.toInt256();
            baseDelta = baseTraded.toInt256();
        } else {
            quoteDelta = quoteTraded.toInt256();
            baseDelta = -baseTraded.toInt256();
        }
    }

    function _movePop(DynamicArrayLib.DynamicArray memory array, bytes32 asset) private pure {
        uint256 index = array.indexOf(asset);

        if (index == type(uint256).max) return;

        array.set(index, asset);
        array.pop();
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               ASSERTIONS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function assertNotLiquidatable(
        ClearingHouse storage self,
        DynamicArrayLib.DynamicArray memory assets,
        Position[] memory positions,
        int256 margin
    ) internal view {
        if (self.isLiquidatable(assets, positions, margin, BookType.STANDARD)) revert Liquidatable();
    }

    function assertLiquidatable(
        ClearingHouse storage self,
        DynamicArrayLib.DynamicArray memory assets,
        Position[] memory positions,
        int256 margin,
        BookType bookType
    ) internal view {
        if (!self.isLiquidatable(assets, positions, margin, bookType)) revert NotLiquidatable();
    }

    function assertPostWithdrawalMarginRequired(
        ClearingHouse storage self,
        DynamicArrayLib.DynamicArray memory assets,
        Position[] memory positions,
        int256 margin
    ) internal view {
        if (margin < 0) revert MarginRequirementUnmet();

        (uint256 intendedMargin, int256 upnl) = _getIntendedMarginAndUpnl(self, assets, positions);
        uint256 totalNotional = self.getNotionalAccountValue(assets, positions);

        intendedMargin = intendedMargin.max(totalNotional / 10);

        if (margin + upnl < intendedMargin.toInt256()) revert MarginRequirementUnmet();
    }

    /// @notice asserts min open margin requirement is met after margin updates
    function assertOpenMarginRequired(
        ClearingHouse storage self,
        DynamicArrayLib.DynamicArray memory assets,
        Position[] memory positions,
        int256 margin
    ) internal view {
        if (!self.isOpenMarginRequirementMet(assets, positions, margin)) revert MarginRequirementUnmet();
    }
}
