// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "../PerpManagerTestBase.sol";

contract PerpPostFillOrder_Decrease_Test is PerpManagerTestBase {
    using FixedPointMathLib for *;
    using SafeCastLib for uint256;

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                 SETUP
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function setUp() public override {
        super.setUp();

        taker = rite;
        maker = jb;
    }

    address taker;
    address maker;

    State state;
    FillOrderParams params;
    ExpectedResult expected;

    struct State {
        uint256 orderId;
        uint256 takerBalance;
        uint256 makerBalance;
        uint256 takerCollateral;
        uint256 makerCollateral;
        uint256 takerMargin;
        uint256 makerMargin;
        Position makerPosition;
        Position takerPosition;
        uint256 insuranceFundBalance;
        uint256 quoteBookOI;
        uint256 baseBookOI;
        uint256 orderCollateral;
        uint256 longOI;
        uint256 shortOI;
    }

    struct FillOrderParams {
        Side side;
        uint256 originalAmount;
        uint256 makerLeverage;
        uint256 takerLeverage;
        uint256 price;
        uint256 takerOrderAmount;
        uint256 makerOrderAmount;
        bool baseDenominated;
        bool makerReduceOnly;
    }

    struct ExpectedResult {
        uint256 takerMargin;
        uint256 makerMargin;
        uint256 takerCollateralReturned;
        uint256 makerCollateralReturned;
        uint256 makerOrderRefund;
        uint256 quoteTraded;
        uint256 baseTraded;
        uint256 takerFee;
        uint256 makerFee;
        int256 takerRpnl;
        int256 makerRpnl;
        uint256 takerPositionAmount;
        uint256 makerPositionAmount;
        uint256 takerPositionOpenNotional;
        uint256 makerPositionOpenNotional;
        bool takerPositionIsLong;
        bool makerPositionIsLong;
    }

    struct CollateralizeCache {
        uint256 size;
        uint256 openNotional;
        uint256 leverage;
        int256 margin;
        int256 rpnl;
        uint256 estimatedClosedMargin;
        bool isLong;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                             DECREASE LONG
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_Perp_Fill_Decrease_Long_PositivePnL(uint256) public {
        params.side = Side.BUY;
        params.baseDenominated = true;
        params.makerReduceOnly = false;
        params.originalAmount = _hem(_randomUnique(), 10e18, 100e18);
        params.makerLeverage = _hem(_randomUnique(), 1e18, 50e18);
        params.takerLeverage = _hem(_randomUnique(), 1e18, 50e18);
        params.price = _hem(
            _randomUnique(),
            perpManager.getMarkPrice(ETH),
            _getLiquidationPrice(
                ETH, params.originalAmount, params.makerLeverage, params.side == Side.BUY ? Side.SELL : Side.BUY
            )
        );
        params.makerOrderAmount = _hem(_randomUnique(), 3e18, params.originalAmount - 1000);
        params.takerOrderAmount = _hem(_randomUnique(), 1e18, params.makerOrderAmount);

        if (params.price % perpManager.getTickSize(ETH) != 0) {
            params.price -= params.price % perpManager.getTickSize(ETH);
            if (params.price == 0) params.price = perpManager.getTickSize(ETH);
        }

        _fillDecreaseHelper();

        assertTrue(perpManager.getPosition(ETH, taker, 1).isLong, "taker position should still be long");
        assertFalse(perpManager.getPosition(ETH, maker, 1).isLong, "maker position should still be short");
        assertTrue(expected.takerRpnl >= 0, "taker pnl should be positive");
        assertTrue(expected.makerRpnl <= 0, "maker pnl should be negative");
    }

    function test_Perp_Fill_Decrease_Long_NegativePnL(uint256) public {
        params.side = Side.BUY;
        params.baseDenominated = true;
        params.makerReduceOnly = false;
        params.originalAmount = _hem(_random(), 10e18, 100e18);
        params.makerLeverage = _hem(_random(), 1e18, 50e18);
        params.takerLeverage = _hem(_random(), 1e18, 50e18);
        params.price = _hem(
            _random(),
            _getLiquidationPrice(ETH, params.originalAmount, params.takerLeverage, params.side),
            perpManager.getMarkPrice(ETH)
        );
        params.makerOrderAmount = _hem(_random(), 3e18, params.originalAmount - 1000);
        params.takerOrderAmount = _hem(_random(), 1e18, params.makerOrderAmount);

        if (params.price % perpManager.getTickSize(ETH) != 0) {
            params.price += perpManager.getTickSize(ETH);
            params.price -= params.price % perpManager.getTickSize(ETH);
        }

        _fillDecreaseHelper();

        assertTrue(perpManager.getPosition(ETH, taker, 1).isLong, "taker position should still be long");
        assertFalse(perpManager.getPosition(ETH, maker, 1).isLong, "maker position should still be short");
        assertTrue(expected.takerRpnl <= 0, "taker pnl should be negative");
        assertTrue(expected.makerRpnl >= 0, "maker pnl should be positive");
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                             DECREASE SHORT
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_Perp_Fill_Decrease_Short_PositivePnL(uint256) public {
        params.side = Side.SELL;
        params.baseDenominated = true;
        params.makerReduceOnly = false;
        params.originalAmount = _hem(_randomUnique(), 10e18, 100e18);
        params.makerLeverage = _hem(_randomUnique(), 1e18, 50e18);
        params.takerLeverage = _hem(_randomUnique(), 1e18, 50e18);
        params.price = _hem(
            _randomUnique(),
            _getLiquidationPrice(
                ETH, params.originalAmount, params.makerLeverage, params.side == Side.BUY ? Side.SELL : Side.BUY
            ),
            perpManager.getMarkPrice(ETH)
        );
        params.makerOrderAmount = _hem(_randomUnique(), 3e18, params.originalAmount - 1000);
        params.takerOrderAmount = _hem(_randomUnique(), 1e18, params.makerOrderAmount);

        if (params.price % perpManager.getTickSize(ETH) != 0) {
            params.price += perpManager.getTickSize(ETH);
            params.price -= params.price % perpManager.getTickSize(ETH);
        }

        _fillDecreaseHelper();

        assertFalse(perpManager.getPosition(ETH, taker, 1).isLong, "taker position should still be long");
        assertTrue(perpManager.getPosition(ETH, maker, 1).isLong, "maker position should still be short");
        assertTrue(expected.takerRpnl >= 0, "taker pnl should be positive");
        assertTrue(expected.makerRpnl <= 0, "maker pnl should be negative");
    }

    function test_Perp_Fill_Decrease_Short_NegativePnL(uint256) public {
        params.side = Side.SELL;
        params.baseDenominated = true;
        params.makerReduceOnly = false;
        params.originalAmount = _hem(_random(), 10e18, 100e18);
        params.makerLeverage = _hem(_random(), 1e18, 50e18);
        params.takerLeverage = _hem(_random(), 1e18, 50e18);
        params.price = _hem(
            _random(),
            perpManager.getMarkPrice(ETH),
            _getLiquidationPrice(ETH, params.originalAmount, params.takerLeverage, params.side)
        );
        params.makerOrderAmount = _hem(_random(), 3e18, params.originalAmount - 1000);
        params.takerOrderAmount = _hem(_random(), 1e18, params.makerOrderAmount);

        if (params.price % perpManager.getTickSize(ETH) != 0) {
            params.price -= params.price % perpManager.getTickSize(ETH);
            if (params.price == 0) params.price = perpManager.getTickSize(ETH);
        }

        _fillDecreaseHelper();

        assertFalse(perpManager.getPosition(ETH, taker, 1).isLong, "taker position should still be long");
        assertTrue(perpManager.getPosition(ETH, maker, 1).isLong, "maker position should still be short");
        assertTrue(expected.takerRpnl <= 0, "taker pnl should be negative");
        assertTrue(expected.makerRpnl >= 0, "maker pnl should be positive");
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                              REDUCE ONLY
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_Perp_Fill_Decrease_ReduceOnly_Long(uint256) public {
        params.side = Side.BUY;
        params.baseDenominated = true;
        params.makerReduceOnly = true;
        params.originalAmount = _hem(_random(), 10e18, 100e18);
        params.makerLeverage = _hem(_random(), 1e18, 50e18);
        params.takerLeverage = _hem(_random(), 1e18, 50e18);
        params.price = _hem(
            _random(),
            _getLiquidationPrice(ETH, params.originalAmount, params.takerLeverage, params.side),
            _getLiquidationPrice(
                ETH, params.originalAmount, params.makerLeverage, params.side == Side.BUY ? Side.SELL : Side.BUY
            )
        );
        params.makerOrderAmount = _hem(_random(), 3e18, params.originalAmount - 1000);
        params.takerOrderAmount = _hem(_random(), 1e18, params.makerOrderAmount);

        if (params.price % perpManager.getTickSize(ETH) != 0) {
            params.price -= params.price % perpManager.getTickSize(ETH);
            if (params.price == 0) params.price = perpManager.getTickSize(ETH);
        }

        _fillDecreaseHelper();

        assertTrue(expected.makerOrderRefund == 0, "maker order refund should be zero");
    }

    function test_Perp_Fill_Decrease_ReduceOnly_Short(uint256) public {
        params.side = Side.SELL;
        params.baseDenominated = true;
        params.makerReduceOnly = true;
        params.originalAmount = _hem(_random(), 10e18, 100e18);
        params.makerLeverage = _hem(_random(), 1e18, 50e18);
        params.takerLeverage = _hem(_random(), 1e18, 50e18);
        params.price = _hem(
            _random(),
            _getLiquidationPrice(
                ETH, params.originalAmount, params.makerLeverage, params.side == Side.BUY ? Side.SELL : Side.BUY
            ),
            _getLiquidationPrice(ETH, params.originalAmount, params.takerLeverage, params.side)
        );
        params.makerOrderAmount = _hem(_random(), 3e18, params.originalAmount - 1000);
        params.takerOrderAmount = _hem(_random(), 1e18, params.makerOrderAmount);

        if (params.price % perpManager.getTickSize(ETH) != 0) {
            params.price -= params.price % perpManager.getTickSize(ETH);
            if (params.price == 0) params.price = perpManager.getTickSize(ETH);
        }

        _fillDecreaseHelper();

        assertTrue(expected.makerOrderRefund == 0, "maker order refund should be zero");
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                           QUOTE DENOMINATED
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_Perp_Fill_Decrease_QuoteDenominated_Long(uint256) public {
        params.side = Side.BUY;
        params.baseDenominated = false;
        params.makerReduceOnly = _randomChance(2);
        params.originalAmount = _hem(_random(), 10e18, 100e18);
        params.makerLeverage = _hem(_random(), 1e18, 50e18);
        params.takerLeverage = _hem(_random(), 1e18, 50e18);
        params.price = _hem(
            _random(),
            _getLiquidationPrice(ETH, params.originalAmount, params.takerLeverage, params.side),
            _getLiquidationPrice(
                ETH, params.originalAmount, params.makerLeverage, params.side == Side.BUY ? Side.SELL : Side.BUY
            )
        );
        if (params.price % perpManager.getTickSize(ETH) != 0) {
            params.price -= params.price % perpManager.getTickSize(ETH);
            if (params.price == 0) params.price = perpManager.getTickSize(ETH);
        }

        params.makerOrderAmount = _hem(_random(), 3e18, params.originalAmount - 1000);
        params.takerOrderAmount = _toQuote(_hem(_random(), 1e18, params.makerOrderAmount), params.price);

        _fillDecreaseHelper();
    }

    function test_Perp_Fill_Decrease_QuoteDenominated_Short(uint256) public {
        params.side = Side.SELL;
        params.baseDenominated = false;
        params.makerReduceOnly = _randomChance(2);
        params.originalAmount = _hem(_random(), 10e18, 100e18);
        params.makerLeverage = _hem(_random(), 1e18, 50e18);
        params.takerLeverage = _hem(_random(), 1e18, 50e18);
        params.price = _hem(
            _random(),
            _getLiquidationPrice(
                ETH, params.originalAmount, params.makerLeverage, params.side == Side.BUY ? Side.SELL : Side.BUY
            ),
            _getLiquidationPrice(ETH, params.originalAmount, params.takerLeverage, params.side)
        );

        if (params.price % perpManager.getTickSize(ETH) != 0) {
            params.price -= params.price % perpManager.getTickSize(ETH);
            if (params.price == 0) params.price = perpManager.getTickSize(ETH);
        }

        params.makerOrderAmount = _hem(_random(), 3e18, params.originalAmount - 1000);
        params.takerOrderAmount = _toQuote(_hem(_random(), 1e18, params.makerOrderAmount), params.price);

        _fillDecreaseHelper();
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                             CLOSE FUNCTION
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_Perp_Fill_Decrease_CloseFunction(uint256) public {
        params.side = _randomChance(2) ? Side.BUY : Side.SELL;
        params.baseDenominated = true;
        params.makerReduceOnly = _randomChance(2);
        params.originalAmount = _hem(_random(), 10e18, 100e18);
        params.makerLeverage = _hem(_random(), 1e18, 50e18);
        params.takerLeverage = _hem(_random(), 1e18, 50e18);

        uint256 makerLiquidation = _getLiquidationPrice(
            ETH, params.originalAmount, params.makerLeverage, params.side == Side.BUY ? Side.SELL : Side.BUY
        );
        uint256 takerLiquidation = _getLiquidationPrice(ETH, params.originalAmount, params.takerLeverage, params.side);

        (uint256 max, uint256 min) = makerLiquidation > takerLiquidation
            ? (makerLiquidation, takerLiquidation)
            : (takerLiquidation, makerLiquidation);

        params.price = _hem(_random(), min, max);
        params.makerOrderAmount = _hem(_random(), 3e18, params.originalAmount - 1000);
        params.takerOrderAmount = _hem(_random(), 1e18, params.makerOrderAmount);

        if (params.price % perpManager.getTickSize(ETH) != 0) {
            params.price -= params.price % perpManager.getTickSize(ETH);
            if (params.price == 0) params.price = perpManager.getTickSize(ETH);
        }

        _fillDecreaseHelper_CloseFunction();
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _fillDecreaseHelper() internal {
        vm.prank(maker);
        perpManager.setPositionLeverage({asset: ETH, account: maker, subaccount: 1, newLeverage: params.makerLeverage});

        vm.prank(taker);
        perpManager.setPositionLeverage({asset: ETH, account: taker, subaccount: 1, newLeverage: params.takerLeverage});

        params.originalAmount = _conformAmountToLots(params.originalAmount);
        params.makerOrderAmount = _conformAmountToLots(params.makerOrderAmount);

        _placeTrade({
            subaccount: 1,
            asset: ETH,
            taker: taker,
            maker: maker,
            price: 4000e18,
            amount: params.originalAmount,
            side: params.side
        });

        PlaceOrderArgs memory makerArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: params.side,
            limitPrice: params.price,
            amount: params.makerOrderAmount,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: params.makerReduceOnly
        });

        PlaceOrderArgs memory takerArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: params.side == Side.BUY ? Side.SELL : Side.BUY,
            limitPrice: params.price,
            amount: params.takerOrderAmount,
            baseDenominated: params.baseDenominated,
            tif: TiF.IOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        vm.prank(maker);
        state.orderId = perpManager.placeOrder(maker, makerArgs).orderId;

        _cachePreFillOderState();
        _predictFillOrderResult();
        // _expectEvents();

        vm.prank(taker);
        PlaceOrderResult memory result = perpManager.placeOrder(taker, takerArgs);

        _assertPostFillState(result);
    }

    function _fillDecreaseHelper_CloseFunction() internal {
        vm.prank(maker);
        perpManager.setPositionLeverage({asset: ETH, account: maker, subaccount: 1, newLeverage: params.makerLeverage});

        vm.prank(taker);
        perpManager.setPositionLeverage({asset: ETH, account: taker, subaccount: 1, newLeverage: params.takerLeverage});

        params.originalAmount = _conformAmountToLots(params.originalAmount);
        params.makerOrderAmount = _conformAmountToLots(params.makerOrderAmount);

        _placeTrade({
            subaccount: 1,
            asset: ETH,
            taker: taker,
            maker: maker,
            price: 4000e18,
            amount: params.originalAmount,
            side: params.side
        });

        PlaceOrderArgs memory makerArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: params.side,
            limitPrice: params.price,
            amount: params.makerOrderAmount,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: params.makerReduceOnly
        });

        PlaceOrderArgs memory closeArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: params.side == Side.BUY ? Side.SELL : Side.BUY,
            limitPrice: params.price,
            amount: params.takerOrderAmount,
            baseDenominated: true, // must be base denominated to be reduce only
            tif: TiF.IOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: true // reduce only true == close args
        });

        vm.prank(maker);
        state.orderId = perpManager.placeOrder(maker, makerArgs).orderId;

        _cachePreFillOderState();
        _predictFillOrderResult();
        // _expectEvents();

        vm.prank(taker);
        PlaceOrderResult memory result = perpManager.placeOrder(taker, closeArgs);

        _assertPostFillState(result);
    }

    function _cachePreFillOderState() internal {
        state.takerBalance = usdc.balanceOf(taker);
        state.makerBalance = usdc.balanceOf(maker);
        state.takerCollateral = perpManager.getFreeCollateralBalance(taker);
        state.makerCollateral = perpManager.getFreeCollateralBalance(maker);
        state.takerMargin = uint256(perpManager.getMarginBalance(taker, 1));
        state.makerMargin = uint256(perpManager.getMarginBalance(maker, 1));
        state.makerPosition = perpManager.getPosition(ETH, maker, 1);
        state.takerPosition = perpManager.getPosition(ETH, taker, 1);
        state.insuranceFundBalance = perpManager.getInsuranceFundBalance();
        (state.baseBookOI, state.quoteBookOI) = perpManager.getOpenInterestBook(ETH);
        (state.longOI, state.shortOI) = perpManager.getOpenInterest(ETH);
        if (!params.makerReduceOnly) {
            state.orderCollateral =
                params.makerOrderAmount.fullMulDiv(params.price, 1e18).fullMulDiv(1e18, params.makerLeverage);
        }

        if (params.side == Side.SELL) {
            assertFalse(state.takerPosition.isLong, "state: taker position before: wrong side");
            assertTrue(state.makerPosition.isLong, "state: maker position before: wrong side");
            assertTrue(state.baseBookOI > 0, "state: base book oi wrong");
            assertEq(state.quoteBookOI, 0, "state: quote book oi wrong");
        } else {
            assertTrue(state.takerPosition.isLong, "state: taker position before: wrong side");
            assertFalse(state.makerPosition.isLong, "state: maker position before: wrong side");
            assertTrue(state.quoteBookOI > 0, "state: quote book oi wrong");
            assertEq(state.baseBookOI, 0, "state: base book oi wrong");
        }
        assertTrue(
            state.makerPosition.amount != 0 && state.takerPosition.amount != 0, "state: position's should not be empty"
        );
    }

    function _predictFillOrderResult() internal {
        // TRADE
        expected.baseTraded =
            params.baseDenominated ? params.takerOrderAmount : params.takerOrderAmount.fullMulDiv(1e18, params.price);
        expected.baseTraded = expected.baseTraded.min(params.makerOrderAmount);
        expected.baseTraded = _conformAmountToLots(expected.baseTraded);
        expected.quoteTraded = expected.baseTraded.fullMulDiv(params.price, 1e18);

        expected.takerFee = expected.quoteTraded * TAKER_BASE_FEE_RATE / 10_000_000;
        expected.makerFee = expected.quoteTraded * MAKER_BASE_FEE_RATE / 10_000_000;

        if (state.takerPosition.isLong) expected.takerPositionIsLong = true;
        else expected.makerPositionIsLong = true;

        // TAKER POSITION SETTLE
        uint256 tradedOpenNotional =
            state.takerPosition.openNotional.fullMulDiv(expected.baseTraded, state.takerPosition.amount);

        expected.takerRpnl = _getPnl(state.takerPosition.isLong, expected.quoteTraded, tradedOpenNotional);

        expected.takerPositionAmount = state.takerPosition.amount - expected.baseTraded;
        expected.takerPositionOpenNotional = state.takerPosition.openNotional - tradedOpenNotional;

        // TAKER COLLATERAL SETTLE
        (expected.takerMargin, expected.takerCollateralReturned) = _calcMarginSettle(
            CollateralizeCache({
                size: expected.takerPositionAmount,
                openNotional: expected.takerPositionOpenNotional,
                leverage: params.takerLeverage,
                margin: int256(state.takerMargin),
                rpnl: expected.takerRpnl - expected.takerFee.toInt256(),
                estimatedClosedMargin: tradedOpenNotional.fullMulDiv(1e18, params.takerLeverage),
                isLong: state.takerPosition.isLong
            })
        );

        // MAKER POSITION SETTLE
        tradedOpenNotional =
            state.makerPosition.openNotional.fullMulDiv(expected.baseTraded, state.makerPosition.amount);

        expected.makerRpnl = _getPnl(state.makerPosition.isLong, expected.quoteTraded, tradedOpenNotional);

        expected.makerPositionAmount = state.makerPosition.amount - expected.baseTraded;
        expected.makerPositionOpenNotional = state.makerPosition.openNotional - tradedOpenNotional;

        if (!params.makerReduceOnly) {
            expected.makerOrderRefund = expected.quoteTraded.fullMulDiv(1e18, params.makerLeverage);
        }

        // MAKER COLLATERAL SETTLE
        (expected.makerMargin, expected.makerCollateralReturned) = _calcMarginSettle(
            CollateralizeCache({
                size: expected.makerPositionAmount,
                openNotional: expected.makerPositionOpenNotional,
                leverage: params.makerLeverage,
                margin: int256(state.makerMargin),
                rpnl: expected.makerRpnl - expected.makerFee.toInt256(),
                estimatedClosedMargin: tradedOpenNotional.fullMulDiv(1e18, params.makerLeverage),
                isLong: state.makerPosition.isLong
            })
        );

        expected.makerCollateralReturned += expected.makerOrderRefund;
    }

    function _assertPostFillState(PlaceOrderResult memory result) internal view {
        Position memory takerPosition = perpManager.getPosition(ETH, taker, 1);
        Position memory makerPosition = perpManager.getPosition(ETH, maker, 1);
        (uint256 baseBookOI, uint256 quoteBookOI) = perpManager.getOpenInterestBook(ETH);
        (uint256 longOI, uint256 shortOI) = perpManager.getOpenInterest(ETH);

        uint256 remainingBookCollateral;
        if (expected.baseTraded != params.makerOrderAmount) {
            remainingBookCollateral = state.orderCollateral - expected.makerOrderRefund;
        }

        // result
        if (params.side == Side.BUY) {
            assertEq(result.quoteTraded, expected.quoteTraded, "result: quote traded is wrong");
            assertEq(result.baseTraded, expected.baseTraded, "result: base traded is wrong");
        } else {
            assertEq(result.quoteTraded, expected.quoteTraded, "result: quote traded is wrong");
            assertEq(result.baseTraded, expected.baseTraded, "result: base traded is wrong");
        }

        // remaining order
        if (expected.baseTraded != params.makerOrderAmount) {
            Order memory order = perpManager.getLimitOrder(ETH, state.orderId);

            assertEq(order.owner, maker, "remaining order: order owner is wrong");
            assertEq(order.amount, params.makerOrderAmount - expected.baseTraded, "remaining order: amount is wrong");
            assertEq(order.price, params.price, "remaining order: price is wrong");
            assertEq(order.subaccount, 1, "remaining order: subaccount is wrong");
        }

        // taker position
        assertEq(takerPosition.amount, expected.takerPositionAmount, "taker position: amount is wrong");
        assertEq(
            takerPosition.openNotional, expected.takerPositionOpenNotional, "taker position: open notional is wrong"
        );
        assertEq(takerPosition.leverage, params.takerLeverage, "taker position: leverage is wrong");
        assertEq(takerPosition.isLong, expected.takerPositionIsLong, "taker position: is long is wrong");
        assertTrue(takerPosition.amount != 0, "taker position: amount should not be zero");
        assertTrue(
            takerPosition.amount < state.takerPosition.amount, "taker position: amount should be less than original"
        );
        assertEq(perpManager.getAssets(taker, 1).length, 1, "taker position: should have one position");
        assertEq(perpManager.getAssets(taker, 1)[0], ETH, "taker position: asset is wrong");

        // maker position
        assertEq(makerPosition.amount, expected.makerPositionAmount, "maker position: amount is wrong");
        assertEq(
            makerPosition.openNotional, expected.makerPositionOpenNotional, "maker position: open notional is wrong"
        );
        assertEq(makerPosition.leverage, params.makerLeverage, "maker position: leverage is wrong");
        assertEq(makerPosition.isLong, expected.makerPositionIsLong, "maker position: is long is wrong");
        assertTrue(makerPosition.amount != 0, "maker position: amount should not be zero");
        assertTrue(
            makerPosition.amount < state.makerPosition.amount, "maker position: amount should be less than original"
        );
        assertEq(perpManager.getAssets(maker, 1).length, 1, "maker position: should have one position");
        assertEq(perpManager.getAssets(maker, 1)[0], ETH, "maker position: asset is wrong");

        // margin account balances
        assertEq(uint256(perpManager.getMarginBalance(taker, 1)), expected.takerMargin, "taker margin is wrong");
        assertEq(uint256(perpManager.getMarginBalance(maker, 1)), expected.makerMargin, "maker margin is wrong");

        // taker collateral balances
        assertEq(
            perpManager.getFreeCollateralBalance(taker) - state.takerCollateral,
            expected.takerCollateralReturned,
            "taker collateral balance is wrong"
        );
        assertEq(state.takerBalance - usdc.balanceOf(taker), 0, "taker balance is wrong");

        // maker collateral balances
        assertEq(state.makerBalance - usdc.balanceOf(maker), 0, "maker balance is wrong");
        assertEq(
            perpManager.getFreeCollateralBalance(maker) - state.makerCollateral,
            expected.makerCollateralReturned,
            "maker collateral balance is wrong"
        );

        // protocol
        assertEq(
            perpManager.getInsuranceFundBalance() - state.insuranceFundBalance,
            expected.takerFee + expected.makerFee,
            "insurance fund balance is wrong"
        );
        assertEq(
            usdc.balanceOf(address(perpManager)),
            perpManager.getInsuranceFundBalance() + uint256(perpManager.getMarginBalance(taker, 1))
                + perpManager.getFreeCollateralBalance(taker) + uint256(perpManager.getMarginBalance(maker, 1))
                + perpManager.getFreeCollateralBalance(maker) + remainingBookCollateral,
            "perp manager balance is wrong"
        );
        if (params.side == Side.BUY) {
            assertEq(state.quoteBookOI - quoteBookOI, expected.quoteTraded, "quote book oi is wrong");
            assertEq(state.baseBookOI - baseBookOI, 0, "base book oi is wrong");
        } else {
            assertEq(state.baseBookOI - baseBookOI, expected.baseTraded, "base book oi is wrong");
            assertEq(state.quoteBookOI - quoteBookOI, 0, "quote book oi is wrong");
        }
        assertEq(state.longOI - longOI, expected.baseTraded, "long oi is wrong");
        assertEq(state.shortOI - shortOI, expected.baseTraded, "short oi is wrong");
    }

    function _getPnl(bool isLong, uint256 currentNotional, uint256 openNotional) internal pure returns (int256) {
        if (isLong) return int256(currentNotional) - int256(openNotional);
        else return int256(openNotional) - int256(currentNotional);
    }

    function _calcMarginSettle(CollateralizeCache memory cache)
        internal
        view
        returns (uint256 remainingMargin, uint256 closedMargin)
    {
        cache.margin += cache.rpnl;

        uint256 currentNotional = cache.size.fullMulDiv(perpManager.getMarkPrice(ETH), 1e18);
        int256 upnl = _getPnl(cache.isLong, currentNotional, cache.openNotional);

        int256 equity = cache.margin + upnl - cache.estimatedClosedMargin.toInt256();
        int256 intendedMargin = currentNotional.fullMulDiv(1e18, cache.leverage).toInt256();

        int256 overCollateralization = equity - intendedMargin;

        if (overCollateralization < 0) {
            overCollateralization += cache.estimatedClosedMargin.toInt256();

            if (overCollateralization > 0) closedMargin = uint256(overCollateralization);
        } else {
            closedMargin = cache.estimatedClosedMargin;
        }

        remainingMargin = uint256(cache.margin) - closedMargin;
    }

    function _getLiquidationPrice(bytes32 asset, uint256 amount, uint256 leverage, Side liquidateeSide)
        internal
        view
        returns (uint256 liquidationPrice)
    {
        uint256 currentPrice = perpManager.getMarkPrice(asset);

        uint256 margin = amount.fullMulDiv(perpManager.getMarkPrice(asset), leverage);

        uint256 minMarginRatio = perpManager.getMinMarginRatio(asset);

        int256 side = liquidateeSide == Side.BUY ? int256(-1) : int256(1);

        uint256 numerator = (currentPrice.toInt256() + (margin.fullMulDiv(1e18, amount).toInt256() * side)).abs();
        uint256 denominator = (1e18 + minMarginRatio.toInt256() * side).abs();

        liquidationPrice = ((numerator).fullMulDiv(1e18, denominator).toInt256() + (side * 5)).abs();
    }

    function _conformAmountToLots(uint256 amount) internal view returns (uint256) {
        uint256 lotSize = perpManager.getLotSize(ETH);
        return amount / lotSize * lotSize;
    }

    function _toQuote(uint256 amount, uint256 price) internal pure returns (uint256) {
        return amount.fullMulDiv(price, 1e18);
    }
}
