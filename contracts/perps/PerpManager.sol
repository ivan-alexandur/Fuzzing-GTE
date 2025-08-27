// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {DynamicArrayLib} from "@solady/utils/DynamicArrayLib.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";

import {AdminPanel} from "./modules/AdminPanel.sol";
import {LiquidatorPanel} from "./modules/LiquidatorPanel.sol";
import {ViewPort} from "./modules/ViewPort.sol";

import {ClearingHouse, ClearingHouseLib} from "./types/ClearingHouse.sol";
import {Market, MarketLib} from "./types/Market.sol";
import {Position} from "./types/Position.sol";
import {StorageLib} from "./types/StorageLib.sol";
import {CLOBLib} from "./types/CLOBLib.sol";

import {Side, TiF, BookType, TradeType} from "./types/Enums.sol";
import {PlaceOrderArgs, PlaceOrderResult, AmendLimitOrderArgs} from "./types/Structs.sol";

import {IAccountManager} from "..//account-manager/IAccountManager.sol";

import {OperatorHelperLib} from "../utils/types/OperatorHelperLib.sol";
import {OperatorPanel, OperatorStorage, OperatorStorageLib, PerpsOperatorRoles} from "../utils/OperatorPanel.sol";

/// CONCURRENCY TODO ///
// @todo make nonces market-specific
// @todo isolate insurance payments, claims, and balance per market (will have to also make liquidations per market)
contract PerpManager is AdminPanel, LiquidatorPanel, ViewPort, OperatorPanel {
    using OperatorHelperLib for OperatorStorage;
    using FixedPointMathLib for uint256;
    using SafeCastLib for uint256;

    event PositionLeverageSet(
        bytes32 indexed asset,
        address indexed account,
        uint256 indexed subaccount,
        uint256 newLeverage,
        int256 collateralDelta,
        int256 newMargin,
        uint256 nonce
    );

    event MarginAdded(
        address indexed account, uint256 indexed subaccount, uint256 amount, int256 newMargin, uint256 nonce
    );
    event MarginRemoved(
        address indexed account, uint256 indexed subaccount, uint256 amount, int256 newMargin, uint256 nonce
    );

    error RemainingMarginInsufficient();
    error InvalidDeposit();
    error InvalidWithdraw();
    error NotAccountManager();
    error InvalidBackstopLimitOrder();

    constructor(address _accountManager, address _operatorHub) OperatorPanel(_operatorHub) {
        accountManager = IAccountManager(_accountManager);
        _disableInitializers();
    }

    IAccountManager immutable accountManager;

    struct __UpdateLeverageCache__ {
        DynamicArrayLib.DynamicArray assets;
        Position[] positions;
        int256 fundingPayment;
        uint256 currentLeverage;
        uint256 orderbookNotional;
        uint256 newOrderbookMargin;
        uint256 currentOrderbookMargin;
        int256 collateralDeltaFromBook;
        uint256 newMargin;
    }

    struct __MarginUpdateCache__ {
        DynamicArrayLib.DynamicArray assets;
        Position[] positions;
        int256 fundingPayment;
        uint256 intendedMargin;
    }

    modifier onlySenderOrOperator(address account, PerpsOperatorRoles requiredRole) {
        OperatorStorageLib.getOperatorStorage().onlySenderOrOperator(account, requiredRole);
        _;
    }

    modifier onlyActiveProtocol() override (AdminPanel, LiquidatorPanel) {
        if (!StorageLib.loadClearingHouse().active) revert ProtocolNotActive();
        _;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            FREE COLLATERAL
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function deposit(address account, uint256 amount)
        external
        onlySenderOrOperator(account, PerpsOperatorRoles.DEPOSIT_ACCOUNT)
    {
        StorageLib.loadCollateralManager().depositFreeCollateral(account, account, amount);
    }

    function withdraw(address account, uint256 amount)
        external
        onlySenderOrOperator(account, PerpsOperatorRoles.WITHDRAW_ACCOUNT)
    {
        StorageLib.loadCollateralManager().withdrawFreeCollateral(account, amount);
    }

    function depositTo(address account, uint256 amount) external {
        StorageLib.loadCollateralManager().depositFreeCollateral({
            from: msg.sender,
            to: account,
            amount: amount
        });
    }

    function depositFromSpot(address account, uint256 amount)
        external
        onlySenderOrOperator(account, PerpsOperatorRoles.SPOT_TO_PERP_DEPOSIT)
    {
        accountManager.withdrawToPerps(account, amount);
        StorageLib.loadCollateralManager().depositFromSpot(account, amount);
    }

    function withdrawToSpot(address account, uint256 amount) external {
        if (msg.sender != address(accountManager)) revert NotAccountManager();
        StorageLib.loadCollateralManager().withdrawToSpot(account, amount, address(accountManager));
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                 MARGIN
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function addMargin(address account, uint256 subaccount, uint256 amount)
        external
        onlySenderOrOperator(account, PerpsOperatorRoles.DEPOSIT_MARGIN)
    {
        ClearingHouse storage clearingHouse = StorageLib.loadClearingHouse();

        __MarginUpdateCache__ memory cache;

        // load account
        (cache.assets, cache.positions) = clearingHouse.getAccount(account, subaccount);

        if (amount == 0) revert InvalidDeposit();
        if (cache.positions.length == 0) revert InvalidDeposit();

        // realize funding payment
        cache.fundingPayment = ClearingHouseLib.realizeFundingPayment(cache.assets, cache.positions);

        // settle margin update
        int256 remainingMargin = StorageLib.loadCollateralManager().settleMarginUpdate({
            account: account,
            subaccount: subaccount,
            marginDelta: amount.toInt256(),
            fundingPayment: cache.fundingPayment
        });

        // assert not liquidatable
        clearingHouse.assertNotLiquidatable({assets: cache.assets, positions: cache.positions, margin: remainingMargin});

        // set position update (note: this will just be the new position.lastCumulativeFunding)
        clearingHouse.setPositions({
            tradedAsset: "",
            account: account,
            subaccount: subaccount,
            assets: cache.assets,
            positions: cache.positions
        });

        emit MarginAdded(account, subaccount, amount, remainingMargin, StorageLib.incNonce());
    }

    function removeMargin(address account, uint256 subaccount, uint256 amount)
        external
        onlySenderOrOperator(account, PerpsOperatorRoles.WITHDRAW_MARGIN)
    {
        ClearingHouse storage clearingHouse = StorageLib.loadClearingHouse();

        __MarginUpdateCache__ memory cache;

        // load account
        (cache.assets, cache.positions) = clearingHouse.getAccount(account, subaccount);

        if (amount == 0) revert InvalidWithdraw();
        if (cache.positions.length == 0) revert InvalidWithdraw();

        // realize funding payment
        cache.fundingPayment = ClearingHouseLib.realizeFundingPayment(cache.assets, cache.positions);

        // settle margin update
        int256 remainingMargin = StorageLib.loadCollateralManager().settleMarginUpdate({
            account: account,
            subaccount: subaccount,
            marginDelta: -amount.toInt256(),
            fundingPayment: cache.fundingPayment
        });

        // assert post withdraw margin requirement (margin + upnl) >= max(intendedMargin, totalNotional / 10)
        // where intendedMargin is the sum of notional / leverage for open positions
        clearingHouse.assertPostWithdrawalMarginRequired({
            assets: cache.assets,
            positions: cache.positions,
            margin: remainingMargin
        });

        // set position update (note: this will just be the new position.lastCumulativeFunding)
        clearingHouse.setPositions({
            tradedAsset: "",
            account: account,
            subaccount: subaccount,
            assets: cache.assets,
            positions: cache.positions
        });

        emit MarginRemoved(account, subaccount, amount, remainingMargin, StorageLib.incNonce());
    }

    function setPositionLeverage(bytes32 asset, address account, uint256 subaccount, uint256 newLeverage)
        external
        onlySenderOrOperator(account, PerpsOperatorRoles.SET_LEVERAGE)
        returns (int256 collateralDelta)
    {
        ClearingHouse storage clearingHouse = StorageLib.loadClearingHouse();
        Market storage market = clearingHouse.market[asset];

        MarketLib.assertActive(asset);
        MarketLib.assertMaxLeverage(asset, newLeverage);

        __UpdateLeverageCache__ memory cache;

        // handle collateral delta for book oi
        cache.currentLeverage = market.getPositionLeverage(account, subaccount);
        cache.orderbookNotional = market.orderbookNotional[account][subaccount];

        cache.newOrderbookMargin = cache.orderbookNotional.fullMulDiv(1e18, newLeverage);
        cache.currentOrderbookMargin = cache.orderbookNotional.fullMulDiv(1e18, cache.currentLeverage);

        cache.collateralDeltaFromBook = cache.newOrderbookMargin.toInt256() - cache.currentOrderbookMargin.toInt256();

        // set new leverage before loading account
        market.position[account][subaccount].leverage = newLeverage;

        // empty position
        if (market.position[account][subaccount].amount == 0) {
            StorageLib.loadCollateralManager().handleCollateralDelta({
                account: account,
                collateralDelta: cache.collateralDeltaFromBook
            });

            // margin doesn't change on leverage update for empty positions
            int256 margin = StorageLib.loadCollateralManager().getMarginBalance(account, subaccount);

            emit PositionLeverageSet(
                asset, account, subaccount, newLeverage, cache.collateralDeltaFromBook, margin, StorageLib.incNonce()
            );

            return cache.collateralDeltaFromBook;
        }

        // load account
        (cache.assets, cache.positions) = clearingHouse.getAccount(account, subaccount);

        // realize funding payment
        cache.fundingPayment = ClearingHouseLib.realizeFundingPayment(cache.assets, cache.positions);

        cache.newMargin = clearingHouse.getIntendedMargin(cache.assets, cache.positions);

        // assert open margin requirement met
        clearingHouse.assertOpenMarginRequired({
            assets: cache.assets,
            positions: cache.positions,
            margin: cache.newMargin.toInt256()
        });

        clearingHouse.setPositions({
            tradedAsset: "",
            account: account,
            subaccount: subaccount,
            assets: cache.assets,
            positions: cache.positions
        });

        // settle delta between new and prev margin & new and prev orderbook collateral
        collateralDelta = StorageLib.loadCollateralManager().settleNewLeverage({
            account: account,
            subaccount: subaccount,
            collateralDeltaFromBook: cache.collateralDeltaFromBook,
            newMargin: cache.newMargin.toInt256(),
            fundingPayment: cache.fundingPayment
        });

        emit PositionLeverageSet(
            asset, account, subaccount, newLeverage, collateralDelta, cache.newMargin.toInt256(), StorageLib.incNonce()
        );
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                              ORDER PLACE
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function placeOrder(address account, PlaceOrderArgs calldata args)
        external
        onlySenderOrOperator(account, PerpsOperatorRoles.PLACE_ORDER)
        onlyActiveProtocol
        returns (PlaceOrderResult memory result)
    {
        return StorageLib.loadClearingHouse().placeOrder(account, args, BookType.STANDARD);
    }

    function postLimitOrderBackstop(address account, PlaceOrderArgs calldata args)
        external
        onlySenderOrOperator(account, PerpsOperatorRoles.PLACE_ORDER)
        onlyActiveProtocol
        returns (PlaceOrderResult memory result)
    {
        if (args.tif != TiF.MOC) revert InvalidBackstopLimitOrder();

        return StorageLib.loadClearingHouse().placeOrder(account, args, BookType.BACKSTOP);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                          ORDER AMEND / CANCEL
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function amendLimitOrder(address account, AmendLimitOrderArgs calldata args)
        external
        onlySenderOrOperator(account, PerpsOperatorRoles.PLACE_ORDER)
        onlyActiveProtocol
        returns (int256 collateralDelta)
    {
        ClearingHouse storage clearingHouse = StorageLib.loadClearingHouse();

        collateralDelta = clearingHouse.market[args.asset].amendLimitOrder(account, args, BookType.STANDARD);

        StorageLib.loadCollateralManager().handleCollateralDelta({account: account, collateralDelta: collateralDelta});
    }

    function cancelLimitOrders(bytes32 asset, address account, uint256 subaccount, uint256[] calldata orderIds)
        external
        onlySenderOrOperator(account, PerpsOperatorRoles.PLACE_ORDER)
        onlyActiveProtocol
        returns (uint256 refund)
    {
        refund = CLOBLib.cancel(asset, account, subaccount, orderIds, BookType.STANDARD);

        StorageLib.loadCollateralManager().handleCollateralDelta({account: account, collateralDelta: -refund.toInt256()});
    }

    function amendLimitOrderBackstop(address account, AmendLimitOrderArgs calldata args)
        external
        onlySenderOrOperator(account, PerpsOperatorRoles.PLACE_ORDER)
        onlyActiveProtocol
        returns (int256 collateralDelta)
    {
        ClearingHouse storage clearingHouse = StorageLib.loadClearingHouse();

        collateralDelta = clearingHouse.market[args.asset].amendLimitOrder(account, args, BookType.BACKSTOP);

        StorageLib.loadCollateralManager().handleCollateralDelta({account: account, collateralDelta: collateralDelta});
    }

    function cancelLimitOrdersBackstop(bytes32 asset, address account, uint256 subaccount, uint256[] calldata orderIds)
        external
        onlySenderOrOperator(account, PerpsOperatorRoles.PLACE_ORDER)
        onlyActiveProtocol
        returns (uint256 refund)
    {
        refund = CLOBLib.cancel(asset, account, subaccount, orderIds, BookType.BACKSTOP);

        StorageLib.loadCollateralManager().handleCollateralDelta({account: account, collateralDelta: -refund.toInt256()});
    }

    function cancelConditionalOrders(address account, uint256[] calldata nonces)
        external
        onlySenderOrOperator(account, PerpsOperatorRoles.PLACE_ORDER)
        onlyActiveProtocol
    {
        ClearingHouse storage clearingHouse = StorageLib.loadClearingHouse();

        for (uint256 i; i < nonces.length; i++) {
            clearingHouse.nonceUsed[account][nonces[i]] = true;
        }
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               HELPER
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _getCollateral(uint256 baseAmount, uint256 price, uint256 leverage)
        private
        pure
        returns (uint256 collateral)
    {
        collateral = baseAmount.fullMulDiv(price, 1e18).fullMulDiv(1e18, leverage);
    }
}
