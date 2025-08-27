// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "../PerpManagerTestBase.sol";

contract PerpPostFillOrder_ReverseOpen_Test is PerpManagerTestBase {
    using FixedPointMathLib for *;
    using SafeCastLib for *;

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                SETUP
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function setUp() public override {
        super.setUp();

        taker = rite;
        maker = jb;
    }

    State state;
    Params params;
    ExpectedResult expected;

    address taker;
    address maker;

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
        uint256 orderCollateral;
        uint256 longOI;
        uint256 shortOI;
    }

    struct Params {
        Side side;
        uint256 price;
        uint256 originalAmount;
        uint256 amount;
        uint256 takerLeverage;
        uint256 makerLeverage;
    }

    struct ExpectedResult {
        uint256 baseTraded;
        uint256 quoteTraded;
        int256 takerRpnl;
        int256 makerRpnl;
        uint256 takerPositionAmount;
        uint256 makerPositionAmount;
        uint256 takerPositionMargin;
        uint256 makerPositionMargin;
        uint256 takerPositionOpenNotional;
        uint256 makerPositionOpenNotional;
        bool takerPositionIsLong;
        bool makerPositionIsLong;
        int256 makerMargin;
        int256 takerMargin;
        uint256 takerFee;
        uint256 makerFee;
        int256 makerCollateralDelta;
        int256 takerCollateralDelta;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                         REVERSE OPEN FROM LONG
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_Perp_Fill_ReverseOpen_PositivePnl_Long(uint256) public {
        params.side = Side.BUY;
        params.originalAmount = _hem(_random(), 1e18, 100e18);
        params.amount = _hem(_random(), params.originalAmount + 1e18, 200e18);
        params.takerLeverage = _hem(_random(), 1e18, 50e18);
        params.makerLeverage = _hem(_random(), 1e18, 50e18);
        params.price = _hem(
            _random(),
            perpManager.getMarkPrice(ETH),
            _getLossPrice(
                ETH, params.originalAmount, params.makerLeverage, params.side == Side.BUY ? Side.SELL : Side.BUY
            )
        );

        params.price -= params.price % perpManager.getTickSize(ETH);

        _reverseOpenHelper();

        assertTrue(expected.takerRpnl >= 0, "taker pnl must be positive");
        assertTrue(expected.makerRpnl <= 0, "maker pnl must be negative");
    }

    function test_Perp_Fill_ReverseOpen_NegativePnl_Long(uint256) public {
        params.side = Side.BUY;
        params.originalAmount = _hem(_random(), 1e18, 100e18);
        params.amount = _hem(_random(), params.originalAmount + 1e18, 200e18);
        params.takerLeverage = _hem(_random(), 1e18, 50e18);
        params.makerLeverage = _hem(_random(), 1e18, 50e18);
        params.price = _hem(
            _random(),
            _getLossPrice(ETH, params.originalAmount, params.takerLeverage, params.side),
            perpManager.getMarkPrice(ETH)
        );

        params.price -= params.price % perpManager.getTickSize(ETH);

        _reverseOpenHelper();

        assertTrue(expected.takerRpnl <= 0, "taker pnl must be negative");
        assertTrue(expected.makerRpnl >= 0, "maker pnl must be positive");
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                        REVERSE OPEN FROM SHORT
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_Perp_Fill_ReverseOpen_PositivePnl_Short(uint256) public {
        params.side = Side.SELL;
        params.originalAmount = _hem(_random(), 1e18, 100e18);
        params.amount = _hem(_random(), params.originalAmount + 1e18, 200e18);
        params.takerLeverage = _hem(_random(), 1e18, 50e18);
        params.makerLeverage = _hem(_random(), 1e18, 50e18);
        params.price = _hem(
            _random(),
            _getLossPrice(
                ETH, params.originalAmount, params.makerLeverage, params.side == Side.BUY ? Side.SELL : Side.BUY
            ),
            perpManager.getMarkPrice(ETH)
        );

        params.price -= params.price % perpManager.getTickSize(ETH);

        _reverseOpenHelper();

        assertTrue(expected.takerRpnl >= 0, "taker pnl must be positive");
        assertTrue(expected.makerRpnl <= 0, "maker pnl must be negative");
    }

    function test_Perp_Fill_ReverseOpen_NegativePnl_Short(uint256) public {
        params.side = Side.SELL;
        params.originalAmount = _hem(_random(), 1e18, 100e18);
        params.amount = _hem(_random(), params.originalAmount + 1e18, 200e18);
        params.takerLeverage = _hem(_random(), 1e18, 50e18);
        params.makerLeverage = _hem(_random(), 1e18, 50e18);
        params.price = _hem(
            _random(),
            perpManager.getMarkPrice(ETH),
            _getLossPrice(ETH, params.originalAmount, params.takerLeverage, params.side)
        );

        params.price -= params.price % perpManager.getTickSize(ETH);

        _reverseOpenHelper();

        assertTrue(expected.takerRpnl <= 0, "taker pnl must be negative");
        assertTrue(expected.makerRpnl >= 0, "maker pnl must be positive");
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _reverseOpenHelper() internal {
        vm.prank(maker);
        perpManager.setPositionLeverage(ETH, maker, 1, params.makerLeverage);
        vm.prank(taker);
        perpManager.setPositionLeverage(ETH, taker, 1, params.takerLeverage);

        params.originalAmount = _conformAmountToLots(params.originalAmount);
        params.amount = _conformAmountToLots(params.amount);

        _placeTrade({
            asset: ETH,
            taker: taker,
            maker: maker,
            price: perpManager.getMarkPrice(ETH),
            amount: params.originalAmount,
            side: params.side,
            subaccount: 1
        });

        PlaceOrderArgs memory makerArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: params.side,
            limitPrice: params.price,
            amount: params.amount,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        PlaceOrderArgs memory takerArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: params.side == Side.BUY ? Side.SELL : Side.BUY,
            limitPrice: params.price,
            amount: params.amount,
            baseDenominated: true,
            tif: TiF.IOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        vm.prank(maker);
        state.orderId = perpManager.placeOrder(maker, makerArgs).orderId;

        vm.prank(admin);
        perpManager.mockSetMarkPrice(ETH, params.price);

        _cachePreFillState();
        _predictFillResult();
        // _expectEvents();

        vm.prank(taker);
        PlaceOrderResult memory result = perpManager.placeOrder(taker, takerArgs);

        _assertPostFillState(result);
    }

    function _cachePreFillState() internal {
        state.takerBalance = usdc.balanceOf(taker);
        state.makerBalance = usdc.balanceOf(maker);
        state.takerCollateral = perpManager.getFreeCollateralBalance(taker);
        state.makerCollateral = perpManager.getFreeCollateralBalance(maker);
        state.takerMargin = uint256(perpManager.getMarginBalance(taker, 1));
        state.makerMargin = uint256(perpManager.getMarginBalance(maker, 1));
        state.makerPosition = perpManager.getPosition(ETH, maker, 1);
        state.takerPosition = perpManager.getPosition(ETH, taker, 1);
        state.insuranceFundBalance = perpManager.getInsuranceFundBalance();
        state.orderCollateral = params.amount.fullMulDiv(params.price, 1e18).fullMulDiv(1e18, params.makerLeverage);
    }

    function _predictFillResult() internal {
        // trade amounts
        expected.baseTraded = params.amount;
        expected.quoteTraded = expected.baseTraded.fullMulDiv(params.price, 1e18);

        uint256 currentNotional = expected.quoteTraded.fullMulDiv(state.takerPosition.amount, params.amount);

        // fee
        expected.takerFee = expected.quoteTraded * TAKER_BASE_FEE_RATE / 10_000_000;
        expected.makerFee = expected.quoteTraded * MAKER_BASE_FEE_RATE / 10_000_000;

        // taker position
        expected.takerPositionAmount = expected.baseTraded - state.takerPosition.amount;
        expected.takerPositionOpenNotional = expected.quoteTraded - currentNotional;
        expected.takerPositionIsLong = !state.takerPosition.isLong;

        // taker settle
        expected.takerRpnl = _getPnl(state.takerPosition.isLong, currentNotional, state.takerPosition.openNotional);

        int256 marginDelta = expected.takerPositionOpenNotional.fullMulDiv(1e18, params.takerLeverage).toInt256();

        (expected.takerMargin, expected.takerCollateralDelta) = _rebalance(
            marginDelta,
            expected.takerPositionAmount,
            expected.takerPositionOpenNotional,
            expected.takerPositionIsLong,
            state.takerMargin.toInt256() - expected.takerFee.toInt256() + expected.takerRpnl,
            params.takerLeverage
        );

        // maker position
        expected.makerPositionAmount = expected.baseTraded - state.makerPosition.amount;
        expected.makerPositionOpenNotional = expected.quoteTraded - currentNotional;
        expected.makerPositionIsLong = !state.makerPosition.isLong;

        // maker settle
        expected.makerRpnl = _getPnl(state.makerPosition.isLong, currentNotional, state.makerPosition.openNotional);

        marginDelta = expected.makerPositionOpenNotional.fullMulDiv(1e18, params.makerLeverage).toInt256();

        (expected.makerMargin, expected.makerCollateralDelta) = _rebalance(
            marginDelta,
            expected.makerPositionAmount,
            expected.makerPositionOpenNotional,
            expected.makerPositionIsLong,
            state.makerMargin.toInt256() - expected.makerFee.toInt256() + expected.makerRpnl,
            params.makerLeverage
        );

        // order refund
        expected.makerCollateralDelta -= expected.quoteTraded.fullMulDiv(1e18, params.makerLeverage).toInt256();
    }

    function _rebalance(
        int256 estimatedMarginDelta,
        uint256 size,
        uint256 openNotional,
        bool isLong,
        int256 margin,
        uint256 leverage
    ) internal view returns (int256 newMargin, int256 collateralDelta) {
        if (estimatedMarginDelta >= 0) {
            return _rebalanceOpen(estimatedMarginDelta, size, openNotional, isLong, margin, leverage);
        } else {
            return _rebalanceClose(estimatedMarginDelta, size, openNotional, isLong, margin, leverage);
        }
    }

    function _rebalanceOpen(
        int256 estimatedMarginDelta,
        uint256 size,
        uint256 openNotional,
        bool isLong,
        int256 margin,
        uint256 leverage
    ) internal view returns (int256 newMargin, int256 collateralDelta) {
        uint256 currentNotional = size.fullMulDiv(perpManager.getMarkPrice(ETH), 1e18);
        int256 upnl = _getPnl(isLong, currentNotional, openNotional);
        int256 intendedMargin = currentNotional.fullMulDiv(1e18, leverage).toInt256();

        int256 overCollateralization = margin + upnl + estimatedMarginDelta - intendedMargin;

        if (overCollateralization > 0) {
            overCollateralization -= estimatedMarginDelta;
            if (overCollateralization < 0) estimatedMarginDelta = -overCollateralization;
            else estimatedMarginDelta = 0;
        }

        margin += estimatedMarginDelta;

        return (margin, estimatedMarginDelta);
    }

    function _rebalanceClose(
        int256 estimatedMarginDelta,
        uint256 size,
        uint256 openNotional,
        bool isLong,
        int256 margin,
        uint256 leverage
    ) internal view returns (int256 newMargin, int256 collateralDelta) {
        uint256 currentNotional = size.fullMulDiv(perpManager.getMarkPrice(ETH), 1e18);
        int256 upnl = _getPnl(isLong, currentNotional, openNotional);
        int256 intendedMargin = currentNotional.fullMulDiv(1e18, leverage).toInt256();

        int256 overCollateralization = margin + upnl + estimatedMarginDelta - intendedMargin;

        if (overCollateralization < 0) {
            overCollateralization -= estimatedMarginDelta;

            if (overCollateralization > 0) estimatedMarginDelta = -overCollateralization;
            else estimatedMarginDelta = 0;
        }

        margin += estimatedMarginDelta;

        return (margin, estimatedMarginDelta);
    }

    function _assertPostFillState(PlaceOrderResult memory result) internal view {
        Position memory takerPosition = perpManager.getPosition(ETH, taker, 1);
        Position memory makerPosition = perpManager.getPosition(ETH, maker, 1);
        (uint256 longOI, uint256 shortOI) = perpManager.getOpenInterest(ETH);

        // result
        if (params.side == Side.BUY) {
            assertEq(result.quoteTraded, expected.quoteTraded, "result: quote traded is wrong");
            assertEq(result.baseTraded, expected.baseTraded, "result: base traded is wrong");
        } else {
            assertEq(result.quoteTraded, expected.quoteTraded, "result: quote traded is wrong");
            assertEq(result.baseTraded, expected.baseTraded, "result: base traded is wrong");
        }

        // taker position
        assertEq(takerPosition.amount, expected.takerPositionAmount, "taker position: amount is wrong");
        assertEq(
            takerPosition.openNotional, expected.takerPositionOpenNotional, "taker position: open notional is wrong"
        );
        assertEq(takerPosition.leverage, params.takerLeverage, "taker position: leverage is wrong");
        assertEq(takerPosition.isLong, expected.takerPositionIsLong, "taker position: is long is wrong");
        assertTrue(takerPosition.amount != 0, "taker position: amount should not be zero");
        assertEq(perpManager.getAssets(taker, 1).length, 1, "taker position: should have one position");

        // maker position
        assertEq(makerPosition.amount, expected.makerPositionAmount, "maker position: amount is wrong");
        assertEq(
            makerPosition.openNotional, expected.makerPositionOpenNotional, "maker position: open notional is wrong"
        );
        assertEq(makerPosition.leverage, params.makerLeverage, "maker position: leverage is wrong");
        assertEq(makerPosition.isLong, expected.makerPositionIsLong, "maker position: is long is wrong");
        assertTrue(makerPosition.amount != 0, "maker position: amount should not be zero");
        assertEq(perpManager.getAssets(maker, 1).length, 1, "maker position: should have one position");

        // margin
        assertEq(perpManager.getMarginBalance(maker, 1), expected.makerMargin, "maker margin is wrong");
        assertEq(perpManager.getMarginBalance(taker, 1), expected.takerMargin, "taker margin is wrong");

        // collateral
        assertEq(
            (state.takerCollateral).toInt256() - (perpManager.getFreeCollateralBalance(taker)).toInt256(),
            expected.takerCollateralDelta,
            "taker collateral is wrong"
        );
        assertEq(state.takerBalance - usdc.balanceOf(taker), 0, "taker asset bal is wrong");

        assertEq(
            (state.makerCollateral).toInt256() - (perpManager.getFreeCollateralBalance(maker)).toInt256(),
            expected.makerCollateralDelta,
            "maker collateral is wrong"
        );
        assertEq(state.makerBalance - usdc.balanceOf(maker), 0, "maker asset bal is wrong");

        uint256 assetSum = uint256(
            perpManager.getInsuranceFundBalance().toInt256() + perpManager.getMarginBalance(taker, 1)
                + perpManager.getFreeCollateralBalance(taker).toInt256() + perpManager.getMarginBalance(maker, 1)
                + perpManager.getFreeCollateralBalance(maker).toInt256()
        );

        // protocol
        assertEq(
            perpManager.getInsuranceFundBalance() - state.insuranceFundBalance,
            expected.takerFee + expected.makerFee,
            "insurance fund balance is wrong"
        );
        assertEq(usdc.balanceOf(address(perpManager)), assetSum, "perp manager balance is wrong");
        assertTrue(usdc.balanceOf(address(perpManager)) >= assetSum, "perp manager is insolvent");
        assertEq(longOI, expected.takerPositionAmount, "long open interest is wrong");
        assertEq(shortOI, expected.takerPositionAmount, "short open interest is wrong");
    }

    function _getPnl(bool isLong, uint256 currentNotional, uint256 openNotional) internal pure returns (int256) {
        if (isLong) return int256(currentNotional) - int256(openNotional);
        else return int256(openNotional) - int256(currentNotional);
    }

    function _getLossPrice(bytes32 asset, uint256 amount, uint256 leverage, Side liquidateeSide)
        internal
        view
        returns (uint256 lossPrice)
    {
        uint256 currentPrice = perpManager.getMarkPrice(asset);

        uint256 openNotional = amount.fullMulDiv(currentPrice, 1e18);
        uint256 margin = openNotional.fullMulDiv(1e18, leverage);

        margin -= margin.fullMulDiv(0.01 ether, 1e18); // allows for 99% loss

        int256 side = liquidateeSide == Side.BUY ? int256(-1) : int256(1);

        uint256 numerator = (openNotional.toInt256() + (margin.toInt256() * side)).abs();

        lossPrice = numerator.fullMulDiv(1e18, amount);
    }

    function _conformAmountToLots(uint256 amount) internal view returns (uint256) {
        uint256 lotSize = perpManager.getLotSize(ETH);
        return amount / lotSize * lotSize;
    }
}
