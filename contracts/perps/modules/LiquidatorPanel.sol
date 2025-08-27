// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {OwnableRoles} from "@solady/auth/OwnableRoles.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {DynamicArrayLib} from "@solady/utils/DynamicArrayLib.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";
import {EnumerableSetLib} from "@solady/utils/EnumerableSetLib.sol";
import {Initializable} from "@solady/utils/Initializable.sol";
import {SignatureCheckerLib} from "@solady/utils/SignatureCheckerLib.sol";

import {Status, Side, TradeType, FeeTier, BookType} from "../types/Enums.sol";
import {
    MarketParams,
    PlaceOrderResult,
    PositionUpdateResult,
    LiquidateData,
    BackstopLiquidateData,
    TradeExecutedData,
    DeleveragePair,
    LiquidatorData,
    Condition,
    OIDelta,
    SignData,
    FundingPaymentResult,
    LiquidateeSettleData,
    Account
} from "../types/Structs.sol";
import {Constants} from "../types/Constants.sol";

import {BackstopLiquidatorDataLib} from "../types/BackstopLiquidatorDataLib.sol";
import {StorageLib} from "../types/StorageLib.sol";
import {CLOBLib} from "../types/CLOBLib.sol";
import {ClearingHouse, ClearingHouseLib} from "../types/ClearingHouse.sol";
import {Market, MarketSettings} from "../types/Market.sol";
import {FundingRateSettings} from "../types/FundingRateEngine.sol";
import {Position} from "../types/Position.sol";
import {Book, BookSettings} from "../types/Book.sol";

contract LiquidatorPanel is OwnableRoles {
    using FixedPointMathLib for *;
    using SafeCastLib for *;
    using DynamicArrayLib for *;

    error MarketNotDelisted();
    error ProtocolInactive();
    error InvalidDeleveragePair();
    error InvalidLiquidation();
    error InvalidBackstopLiquidation();

    enum LiquidationType {
        LIQUIDATEE,
        BACKSTOP_LIQUIDATEE,
        DELIST,
        DELEVERAGE_MAKER, // maker is underwater
        DELEVERAGE_TAKER
    }

    event Liquidation( // negative is bad debt
        bytes32 indexed asset,
        address indexed account,
        uint256 indexed subaccount,
        int256 baseDelta,
        int256 quoteDelta,
        int256 rpnl,
        int256 margin,
        int256 fee,
        LiquidationType liquidationType,
        uint256 nonce
    );

    struct __LiquidateParams__ {
        address account;
        uint256 subaccount;
        bytes32 asset;
        Position position;
        Side side;
        BookType bookType;
    }

    struct __InternalLiquidateCache__ {
        DynamicArrayLib.DynamicArray assets;
        Position[] positions;
        int256 margin;
        uint256 positionIdx;
        Side side;
        PlaceOrderResult fillResult;
        PositionUpdateResult positionResult;
        uint256 maintenanceOrProratedMargin;
    }

    struct __DelistCache__ {
        DynamicArrayLib.DynamicArray assets;
        Position[] positions;
        int256 fundingPayment;
        Side side;
        uint256 baseTraded;
        uint256 quoteTraded;
        PositionUpdateResult positionResult;
        int256 margin;
        int256 fee;
    }

    struct __DeleveragePairCache__ {
        DynamicArrayLib.DynamicArray makerAssets;
        DynamicArrayLib.DynamicArray takerAssets;
        Position[] makerPositions;
        Position[] takerPositions;
        int256 makerFundingPayment;
        int256 takerFundingPayment;
        int256 makerMargin;
        int256 takerMargin;
        uint256 baseAmount;
        uint256 quoteAmount;
    }

    struct __DeleverageValidationParams__ {
        bytes32 asset;
        DynamicArrayLib.DynamicArray makerAssets;
        DynamicArrayLib.DynamicArray takerAssets;
        Position[] makerPositions;
        Position[] takerPositions;
        uint256 makerPositionIdx;
        uint256 takerPositionIdx;
        int256 makerMargin;
        int256 takerMargin;
    }

    struct __DeleverageParams__ {
        address account;
        uint256 subaccount;
        bytes32 asset;
        DynamicArrayLib.DynamicArray assets;
        Position[] positions;
        uint256 positionIdx;
        uint256 baseTraded;
        uint256 quoteTraded;
        int256 margin;
        LiquidationType deleverageType;
    }

    modifier onlyLiquidator() {
        _checkRolesOrOwner(Constants.ADMIN_ROLE | Constants.LIQUIDATOR_ROLE);
        _;
    }

    modifier onlyBackstopLiquidator() {
        _checkRolesOrOwner(Constants.ADMIN_ROLE | Constants.BACKSTOP_LIQUIDATOR_ROLE);
        _;
    }

    modifier onlyActiveProtocol() virtual {
        if (!StorageLib.loadClearingHouse().active) revert ProtocolInactive();
        _;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                              LIQUIDATIONS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function liquidate(bytes32 asset, address account, uint256 subaccount) external onlyLiquidator onlyActiveProtocol {
        ClearingHouse storage clearingHouse = StorageLib.loadClearingHouse();

        __InternalLiquidateCache__ memory cache = _liquidate({
            clearingHouse: clearingHouse,
            asset: asset,
            account: account,
            subaccount: subaccount,
            bookType: BookType.STANDARD
        });

        int256 fee = StorageLib.loadMarketSettings(asset).liquidationFeeRate.fullMulDiv(
            cache.fillResult.quoteTraded, 1e18
        ).toInt256();

        // settle rpnl and fee on margin
        cache.margin += cache.positionResult.rpnl - fee;

        (cache.margin, cache.positionResult.marginDelta) = clearingHouse.rebalanceClose({
            assets: cache.assets,
            positions: cache.positions,
            margin: cache.margin,
            marginDelta: cache.positionResult.marginDelta
        });

        bool fullClose = cache.positions[cache.positionIdx].amount == 0 && cache.positions.length == 1;

        // account close above water
        if (fullClose && cache.positionResult.marginDelta < 0) {
            // below maintenance margin
            if (cache.positionResult.marginDelta.abs() < cache.maintenanceOrProratedMargin) {
                fee -= cache.positionResult.marginDelta;
                delete cache.positionResult.marginDelta;
            }
            // account close under water
        } else if (fullClose && cache.margin < 0) {
            fee += cache.margin;

            delete cache.margin;
        }

        _emitLiquidationEvent({
            asset: asset,
            account: account,
            subaccount: subaccount,
            side: cache.side,
            quoteTraded: cache.fillResult.quoteTraded,
            baseTraded: cache.fillResult.baseTraded,
            rpnl: cache.positionResult.rpnl,
            margin: cache.margin,
            fee: fee,
            liquidationType: LiquidationType.LIQUIDATEE
        });

        if (fee > 0) StorageLib.loadInsuranceFund().pay(fee.abs());
        else StorageLib.loadInsuranceFund().claim(fee.abs());

        StorageLib.loadCollateralManager().settleFill(
            account, subaccount, cache.margin, cache.positionResult.marginDelta
        );

        clearingHouse.updateAccount({
            account: account,
            subaccount: subaccount,
            assets: cache.assets,
            positions: cache.positions,
            tradedAsset: asset,
            positionIdx: cache.positionIdx,
            oiDelta: cache.positionResult.oiDelta,
            sideClose: cache.positionResult.sideClose
        });
    }

    function backstopLiquidate(bytes32 asset, address account, uint256 subaccount)
        external
        onlyBackstopLiquidator
        onlyActiveProtocol
    {
        ClearingHouse storage clearingHouse = StorageLib.loadClearingHouse();

        __InternalLiquidateCache__ memory cache = _liquidate({
            clearingHouse: clearingHouse,
            asset: asset,
            account: account,
            subaccount: subaccount,
            bookType: BookType.BACKSTOP
        });

        int256 proratedMargin = cache.maintenanceOrProratedMargin.toInt256();

        cache.margin -= proratedMargin;

        proratedMargin += cache.positionResult.rpnl;

        if (proratedMargin < 0) {
            cache.margin += proratedMargin;
            delete proratedMargin;
        }

        int256 fee = _settleBackstopLiquidation(clearingHouse, asset, proratedMargin.toUint256()).toInt256();

        // realize bad debt if underwater and full close
        if (cache.margin < 0 && cache.positions.length == 1) {
            fee += cache.margin;
            delete cache.margin;
        }

        _emitLiquidationEvent({
            asset: asset,
            account: account,
            subaccount: subaccount,
            side: cache.side,
            quoteTraded: cache.fillResult.quoteTraded,
            baseTraded: cache.fillResult.baseTraded,
            rpnl: cache.positionResult.rpnl,
            margin: cache.margin,
            fee: fee,
            liquidationType: LiquidationType.BACKSTOP_LIQUIDATEE
        });

        if (fee > 0) StorageLib.loadInsuranceFund().pay(fee.abs());
        else StorageLib.loadInsuranceFund().claim(fee.abs());

        StorageLib.loadCollateralManager().settleFill(account, subaccount, cache.margin, 0);

        clearingHouse.updateAccount({
            account: account,
            subaccount: subaccount,
            assets: cache.assets,
            positions: cache.positions,
            tradedAsset: asset,
            positionIdx: cache.positionIdx,
            oiDelta: cache.positionResult.oiDelta,
            sideClose: cache.positionResult.sideClose
        });
    }

    function deleverage(bytes32 asset, DeleveragePair[] calldata pairs) external onlyLiquidator onlyActiveProtocol {
        ClearingHouse storage clearingHouse = StorageLib.loadClearingHouse();

        for (uint256 i; i < pairs.length; ++i) {
            _deleveragePair(clearingHouse, asset, pairs[i]);
        }
    }

    function delistClose(bytes32 asset, Account[] calldata accounts) external onlyLiquidator onlyActiveProtocol {
        ClearingHouse storage clearingHouse = StorageLib.loadClearingHouse();
        Market storage market = clearingHouse.market[asset];

        if (StorageLib.loadMarketSettings(asset).status != Status.DELISTED) revert MarketNotDelisted();

        for (uint256 i; i < accounts.length; ++i) {
            _delistClose(clearingHouse, market, asset, accounts[i]);
        }
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _delistClose(
        ClearingHouse storage clearingHouse,
        Market storage market,
        bytes32 asset,
        Account calldata account
    ) internal {
        __DelistCache__ memory cache;

        (cache.assets, cache.positions, cache.margin) =
            clearingHouse.getAccountAndMargin(account.account, account.subaccount);

        uint256 positionIdx = cache.assets.indexOf(asset);

        if (positionIdx == type(uint256).max) return;

        cache.margin -= ClearingHouseLib.realizeFundingPayment(cache.assets, cache.positions);

        cache.side = cache.positions[positionIdx].isLong ? Side.SELL : Side.BUY;
        cache.baseTraded = cache.positions[positionIdx].amount;
        cache.quoteTraded = cache.baseTraded.fullMulDiv(market.markPrice, 1e18);

        cache.positionResult = cache.positions[positionIdx].processTrade({
            side: cache.side,
            quoteTraded: cache.quoteTraded,
            baseTraded: cache.baseTraded
        });

        cache.fee = StorageLib.loadFeeManager().getTakerFee(account.account, cache.quoteTraded).toInt256();

        // settle rpnl and fee on margin
        cache.margin += cache.positionResult.rpnl - cache.fee;

        (cache.margin, cache.positionResult.marginDelta) = clearingHouse.rebalanceClose({
            assets: cache.assets,
            positions: cache.positions,
            margin: cache.margin,
            marginDelta: cache.positionResult.marginDelta
        });

        // bad debt realized
        if (cache.margin < 0 && cache.positions.length == 1) {
            cache.fee += cache.margin;
            delete cache.margin;
        }

        _emitLiquidationEvent({
            asset: asset,
            account: account.account,
            subaccount: account.subaccount,
            side: cache.side,
            quoteTraded: cache.quoteTraded,
            baseTraded: cache.baseTraded,
            rpnl: cache.positionResult.rpnl,
            margin: cache.margin,
            fee: cache.fee,
            liquidationType: LiquidationType.DELIST
        });

        if (cache.fee > 0) StorageLib.loadInsuranceFund().pay(cache.fee.abs());
        else StorageLib.loadInsuranceFund().claim(cache.fee.abs());

        StorageLib.loadCollateralManager().settleFill(
            account.account, account.subaccount, cache.margin, cache.positionResult.marginDelta
        );

        clearingHouse.updateAccount({
            account: account.account,
            subaccount: account.subaccount,
            assets: cache.assets,
            positions: cache.positions,
            tradedAsset: asset,
            positionIdx: positionIdx,
            oiDelta: cache.positionResult.oiDelta,
            sideClose: true
        });
    }

    function _deleveragePair(ClearingHouse storage clearingHouse, bytes32 asset, DeleveragePair calldata pair)
        internal
    {
        __DeleveragePairCache__ memory cache;

        // load accounts
        (cache.makerAssets, cache.makerPositions, cache.makerMargin) =
            clearingHouse.getAccountAndMargin(pair.maker.account, pair.maker.subaccount);
        (cache.takerAssets, cache.takerPositions, cache.takerMargin) =
            clearingHouse.getAccountAndMargin(pair.taker.account, pair.taker.subaccount);

        // realize funding payments
        cache.makerMargin -= ClearingHouseLib.realizeFundingPayment(cache.makerAssets, cache.makerPositions);
        cache.takerMargin -= ClearingHouseLib.realizeFundingPayment(cache.takerAssets, cache.takerPositions);

        uint256 makerPositionIdx = cache.makerAssets.indexOf(asset);
        uint256 takerPositionIdx = cache.takerAssets.indexOf(asset);

        // validate
        _validateDeleveragePair(
            clearingHouse,
            __DeleverageValidationParams__({
                asset: asset,
                makerAssets: cache.makerAssets,
                takerAssets: cache.takerAssets,
                makerPositions: cache.makerPositions,
                takerPositions: cache.takerPositions,
                makerPositionIdx: makerPositionIdx,
                takerPositionIdx: takerPositionIdx,
                makerMargin: cache.makerMargin,
                takerMargin: cache.takerMargin
            })
        );

        cache.baseAmount =
            cache.makerPositions[makerPositionIdx].amount.min(cache.takerPositions[takerPositionIdx].amount);

        // ADL trades at bankruptcy price of maker
        uint256 bankruptcyPrice = _getBankruptcyPrice({
            position: cache.makerPositions[makerPositionIdx],
            closeSize: cache.baseAmount,
            proratedMargin: clearingHouse.getProratedMargin(
                cache.makerAssets, cache.makerPositions, asset, cache.makerMargin
            )
        });

        cache.quoteAmount = cache.baseAmount.fullMulDiv(bankruptcyPrice, 1e18);

        _deleverage(
            clearingHouse,
            __DeleverageParams__({
                account: pair.maker.account,
                subaccount: pair.maker.subaccount,
                asset: asset,
                assets: cache.makerAssets,
                positions: cache.makerPositions,
                positionIdx: makerPositionIdx,
                baseTraded: cache.baseAmount,
                quoteTraded: cache.quoteAmount,
                margin: cache.makerMargin,
                deleverageType: LiquidationType.DELEVERAGE_MAKER
            })
        );

        _deleverage(
            clearingHouse,
            __DeleverageParams__({
                account: pair.taker.account,
                subaccount: pair.taker.subaccount,
                asset: asset,
                assets: cache.takerAssets,
                positions: cache.takerPositions,
                positionIdx: takerPositionIdx,
                baseTraded: cache.baseAmount,
                quoteTraded: cache.quoteAmount,
                margin: cache.takerMargin,
                deleverageType: LiquidationType.DELEVERAGE_TAKER
            })
        );
    }

    function _deleverage(ClearingHouse storage clearingHouse, __DeleverageParams__ memory params) internal {
        Side side = params.positions[params.positionIdx].isLong ? Side.SELL : Side.BUY;

        PositionUpdateResult memory result = params.positions[params.positionIdx].processTrade({
            side: side,
            quoteTraded: params.quoteTraded,
            baseTraded: params.baseTraded
        });

        // settle rpnl on margin
        params.margin += result.rpnl;

        (params.margin, result.marginDelta) = clearingHouse.rebalanceClose({
            assets: params.assets,
            positions: params.positions,
            margin: params.margin,
            marginDelta: 0
        });

        bool fullClose = params.positions[params.positionIdx].amount == 0 && params.positions.length == 1;

        // full close, underwater
        // outside of dust bad debt due to rounding error, this can only happen when the loss on a maker short is greater than openNotional
        // or when the bankruptcy price puts the taker into bad debt
        // in practice, neither of these should ever occur
        uint256 badDebt;
        if (fullClose && params.margin < 0) {
            badDebt = params.margin.abs();
            StorageLib.loadInsuranceFund().claim(badDebt);
            delete params.margin;
        }

        _emitLiquidationEvent({
            asset: params.asset,
            account: params.account,
            subaccount: params.subaccount,
            side: side,
            quoteTraded: params.quoteTraded,
            baseTraded: params.baseTraded,
            rpnl: result.rpnl,
            margin: params.margin,
            fee: -badDebt.toInt256(),
            liquidationType: params.deleverageType
        });

        StorageLib.loadCollateralManager().settleFill(
            params.account, params.subaccount, params.margin, result.marginDelta
        );

        clearingHouse.updateAccount({
            account: params.account,
            subaccount: params.subaccount,
            assets: params.assets,
            positions: params.positions,
            tradedAsset: params.asset,
            positionIdx: params.positionIdx,
            oiDelta: result.oiDelta,
            sideClose: result.sideClose
        });
    }

    function _getBankruptcyPrice(Position memory position, uint256 closeSize, int256 proratedMargin)
        internal
        pure
        returns (uint256 bankruptcyPrice)
    {
        // prorated margin again, based on amount closed
        if (proratedMargin > 0) proratedMargin = proratedMargin.abs().fullMulDiv(closeSize, position.amount).toInt256();
        else proratedMargin = -proratedMargin.abs().fullMulDiv(closeSize, position.amount).toInt256();

        uint256 openNotional = position.openNotional.fullMulDiv(closeSize, position.amount);

        int256 numerator;
        if (position.isLong) numerator = openNotional.toInt256() - proratedMargin;
        else numerator = openNotional.toInt256() + proratedMargin;

        if (numerator < 0) return 0;

        bankruptcyPrice = numerator.toUint256().fullMulDiv(1e18, closeSize);
    }

    function _validateDeleveragePair(ClearingHouse storage clearingHouse, __DeleverageValidationParams__ memory params)
        internal
        view
    {
        // assert positions exist
        if (params.makerPositionIdx.max(params.takerPositionIdx) == type(uint256).max) revert InvalidDeleveragePair();

        // assert maker is under water
        if (!clearingHouse.hasBadDebt(params.makerAssets, params.makerPositions, params.makerMargin)) {
            revert InvalidDeleveragePair();
        }

        // assert taker meets open margin requirement
        if (!clearingHouse.isOpenMarginRequirementMet(params.takerAssets, params.takerPositions, params.takerMargin)) {
            revert InvalidDeleveragePair();
        }

        // assert side
        if (
            params.makerPositions[params.makerPositionIdx].isLong
                == params.takerPositions[params.takerPositionIdx].isLong
        ) revert InvalidDeleveragePair();
    }

    function _setupAccountAndValidateLiquidation(
        ClearingHouse storage clearingHouse,
        address account,
        uint256 subaccount,
        bytes32 asset,
        BookType bookType
    )
        internal
        view
        returns (
            DynamicArrayLib.DynamicArray memory assets,
            Position[] memory positions,
            int256 margin,
            uint256 positionIdx
        )
    {
        (assets, positions, margin) = clearingHouse.getAccountAndMargin(account, subaccount);

        positionIdx = assets.indexOf(asset);

        if (positionIdx == type(uint256).max) revert InvalidLiquidation();

        margin -= ClearingHouseLib.realizeFundingPayment(assets, positions);

        clearingHouse.assertLiquidatable(assets, positions, margin, bookType);
    }

    function _liquidate(
        ClearingHouse storage clearingHouse,
        bytes32 asset,
        address account,
        uint256 subaccount,
        BookType bookType
    ) internal returns (__InternalLiquidateCache__ memory cache) {
        // load account, realize funding on margin, & validate liquidatability
        (cache.assets, cache.positions, cache.margin, cache.positionIdx) = _setupAccountAndValidateLiquidation({
            clearingHouse: clearingHouse,
            account: account,
            subaccount: subaccount,
            asset: asset,
            bookType: bookType
        });
        cache.side = cache.positions[cache.positionIdx].isLong ? Side.SELL : Side.BUY;

        // liquidate on book
        cache.fillResult = clearingHouse.market[asset].liquidate({
            account: account,
            subaccount: subaccount,
            side: cache.side,
            amount: cache.positions[cache.positionIdx].amount,
            bookType: bookType
        });

        // calc maintenance/prorated margin
        if (bookType == BookType.BACKSTOP) {
            int256 proratedMargin = clearingHouse.getProratedMargin(cache.assets, cache.positions, asset, cache.margin);

            cache.maintenanceOrProratedMargin = proratedMargin < 0 ? 0 : proratedMargin.toUint256();

            // if prorated margin is non-zero & partial liquidation, then prorate margin again based on amount closed
            if (
                cache.maintenanceOrProratedMargin > 0
                    && cache.positions[cache.positionIdx].amount > cache.fillResult.baseTraded
            ) {
                cache.maintenanceOrProratedMargin = cache.maintenanceOrProratedMargin.fullMulDiv(
                    cache.fillResult.baseTraded, cache.positions[cache.positionIdx].amount
                );
            }
        } else {
            cache.maintenanceOrProratedMargin =
                clearingHouse.market[asset].getMaintenanceMargin(cache.positions[cache.positionIdx].amount);
        }

        // process on position
        cache.positionResult = cache.positions[cache.positionIdx].processTrade({
            side: cache.side,
            quoteTraded: cache.fillResult.quoteTraded,
            baseTraded: cache.fillResult.baseTraded
        });
    }

    function _settleBackstopLiquidation(ClearingHouse storage clearingHouse, bytes32 asset, uint256 margin)
        internal
        returns (uint256 liquidationFee)
    {
        LiquidatorData[] memory data = BackstopLiquidatorDataLib.getLiquidatorDataAndClearStorage();

        if (margin == 0) return 0;

        liquidationFee = margin.fullMulDiv(StorageLib.loadMarketSettings(asset).liquidationFeeRate, 1e18);
        margin -= liquidationFee;

        uint256[] memory points = new uint256[](data.length);

        uint256 totalPoints;
        uint256 totalVolume;
        for (uint256 i; i < data.length; ++i) {
            points[i] = clearingHouse.liquidatorPoints[data[i].liquidator];
            totalPoints += points[i];
            totalVolume += data[i].volume;
        }

        uint256 pointShare;
        uint256 volumeShare;
        uint256 rate;
        uint256 fee;
        for (uint256 i; i < data.length; ++i) {
            pointShare = points[i].fullMulDiv(1e18, totalPoints);
            volumeShare = data[i].volume.fullMulDiv(1e18, totalVolume);

            rate = (pointShare + volumeShare) / 2;
            fee = margin.fullMulDiv(rate, 1e18);

            StorageLib.loadCollateralManager().creditAccount(data[i].liquidator, fee);
        }
    }

    function _emitLiquidationEvent(
        bytes32 asset,
        address account,
        uint256 subaccount,
        Side side,
        uint256 quoteTraded,
        uint256 baseTraded,
        int256 rpnl,
        int256 margin,
        int256 fee,
        LiquidationType liquidationType
    ) internal {
        int256 quoteDelta = side == Side.BUY ? -quoteTraded.toInt256() : quoteTraded.toInt256();
        int256 baseDelta = side == Side.BUY ? baseTraded.toInt256() : -baseTraded.toInt256();

        emit Liquidation({
            asset: asset,
            account: account,
            subaccount: subaccount,
            baseDelta: baseDelta,
            quoteDelta: quoteDelta,
            rpnl: rpnl,
            margin: margin,
            fee: fee,
            liquidationType: liquidationType,
            nonce: StorageLib.incNonce()
        });
    }

    function _balanceBadDebt(uint256 fee, uint256 badDebt)
        internal
        pure
        returns (uint256, /*fee*/ uint256 /*badDebt*/ )
    {
        if (fee > badDebt) return (fee - badDebt, 0);
        else return (0, badDebt - fee);
    }
}
