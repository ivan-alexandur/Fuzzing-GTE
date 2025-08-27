// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "../PerpManagerTestBase.sol";

contract PerpPostFillOrder_Increase_Test is PerpManagerTestBase {
    using FixedPointMathLib for *;
    using SafeCastLib for uint256;

    function setUp() public override {
        super.setUp();

        taker = rite;
        maker = jb;
    }

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
        uint256 quoteBookOI;
        uint256 baseBookOI;
        uint256 longOI;
        uint256 shortOI;
        int256 cumulativeFunding;
    }

    struct FillOrderParams {
        Side side;
        uint256 price;
        uint256 takerOrderAmount;
        uint256 makerOrderAmount;
        uint256 takerLeverage;
        uint256 makerLeverage;
        bool baseDenominated;
    }

    struct ExpectedResult {
        uint256 takerMargin;
        uint256 makerMargin;
        uint256 takerMarginOwed;
        uint256 makerFilledOrderValue;
        uint256 makerOrderRefund;
        uint256 quoteTraded;
        uint256 baseTraded;
        uint256 takerFee;
        uint256 makerFee;
        uint256 takerPositionAmount;
        uint256 makerPositionAmount;
        uint256 takerPositionOpenNotional;
        uint256 makerPositionOpenNotional;
        bool takerPositionIsLong;
        bool makerPositionIsLong;
    }

    State state;
    FillOrderParams params;
    ExpectedResult expected;

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                SUCCESS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// forge-config: default.fuzz.runs = 5000
    function test_Perp_Fill_Increase_Success(uint256) public {
        _fuzzParams();

        PlaceOrderArgs memory makerArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: params.side == Side.BUY ? Side.SELL : Side.BUY,
            limitPrice: params.price,
            amount: params.makerOrderAmount,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        PlaceOrderArgs memory takerArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: params.side,
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

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _fuzzParams() internal {
        params = FillOrderParams({
            side: _randomChance(2) ? Side.BUY : Side.SELL,
            price: 4000e18,
            takerOrderAmount: _hem(_random(), 1e18, 20e18),
            makerOrderAmount: _conformLots(ETH, _hem(_random(), 1e18, 20e18)),
            takerLeverage: _hem(_random(), 1e18, 20e18),
            makerLeverage: _hem(_random(), 1e18, 20e18),
            baseDenominated: _randomChance(2)
        });

        if (!params.baseDenominated) params.takerOrderAmount = _toQuote(params.takerOrderAmount, params.price);

        _setPositionLeverage();

        _placeTrade({
            subaccount: 1,
            asset: ETH,
            taker: taker,
            maker: maker,
            price: 4000e18,
            amount: _conformAmountToLots(_hem(_random(), 1e18, 20e18)),
            side: params.side
        });

        int256 newCumulativeFunding = _hem(_random(), 0.1e18, 0.5e18).toInt256();

        if (_randomChance(2)) newCumulativeFunding = -newCumulativeFunding;

        perpManager.mockSetCumulativeFunding(ETH, newCumulativeFunding);
    }

    function _setPositionLeverage() internal {
        vm.prank(maker);
        perpManager.setPositionLeverage({asset: ETH, account: maker, subaccount: 1, newLeverage: params.makerLeverage});

        vm.prank(taker);
        perpManager.setPositionLeverage({asset: ETH, account: taker, subaccount: 1, newLeverage: params.takerLeverage});
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
        state.cumulativeFunding = perpManager.getCumulativeFunding(ETH);

        if (params.side == Side.BUY) {
            assertTrue(state.takerPosition.isLong, "taker position before: wrong side");
            assertFalse(state.makerPosition.isLong, "maker position before: wrong side");
            assertTrue(state.baseBookOI > 0, "base book oi wrong");
            assertEq(state.quoteBookOI, 0, "quote book oi wrong");
        } else {
            assertFalse(state.takerPosition.isLong, "taker position before: wrong side");
            assertTrue(state.makerPosition.isLong, "maker position before: wrong side");
            assertTrue(state.quoteBookOI > 0, "quote book oi wrong");
            assertEq(state.baseBookOI, 0, "base book oi wrong");
        }
        assertTrue(
            state.makerPosition.amount != 0 && state.takerPosition.amount != 0,
            "Positions should be empty before fill order"
        );
    }

    function _predictFillOrderResult() internal {
        expected.baseTraded =
            params.baseDenominated ? params.takerOrderAmount : params.takerOrderAmount.fullMulDiv(1e18, params.price);
        expected.baseTraded = expected.baseTraded.min(params.makerOrderAmount);
        expected.baseTraded = _conformAmountToLots(expected.baseTraded);
        expected.quoteTraded = expected.baseTraded.fullMulDiv(params.price, 1e18);

        expected.takerPositionAmount = expected.makerPositionAmount = expected.baseTraded + state.takerPosition.amount;
        expected.takerPositionOpenNotional =
            expected.makerPositionOpenNotional = state.takerPosition.openNotional + expected.quoteTraded;

        expected.takerFee = expected.quoteTraded * TAKER_BASE_FEE_RATE / 10_000_000;
        expected.makerFee = expected.quoteTraded * MAKER_BASE_FEE_RATE / 10_000_000;

        expected.takerPositionIsLong = state.takerPosition.isLong;
        expected.makerPositionIsLong = state.makerPosition.isLong;

        expected.takerMarginOwed = expected.quoteTraded.fullMulDiv(1e18, params.takerLeverage);
        expected.makerFilledOrderValue = expected.quoteTraded.fullMulDiv(1e18, params.makerLeverage);

        (expected.takerMargin, expected.takerMarginOwed) = _rebalanceOpen({
            estimatedMarginOwed: expected.takerMarginOwed,
            intendedMargin: expected.takerPositionOpenNotional.fullMulDiv(1e18, params.takerLeverage),
            marginAfterFunding: state.takerMargin.toInt256() - expected.takerFee.toInt256()
                - perpManager.getPendingFundingPayment(taker, 1)
        });

        uint256 makerMarginOwed;
        (expected.makerMargin, makerMarginOwed) = _rebalanceOpen({
            estimatedMarginOwed: expected.makerFilledOrderValue,
            intendedMargin: expected.makerPositionOpenNotional.fullMulDiv(1e18, params.makerLeverage),
            marginAfterFunding: state.makerMargin.toInt256() - expected.makerFee.toInt256()
                - perpManager.getPendingFundingPayment(maker, 1)
        });

        if (makerMarginOwed < expected.makerFilledOrderValue) {
            expected.makerOrderRefund = expected.makerFilledOrderValue - makerMarginOwed;
        }
    }

    function _rebalanceOpen(uint256 estimatedMarginOwed, uint256 intendedMargin, int256 marginAfterFunding)
        internal
        pure
        returns (uint256 margin, uint256 marginOwed)
    {
        int256 overCollateralization = marginAfterFunding + estimatedMarginOwed.toInt256() - intendedMargin.toInt256();

        if (overCollateralization > 0) {
            overCollateralization -= estimatedMarginOwed.toInt256();

            if (overCollateralization < 0) marginOwed = uint256(-overCollateralization);
        } else {
            marginOwed = estimatedMarginOwed;
        }

        if (marginAfterFunding + marginOwed.toInt256() < 0) revert("BAD DEBT");

        margin = uint256(marginAfterFunding + marginOwed.toInt256());
    }

    function _assertPostFillState(PlaceOrderResult memory result) internal view {
        Position memory takerPosition = perpManager.getPosition(ETH, taker, 1);
        Position memory makerPosition = perpManager.getPosition(ETH, maker, 1);
        (uint256 baseBookOI, uint256 quoteBookOI) = perpManager.getOpenInterestBook(ETH);
        (uint256 longOI, uint256 shortOI) = perpManager.getOpenInterest(ETH);

        uint256 remainingBookCollateral;
        if (params.side == Side.BUY && baseBookOI > 0) {
            uint256 orderCollateral = params.makerOrderAmount.fullMulDiv(params.price, params.makerLeverage);
            remainingBookCollateral = orderCollateral - expected.makerFilledOrderValue;
        } else if (quoteBookOI > 0) {
            uint256 orderCollateral = params.makerOrderAmount.fullMulDiv(params.price, params.makerLeverage);
            remainingBookCollateral = orderCollateral - expected.makerFilledOrderValue;
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
        assertEq(
            takerPosition.lastCumulativeFunding,
            state.cumulativeFunding,
            "taker position: last cumulative funding is wrong"
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
        assertEq(
            makerPosition.lastCumulativeFunding,
            state.cumulativeFunding,
            "maker position: last cumulative funding is wrong"
        );
        assertEq(perpManager.getAssets(maker, 1).length, 1, "maker position: should have one position");
        assertEq(perpManager.getAssets(maker, 1)[0], ETH, "maker position: asset is wrong");

        // margin account balances
        assertEq(uint256(perpManager.getMarginBalance(taker, 1)), expected.takerMargin, "taker margin is wrong");
        assertEq(uint256(perpManager.getMarginBalance(maker, 1)), expected.makerMargin, "maker margin is wrong");

        // taker collateral balances
        assertEq(
            state.takerCollateral - perpManager.getFreeCollateralBalance(taker),
            expected.takerMarginOwed,
            "taker collateral balance is wrong"
        );
        assertEq(state.takerBalance - usdc.balanceOf(taker), 0, "taker balance is wrong");

        // maker collateral balances
        assertEq(state.makerBalance - usdc.balanceOf(maker), 0, "maker balance is wrong");
        assertEq(
            perpManager.getFreeCollateralBalance(maker) - state.makerCollateral,
            expected.makerOrderRefund,
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
            assertEq(state.baseBookOI - baseBookOI, expected.baseTraded, "base book oi is wrong");
            assertEq(state.quoteBookOI - quoteBookOI, 0, "quote book oi is wrong");
        } else {
            assertEq(state.quoteBookOI - quoteBookOI, expected.quoteTraded, "quote book oi is wrong");
            assertEq(state.baseBookOI - baseBookOI, 0, "base book oi is wrong");
        }

        assertEq(longOI, state.longOI + expected.baseTraded, "long oi is wrong");
        assertEq(shortOI, state.shortOI + expected.baseTraded, "short oi is wrong");
    }

    function _conformAmountToLots(uint256 amount) internal view returns (uint256) {
        uint256 lotSize = perpManager.getLotSize(ETH);
        return amount / lotSize * lotSize;
    }

    function _toQuote(uint256 amount, uint256 price) internal pure returns (uint256) {
        return amount.fullMulDiv(price, 1e18);
    }
}
