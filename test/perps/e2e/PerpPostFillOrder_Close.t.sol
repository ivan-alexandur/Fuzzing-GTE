// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "../PerpManagerTestBase.sol";

contract PerpPostFillOrder_Close_Test is PerpManagerTestBase {
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
        uint256 originalMakerFee;
        uint256 quoteBookOI;
        uint256 baseBookOI;
        uint256 orderCollateral;
        uint256 longOI;
        uint256 shortOI;
    }

    struct FillOrderParams {
        Side side;
        uint256 amount;
        uint256 makerLeverage;
        uint256 takerLeverage;
        uint256 price;
        bool makerReduceOnly;
    }

    struct ExpectedResult {
        uint256 takerCollateralReturned;
        uint256 makerCollateralReturned;
        uint256 makerOrderRefund;
        uint256 quoteTraded;
        uint256 baseTraded;
        uint256 takerFee;
        uint256 makerFee;
        int256 takerRpnl;
        int256 makerRpnl;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                              CLOSE LONG
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_Perp_Fill_Close_PositiveRpnl_Long(uint256) public {
        params.side = Side.BUY;
        params.makerReduceOnly = _randomChance(2);
        params.amount = _hem(_random(), 1e18, 100e18);
        params.makerLeverage = _hem(_random(), 1e18, 50e18);
        params.takerLeverage = _hem(_random(), 1e18, 50e18);
        params.price = _hem(
            _random(),
            perpManager.getMarkPrice(ETH),
            _getBankruptcyPrice(
                ETH, params.amount, params.makerLeverage, params.side == Side.BUY ? Side.SELL : Side.BUY
            )
        );

        params.price -= params.price % perpManager.getTickSize(ETH);

        _perpCloseHelper();
    }

    function test_Perp_Fill_Close_NegativeRpnl_Long(uint256) public {
        params.side = Side.BUY;
        params.makerReduceOnly = _randomChance(2);
        params.amount = _hem(_random(), 1e18, 100e18);
        params.makerLeverage = _hem(_random(), 2e18, 50e18);
        params.takerLeverage = _hem(_random(), 2e18, 50e18);
        params.price = _hem(
            _random(),
            _getBankruptcyPrice(ETH, params.amount, params.takerLeverage, params.side),
            perpManager.getMarkPrice(ETH)
        );

        params.price -= params.price % perpManager.getTickSize(ETH);

        _perpCloseHelper();
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                             CLOSE SHORT
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_Perp_Fill_Close_NegativeRpnl_Short(uint256) public {
        params.side = Side.SELL;
        params.makerReduceOnly = _randomChance(2);
        params.amount = _hem(_random(), 1e18, 100e18);
        params.makerLeverage = _hem(_random(), 1e18, 50e18);
        params.takerLeverage = _hem(_random(), 1e18, 50e18);
        params.price = _hem(
            _random(),
            perpManager.getMarkPrice(ETH),
            _getBankruptcyPrice(ETH, params.amount, params.takerLeverage, params.side)
        );

        params.price -= params.price % perpManager.getTickSize(ETH);

        _perpCloseHelper();
    }

    function test_Perp_Fill_Close_PositiveRpnl_Short(uint256) public {
        params.side = Side.SELL;
        params.makerReduceOnly = _randomChance(2);
        params.amount = _hem(_random(), 1e18, 100e18);
        params.makerLeverage = _hem(_random(), 1e18, 50e18);
        params.takerLeverage = _hem(_random(), 1e18, 50e18);
        params.price = _hem(
            _random(),
            _getBankruptcyPrice(
                ETH, params.amount, params.makerLeverage, params.side == Side.BUY ? Side.SELL : Side.BUY
            ) + 10 * perpManager.getTickSize(ETH), // adding a buffer to prevent maker to be within liquidatable range
            perpManager.getMarkPrice(ETH)
        );

        params.price -= params.price % perpManager.getTickSize(ETH);

        _perpCloseHelper();
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                             CLOSE FUNCTION
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_Perp_Fill_Close_CloseFunction() public {
        params.side = _randomChance(2) ? Side.BUY : Side.SELL;
        params.makerReduceOnly = _randomChance(2);
        params.amount = _hem(_random(), 1e18, 100e18);
        params.makerLeverage = _hem(_random(), 1e18, 50e18);
        params.takerLeverage = _hem(_random(), 1e18, 50e18);

        uint256 makerLoss = _getBankruptcyPrice(
            ETH, params.amount, params.makerLeverage, params.side == Side.BUY ? Side.SELL : Side.BUY
        );
        uint256 takerLoss = _getBankruptcyPrice(ETH, params.amount, params.takerLeverage, params.side);

        (uint256 max, uint256 min) = params.side == Side.BUY ? (makerLoss, takerLoss) : (takerLoss, makerLoss);

        params.price = _hem(_random(), min, max);
        params.price -= params.price % perpManager.getTickSize(ETH);

        _perpCloseHelperCloseFunction();
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _perpCloseHelper() public {
        vm.prank(maker);
        perpManager.setPositionLeverage({asset: ETH, account: maker, subaccount: 1, newLeverage: params.makerLeverage});

        vm.prank(taker);
        perpManager.setPositionLeverage({asset: ETH, account: taker, subaccount: 1, newLeverage: params.takerLeverage});

        params.amount = _conformAmountToLots(params.amount);

        _placeTrade({
            subaccount: 1,
            asset: ETH,
            taker: taker,
            maker: maker,
            price: perpManager.getMarkPrice(ETH),
            amount: params.amount,
            side: params.side
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
            reduceOnly: params.makerReduceOnly
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

        vm.prank(admin);
        perpManager.mockSetMarkPrice(ETH, params.price);

        vm.prank(maker);
        perpManager.placeOrder(maker, makerArgs);

        _cachePreFillState();
        _predictFillOrderResult();
        // _expectEvents();

        vm.prank(taker);
        PlaceOrderResult memory result = perpManager.placeOrder(taker, takerArgs);

        _assertPostFillState(result);
    }

    function _perpCloseHelperCloseFunction() public {
        vm.prank(maker);
        perpManager.setPositionLeverage({asset: ETH, account: maker, subaccount: 1, newLeverage: params.makerLeverage});

        vm.prank(taker);
        perpManager.setPositionLeverage({asset: ETH, account: taker, subaccount: 1, newLeverage: params.takerLeverage});

        params.amount = _conformAmountToLots(params.amount);

        _placeTrade({
            subaccount: 1,
            asset: ETH,
            taker: taker,
            maker: maker,
            price: perpManager.getMarkPrice(ETH),
            amount: params.amount,
            side: params.side
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
            reduceOnly: params.makerReduceOnly
        });

        PlaceOrderArgs memory closeArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: params.side == Side.BUY ? Side.SELL : Side.BUY,
            limitPrice: params.price,
            amount: params.amount,
            baseDenominated: true,
            tif: TiF.IOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: true
        });

        vm.prank(admin);
        perpManager.mockSetMarkPrice(ETH, params.price);

        vm.prank(maker);
        perpManager.placeOrder(maker, makerArgs);

        _cachePreFillState();
        _predictFillOrderResult();
        // _expectEvents();

        vm.prank(taker);
        PlaceOrderResult memory result = perpManager.placeOrder(taker, closeArgs);

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
        (state.longOI, state.shortOI) = perpManager.getOpenInterest(ETH);

        if (params.side == Side.BUY) {
            assertTrue(state.takerPosition.isLong, "taker position should be long");
            assertFalse(state.makerPosition.isLong, "maker position should be short");
        } else {
            assertFalse(state.takerPosition.isLong, "taker position should be short");
            assertTrue(state.makerPosition.isLong, "maker position should be long");
        }
    }

    function _predictFillOrderResult() public {
        expected.quoteTraded = params.amount.fullMulDiv(params.price, 1e18);
        expected.baseTraded = params.amount;
        expected.takerFee = expected.quoteTraded * TAKER_BASE_FEE_RATE / 10_000_000;
        expected.makerFee = expected.quoteTraded * MAKER_BASE_FEE_RATE / 10_000_000;

        expected.takerRpnl = _getPnl(state.takerPosition.isLong, expected.quoteTraded, state.takerPosition.openNotional);
        expected.makerRpnl = _getPnl(state.makerPosition.isLong, expected.quoteTraded, state.makerPosition.openNotional);

        int256 marginAfterRpnlAndFee = state.takerMargin.toInt256() + expected.takerRpnl - expected.takerFee.toInt256();

        assertTrue(marginAfterRpnlAndFee >= 0, "taker should have no bad debt");

        expected.takerCollateralReturned = marginAfterRpnlAndFee.abs();

        marginAfterRpnlAndFee = state.makerMargin.toInt256() + expected.makerRpnl - expected.makerFee.toInt256();
        console.log("marginAfterRpnlAndFee", marginAfterRpnlAndFee);
        console.log("expected.makerRpnl", expected.makerRpnl);
        console.log("expected.makerFee", expected.makerFee);
        console.log("state.makerMargin", state.makerMargin);
        // assertTrue(marginAfterRpnlAndFee >= 0, "maker should have no bad debt");

        expected.makerCollateralReturned = marginAfterRpnlAndFee.abs();

        if (!params.makerReduceOnly) {
            expected.makerOrderRefund = expected.quoteTraded.fullMulDiv(1e18, params.makerLeverage);
        }
    }

    function _assertPostFillState(PlaceOrderResult memory result) internal view {
        Position memory takerPosition = perpManager.getPosition(ETH, taker, 1);
        Position memory makerPosition = perpManager.getPosition(ETH, maker, 1);

        // result
        if (params.side == Side.BUY) {
            assertEq(result.quoteTraded, expected.quoteTraded, "result: quote traded is wrong");
            assertEq(result.baseTraded, expected.baseTraded, "result: base traded is wrong");
        } else {
            assertEq(result.quoteTraded, expected.quoteTraded, "result: quote traded is wrong");
            assertEq(result.baseTraded, expected.baseTraded, "result: base traded is wrong");
        }

        // taker position
        assertFalse(takerPosition.isLong, "taker position should be closed");
        assertEq(takerPosition.openNotional, 0, "taker position open notional should be 0");
        assertEq(takerPosition.amount, 0, "taker position base amount should be 0");
        assertEq(takerPosition.leverage, params.takerLeverage, "taker position leverage is wrong");
        assertEq(perpManager.getAssets(taker, 1).length, 0, "taker position: should have no positions");

        // maker position
        assertFalse(makerPosition.isLong, "maker position should be closed");
        assertEq(makerPosition.openNotional, 0, "maker position open notional should be 0");
        assertEq(makerPosition.amount, 0, "maker position base amount should be 0");
        assertEq(makerPosition.leverage, params.makerLeverage, "maker position leverage is wrong");
        assertEq(perpManager.getAssets(maker, 1).length, 0, "maker position: should have no positions");

        // taker margin
        assertEq(perpManager.getMarginBalance(taker, 1), 0, "taker margin should be 0");

        // maker margin
        assertEq(perpManager.getMarginBalance(maker, 1), 0, "maker margin should be 0");

        // taker collateral
        assertEq(usdc.balanceOf(taker), state.takerBalance, "taker collateral is wrong");
        assertEq(
            perpManager.getFreeCollateralBalance(taker) - state.takerCollateral,
            expected.takerCollateralReturned,
            "taker collateral balance is wrong"
        );

        // maker collateral
        assertEq(
            perpManager.getFreeCollateralBalance(maker) - state.makerCollateral,
            expected.makerCollateralReturned + expected.makerOrderRefund,
            "maker collateral balance is wrong"
        );
        assertEq(usdc.balanceOf(maker), state.makerBalance, "maker collateral is wrong");

        // protocol
        assertEq(
            perpManager.getInsuranceFundBalance() - state.insuranceFundBalance,
            expected.takerFee + expected.makerFee,
            "insurance fund balance is wrong"
        );
        assertTrue(
            usdc.balanceOf(address(perpManager)).dist(
                perpManager.getInsuranceFundBalance() + perpManager.getFreeCollateralBalance(taker)
                    + perpManager.getFreeCollateralBalance(maker)
            ) <= 1,
            "protocol balance is wrong"
        );
    }

    function _getPnl(bool isLong, uint256 currentNotional, uint256 openNotional) internal pure returns (int256) {
        if (isLong) return int256(currentNotional) - int256(openNotional);
        else return int256(openNotional) - int256(currentNotional);
    }

    function _getBankruptcyPrice(bytes32 asset, uint256 amount, uint256 leverage, Side liquidateeSide)
        internal
        view
        returns (uint256 bankruptcyPrice)
    {
        uint256 currentPrice = perpManager.getMarkPrice(asset);

        uint256 openNotional = amount.fullMulDiv(currentPrice, 1e18);
        uint256 margin = openNotional.fullMulDiv(1e18, leverage);

        int256 side = liquidateeSide == Side.BUY ? int256(-1) : int256(1);
        uint256 numerator = (openNotional.toInt256() + (margin.toInt256() * side)).abs();

        bankruptcyPrice = numerator.fullMulDiv(1e18, amount);

        uint256 notional = bankruptcyPrice.fullMulDiv(amount, 1e18);
        uint256 fee = notional.fullMulDiv(perpManager.getLiquidationFeeRate(asset), 1e18);

        if (liquidateeSide == Side.BUY) bankruptcyPrice += fee.fullMulDiv(1e18, amount);
        else bankruptcyPrice -= fee.fullMulDiv(1e18, amount);
    }

    function _getLiquidationPrice(bytes32 asset, uint256 amount, uint256 leverage, Side liquidateeSide, bool isTaker)
        internal
        view
        returns (uint256 liquidationPrice)
    {
        uint256 currentPrice = perpManager.getMarkPrice(asset);

        uint256 notional = currentPrice.fullMulDiv(amount, 1e18);

        uint256 margin = amount.fullMulDiv(perpManager.getMarkPrice(asset), leverage);

        if (isTaker) margin -= notional * TAKER_BASE_FEE_RATE / 10_000_000;
        else margin = margin - (notional * MAKER_BASE_FEE_RATE / 10_000_000) - state.originalMakerFee;

        uint256 minMarginRatio = perpManager.getMinMarginRatio(asset);

        int256 side = liquidateeSide == Side.BUY ? int256(-1) : int256(1);

        uint256 numerator = (currentPrice.toInt256() + (margin.fullMulDiv(1e18, amount).toInt256() * side)).abs();
        uint256 denominator = (1e18 + minMarginRatio.toInt256() * side).abs();

        liquidationPrice = ((numerator).fullMulDiv(1e18, denominator).toInt256() + (side * 1)).abs();
    }

    function _conformAmountToLots(uint256 amount) internal view returns (uint256) {
        uint256 lotSize = perpManager.getLotSize(ETH);
        return amount / lotSize * lotSize;
    }
}
