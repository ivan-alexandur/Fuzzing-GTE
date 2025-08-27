// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "../PerpManagerTestBase.sol";

contract PerpStandardLiquidation_Test is PerpManagerTestBase {
    using FixedPointMathLib for *;
    using SafeCastLib for uint256;

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                SETUP
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function setUp() public override {
        super.setUp();

        vm.prank(admin);
        perpManager.insuranceFundDeposit(5_000_000e18);
    }

    struct State {
        Position liquidateePosition;
        uint256 insuranceFundBalance;
        uint256 assetBalance;
        uint256 collateralBalance;
        int256 marginBalance;
        uint256 orderId;
        Position makerPosition;
        int256 makerMarginBalance;
    }

    struct ExpectedResult {
        uint256 collateralReturned;
        int256 marginBalance;
        uint256 liquidateeFee;
        int256 rpnl;
        uint256 makerFee;
        uint256 badDebt;
        uint256 positionAmount;
        uint256 positionOpenNotional;
        bool positionIsLong;
        int256 makerMarginBalance;
        uint256 makerPositionAmount;
        uint256 makerPositionOpenNotional;
        bool makerPositionIsLong;
        int256 makerRpnl;
        // Add fill amounts for events
        uint256 fillAmount;
        uint256 fillAmountRaw; // Un-conformed amount for FillOrderSubmitted
    }

    struct LiquidationParams {
        Side side;
        uint256 amount;
        uint256 leverage;
        uint256 liquidationLiquidity;
        uint256 price;
        uint256 liqPrice;
    }

    LiquidationParams params;
    State state;
    ExpectedResult expected;

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                 FULL
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_Perp_Liquidation_Full_No_Bankruptcy_Long(uint256) public {
        params.side = Side.BUY;
        params.amount = params.liquidationLiquidity = _hem(_randomUnique(), 1e18, 100e18);
        params.leverage = _hem(_randomUnique(), 20e18, 50e18);
        params.liqPrice = _getLiquidationPrice(ETH, params.amount, params.leverage, params.side, false);
        params.price = _hem(
            _randomUnique(),
            _getBankruptcyPrice(ETH, params.amount, params.leverage, params.side, true) + 1e18,
            _getLiquidationPrice(ETH, params.amount, params.leverage, params.side, true)
        );

        if (params.price == 0) {
            params.price = perpManager.getTickSize(ETH);
        } else {
            params.price += perpManager.getTickSize(ETH);
            params.price -= params.price % perpManager.getTickSize(ETH);
        }

        _liquidationHelper();
    }

    function test_Perp_Liquidation_Full_No_Bankruptcy_Short(uint256) public {
        params.side = Side.SELL;
        params.amount = params.liquidationLiquidity = _hem(_randomUnique(), 1e18, 100e18);
        params.leverage = _hem(_randomUnique(), 20e18, 50e18);
        params.liqPrice = _getLiquidationPrice(ETH, params.amount, params.leverage, params.side, false);
        params.price = _hem(
            _randomUnique(),
            _getLiquidationPrice(ETH, params.amount, params.leverage, params.side, true),
            _getBankruptcyPrice(ETH, params.amount, params.leverage, params.side, true) - 5000
        );

        if (params.price == 0) {
            params.price = perpManager.getTickSize(ETH);
        } else {
            params.price += perpManager.getTickSize(ETH);
            params.price -= params.price % perpManager.getTickSize(ETH);
        }

        _liquidationHelper();
    }

    function test_Perp_Liquidation_Full_Bankruptcy(uint256) public {
        params.side = Side.BUY;
        params.amount = params.liquidationLiquidity = _hem(_randomUnique(), 1e18, 100e18);
        params.leverage = _hem(_randomUnique(), 10e18, 50e18);
        params.liqPrice = _getLiquidationPrice(ETH, params.amount, params.leverage, params.side, false);
        params.price = _hem(
            _randomUnique(),
            _getLiquidationPriceWithBadDebt(ETH, params.amount, params.leverage, params.side, 10e18),
            _getBankruptcyPrice(ETH, params.amount, params.leverage, params.side, false)
        );

        if (params.price == 0) {
            params.price = perpManager.getTickSize(ETH);
        } else {
            params.price += perpManager.getTickSize(ETH);
            params.price -= params.price % perpManager.getTickSize(ETH);
        }

        _liquidationHelper();
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                PARTIAL
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_Perp_Liquidation_Partial_No_Bankruptcy(uint256) public {
        params.side = Side.BUY;
        params.amount = _hem(_randomUnique(), 10e18, 100e18);
        params.liquidationLiquidity = _hem(_randomUnique(), 1e18, params.amount);
        params.leverage = _hem(_randomUnique(), 10e18, 50e18);
        params.liqPrice = _getLiquidationPrice(ETH, params.amount, params.leverage, params.side, false);
        params.price = _hem(
            _randomUnique(),
            _getBankruptcyPrice(ETH, params.amount, params.leverage, params.side, true) + 1e18,
            _getLiquidationPrice(ETH, params.amount, params.leverage, params.side, true)
        );

        if (params.price == 0) params.price = perpManager.getTickSize(ETH);
        else params.price -= params.price % perpManager.getTickSize(ETH);

        _liquidationHelper();
    }

    function test_Perp_Liquidation_Partial_Bankruptcy(uint256) public {
        params.side = Side.BUY;
        params.amount = _hem(_randomUnique(), 10e18, 100e18);
        params.liquidationLiquidity = _hem(_randomUnique(), 1e18, params.amount);
        params.leverage = _hem(_randomUnique(), 40e18, 50e18);
        params.liqPrice = _getLiquidationPrice(ETH, params.amount, params.leverage, params.side, false);
        params.price = _hem(
            _randomUnique(),
            _getLiquidationPriceWithBadDebt(ETH, params.amount, params.leverage, params.side, 100e18),
            _getLiquidationPriceWithBadDebt(ETH, params.amount, params.leverage, params.side, 10e18)
        );

        if (params.price == 0) params.price = perpManager.getTickSize(ETH);
        else params.price -= params.price % perpManager.getTickSize(ETH);

        _liquidationHelper();
    }

    function test_Perp_Partial_OverThreshold(uint256) public {
        params.side = Side.BUY;
        params.amount = _hem(_randomUnique(), 10e18, 100e18);
        params.liquidationLiquidity = params.amount;
        params.leverage = _hem(_randomUnique(), 40e18, 50e18);
        params.liqPrice = _getLiquidationPrice(ETH, params.amount, params.leverage, params.side, false);
        params.price = _hem(
            _randomUnique(),
            _getLiquidationPriceWithBadDebt(ETH, params.amount, params.leverage, params.side, 100e18),
            _getLiquidationPriceWithBadDebt(ETH, params.amount, params.leverage, params.side, 10e18)
        );

        if (params.price == 0) params.price = perpManager.getTickSize(ETH);
        else params.price -= params.price % perpManager.getTickSize(ETH);

        vm.startPrank(admin);
        perpManager.setPartialLiquidationThreshold(
            ETH, _conformAmountToLots(params.amount).fullMulDiv(params.liqPrice, 1e18)
        );

        perpManager.setPartialLiquidationRate(ETH, _hem(_random(), 0.2 ether, 0.7 ether));
        vm.stopPrank();

        _liquidationHelper();

        uint256 liquidatedPosition =
            _conformAmountToLots(params.amount).fullMulDiv(perpManager.getPartialLiquidationRate(ETH), 1e18);
        liquidatedPosition = _conformAmountToLots(liquidatedPosition);

        assertEq(expected.positionAmount, params.amount - liquidatedPosition, "partial liquidation wrong");
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _liquidationHelper() public {
        _setupLiquidationScenario();
        _executeLiquidation();
    }

    function _setupLiquidationScenario() internal {
        params.amount = _conformAmountToLots(params.amount);
        params.liquidationLiquidity = _conformAmountToLots(params.liquidationLiquidity);

        _setLeverage();
        _executeTrade();
        _setupMakerOrder();
        _setLiquidationPrice();
    }

    function _executeTrade() internal {
        _placeTrade({
            subaccount: 1,
            asset: ETH,
            taker: rite,
            maker: jb,
            price: perpManager.getMarkPrice(ETH),
            amount: params.amount,
            side: params.side
        });
    }

    function _setLeverage() internal {
        vm.prank(jb);
        perpManager.setPositionLeverage(ETH, jb, 1, params.leverage);
        vm.prank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, params.leverage);
    }

    function _setupMakerOrder() internal {
        PlaceOrderArgs memory makerArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: params.side,
            limitPrice: params.price,
            amount: params.liquidationLiquidity,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: true
        });

        vm.prank(jb);
        state.orderId = perpManager.placeOrder(jb, makerArgs).orderId;
    }

    function _setLiquidationPrice() internal {
        vm.prank(admin);
        perpManager.mockSetMarkPrice(ETH, params.liqPrice);
    }

    function _executeLiquidation() internal {
        assertTrue(perpManager.isLiquidatable(rite, 1), "liquidatee should be liquidatable");

        _cachePreLiquidationState();
        _predictLiquidation();

        // _expectEvents();

        vm.prank(admin);
        perpManager.liquidate(ETH, rite, 1);

        _assertPostLiquidation();
    }

    function _cachePreLiquidationState() public {
        state.liquidateePosition = perpManager.getPosition(ETH, rite, 1);
        state.insuranceFundBalance = perpManager.getInsuranceFundBalance();
        state.assetBalance = usdc.balanceOf(rite);
        state.collateralBalance = perpManager.getFreeCollateralBalance(rite);
        state.marginBalance = perpManager.getMarginBalance(rite, 1);
        // jb (maker) state
        state.makerPosition = perpManager.getPosition(ETH, jb, 1);
        state.makerMarginBalance = perpManager.getMarginBalance(jb, 1);
    }

    function _predictLiquidation() public {
        _calculateFillAmounts();
        _predictLiquidateeState();
        _predictExpectedMakerState();
    }

    function _calculateFillAmounts() internal {
        if (
            state.liquidateePosition.amount.fullMulDiv(params.liqPrice, 1e18)
                >= perpManager.getPartialLiquidationThreshold(ETH)
        ) {
            // Over threshold - calculate partial liquidation amount
            expected.fillAmountRaw =
                state.liquidateePosition.amount.fullMulDiv(perpManager.getPartialLiquidationRate(ETH), 1e18);
            expected.fillAmount = _conformAmountToLots(expected.fillAmountRaw);
        } else {
            // Not over threshold - use the requested liquidation amount for actual fill
            expected.fillAmount = params.liquidationLiquidity;
            // For FillOrderSubmitted, always use the full position amount
            // (the liquidation attempts to liquidate the full position but only partial gets filled)
            expected.fillAmountRaw = state.liquidateePosition.amount;
        }
    }

    function _predictLiquidateeState() internal {
        uint256 tradedQuote = expected.fillAmount.fullMulDiv(params.price, 1e18);
        uint256 tradedOpenNotional =
            state.liquidateePosition.openNotional.fullMulDiv(expected.fillAmount, state.liquidateePosition.amount);

        expected.rpnl = _getPnl(state.liquidateePosition.isLong, tradedQuote, tradedOpenNotional);
        int256 marginDelta = -tradedOpenNotional.fullMulDiv(1e18, state.liquidateePosition.leverage).toInt256();

        expected.makerFee = tradedQuote * MAKER_BASE_FEE_RATE / 10_000_000;
        expected.liquidateeFee = tradedQuote.fullMulDiv(perpManager.getLiquidationFeeRate(ETH), 1e18);

        expected.marginBalance = state.marginBalance;

        bool fullClose = (state.liquidateePosition.amount == expected.fillAmount);

        if (fullClose) _handleFullCloseLiquidation();
        else _handlePartialCloseLiquidation(marginDelta);

        // Update position state
        expected.positionAmount = state.liquidateePosition.amount - expected.fillAmount;
        expected.positionOpenNotional = state.liquidateePosition.openNotional - tradedOpenNotional;

        if (expected.positionAmount > 0 && params.side == Side.BUY) expected.positionIsLong = true;
    }

    function _predictExpectedMakerState() internal {
        // Calculate maker's position changes
        expected.makerPositionAmount = state.makerPosition.amount - expected.fillAmount;
        uint256 makerTradedOpenNotional =
            state.makerPosition.openNotional.fullMulDiv(expected.fillAmount, state.makerPosition.amount);
        expected.makerPositionOpenNotional = state.makerPosition.openNotional - makerTradedOpenNotional;

        // Maker's position side remains the same unless fully closed
        expected.makerPositionIsLong = state.makerPosition.isLong;
        if (expected.makerPositionAmount == 0) expected.makerPositionIsLong = false; // default when no position

        // Calculate maker's PnL
        _calculateMakerPnL(makerTradedOpenNotional);

        // Calculate maker's margin balance
        _calculateMakerMarginBalance(makerTradedOpenNotional);
    }

    function _calculateMakerPnL(uint256 makerTradedOpenNotional) internal {
        bool isFullLiquidation = (state.liquidateePosition.amount == expected.fillAmount);
        if (isFullLiquidation && expected.makerPositionAmount == 0) {
            // Both parties fully close - PnLs are exact opposites
            expected.makerRpnl = -expected.rpnl;
        } else {
            // Partial liquidation or maker not fully closing - calculate independently
            uint256 makerTradedQuote = expected.fillAmount.fullMulDiv(params.price, 1e18);
            expected.makerRpnl = _getPnl(state.makerPosition.isLong, makerTradedQuote, makerTradedOpenNotional);
        }
    }

    function _calculateMakerMarginBalance(uint256 makerTradedOpenNotional) internal {
        int256 makerMarginDelta = -makerTradedOpenNotional.fullMulDiv(1e18, state.makerPosition.leverage).toInt256();

        // If maker fully closes position, margin is returned to free collateral (becomes 0)
        if (expected.makerPositionAmount == 0) {
            expected.makerMarginBalance = 0;
        } else {
            expected.makerMarginBalance =
                state.makerMarginBalance + expected.makerRpnl - expected.makerFee.toInt256() + makerMarginDelta;
        }
    }

    function _handleFullCloseLiquidation() internal {
        uint256 maintenanceMargin = perpManager.getMaintenanceMargin(ETH, state.liquidateePosition.amount);

        expected.marginBalance += expected.rpnl - expected.liquidateeFee.toInt256();

        if (expected.marginBalance < 0) {
            expected.badDebt = expected.marginBalance.abs();
            expected.marginBalance = 0;

            if (expected.liquidateeFee > expected.badDebt) {
                expected.liquidateeFee -= expected.badDebt;
                expected.badDebt = 0;
            } else {
                expected.badDebt -= expected.liquidateeFee;
                expected.liquidateeFee = 0;
            }
            expected.marginBalance = 0;
            expected.collateralReturned = 0;
        } else {
            // Margin should be returned, but check if it's below maintenance margin first
            if (expected.marginBalance < maintenanceMargin.toInt256()) {
                // Add the margin to liquidation fee instead of returning it
                expected.liquidateeFee += uint256(expected.marginBalance);
                expected.marginBalance = 0;
                expected.collateralReturned = 0;
            } else {
                // Return the excess margin
                expected.marginBalance = 0;
                expected.collateralReturned = uint256(expected.marginBalance);
            }
            expected.badDebt = 0;
        }
    }

    function _handlePartialCloseLiquidation(int256 marginDelta) internal {
        (uint256 intendedMarginAfter, int256 upnlAfter) = _getIntendedMarginAndUpnlAfter();

        // Add net rpnl (after fees) to margin
        expected.marginBalance += expected.rpnl - expected.liquidateeFee.toInt256();

        int256 equity = expected.marginBalance + upnlAfter + marginDelta;
        int256 overCollateralization = equity - intendedMarginAfter.toInt256();

        if (overCollateralization < 0) {
            overCollateralization -= marginDelta;
            if (overCollateralization > 0) marginDelta = -overCollateralization;
            else marginDelta = 0;
        }

        expected.marginBalance += marginDelta;
        expected.collateralReturned = 0;
        expected.badDebt = 0;
    }

    function _getIntendedMarginAndUpnlAfter() internal view returns (uint256 intendedMargin, int256 upnl) {
        // Calculate what the position will look like after the trade
        uint256 remainingAmount = state.liquidateePosition.amount - expected.fillAmount;
        if (remainingAmount == 0) return (0, 0);

        uint256 remainingOpenNotional = state.liquidateePosition.openNotional
            - state.liquidateePosition.openNotional.fullMulDiv(expected.fillAmount, state.liquidateePosition.amount);

        // Create a temporary position to calculate intended margin and upnl
        Position memory afterPosition = Position({
            amount: remainingAmount,
            openNotional: remainingOpenNotional,
            isLong: state.liquidateePosition.isLong,
            leverage: state.liquidateePosition.leverage,
            lastCumulativeFunding: state.liquidateePosition.lastCumulativeFunding
        });

        return perpManager.getIntendedMarginAndUpnl(ETH, afterPosition);
    }

    function _assertPostLiquidation() internal view {
        _assertLiquidateeState();
        _assertMakerState();
        _assertProtocolState();
    }

    function _assertLiquidateeState() internal view {
        Position memory liquidateePosition = perpManager.getPosition(ETH, rite, 1);

        // liquidatee position
        assertEq(liquidateePosition.amount, expected.positionAmount, "liquidatee position amount mismatch");
        assertEq(
            liquidateePosition.openNotional, expected.positionOpenNotional, "liquidatee position open notional mismatch"
        );
        assertEq(liquidateePosition.isLong, expected.positionIsLong, "liquidatee position side mismatch");

        // liquidatee margin
        assertEq(perpManager.getMarginBalance(rite, 1), expected.marginBalance, "liquidatee margin balance mismatch");
    }

    function _assertMakerState() internal view {
        Position memory makerPosition = perpManager.getPosition(ETH, jb, 1);
        assertEq(makerPosition.amount, expected.makerPositionAmount, "maker position amount mismatch");
        assertEq(
            makerPosition.openNotional, expected.makerPositionOpenNotional, "maker position open notional mismatch"
        );
        assertEq(makerPosition.isLong, expected.makerPositionIsLong, "maker position side mismatch");
        assertEq(perpManager.getMarginBalance(jb, 1), expected.makerMarginBalance, "maker margin balance mismatch");
    }

    function _assertProtocolState() internal view {
        // protocol balances
        assertEq(
            perpManager.getInsuranceFundBalance(),
            state.insuranceFundBalance + expected.liquidateeFee + expected.makerFee - expected.badDebt,
            "insurance fund balance mismatch"
        );
        assertEq(
            usdc.balanceOf(address(perpManager)),
            uint256(
                perpManager.getMarginBalance(rite, 1) + perpManager.getFreeCollateralBalance(rite).toInt256()
                    + perpManager.getMarginBalance(jb, 1) + perpManager.getFreeCollateralBalance(jb).toInt256()
                    + perpManager.getInsuranceFundBalance().toInt256()
            ),
            "perpManager USDC balance mismatch"
        );
    }

    function _getLiquidationPrice(bytes32 asset, uint256 amount, uint256 leverage, Side liquidateeSide, bool includeFee)
        internal
        view
        returns (uint256 liquidationPrice)
    {
        uint256 currentPrice = perpManager.getMarkPrice(asset);

        uint256 notional = currentPrice.fullMulDiv(amount, 1e18);

        uint256 margin = amount.fullMulDiv(perpManager.getMarkPrice(asset), leverage);

        if (includeFee) margin -= notional.fullMulDiv(perpManager.getLiquidationFeeRate(asset), 1e18);

        uint256 minMarginRatio = perpManager.getMinMarginRatio(asset);

        int256 side = liquidateeSide == Side.BUY ? int256(-1) : int256(1);

        uint256 numerator = (currentPrice.toInt256() + (margin.fullMulDiv(1e18, amount).toInt256() * side)).abs();
        uint256 denominator = (1e18 + minMarginRatio.toInt256() * side).abs();

        liquidationPrice = ((numerator).fullMulDiv(1e18, denominator).toInt256() + (side * 5)).abs();
    }

    function _getBankruptcyPrice(bytes32 asset, uint256 amount, uint256 leverage, Side liquidateeSide, bool includeFee)
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

        if (!includeFee) return bankruptcyPrice;

        uint256 notional = bankruptcyPrice.fullMulDiv(amount, 1e18);
        uint256 fee = notional.fullMulDiv(perpManager.getLiquidationFeeRate(asset), 1e18);

        if (liquidateeSide == Side.BUY) bankruptcyPrice += fee.fullMulDiv(1e18, amount);
        else bankruptcyPrice -= fee.fullMulDiv(1e18, amount);
    }

    function _getLiquidationPriceWithBadDebt(
        bytes32 asset,
        uint256 amount,
        uint256 leverage,
        Side liquidateeSide,
        uint256 badDebt
    ) internal view returns (uint256) {
        uint256 currentPrice = perpManager.getMarkPrice(asset);

        uint256 openNotional = amount.fullMulDiv(currentPrice, 1e18);
        uint256 margin = openNotional.fullMulDiv(1e18, leverage);

        int256 side = liquidateeSide == Side.BUY ? int256(-1) : int256(1);

        uint256 numerator = (openNotional.toInt256() + (margin.toInt256() + int256(badDebt) * side)).abs();

        if (liquidateeSide == Side.BUY) {
            uint256 loss = (margin + badDebt);
            if (loss > openNotional) return 0;
            numerator = openNotional - loss;
        } else {
            numerator = openNotional + (margin + badDebt);
        }

        return numerator.fullMulDiv(1e18, amount);
    }

    function _getPnl(bool isLong, uint256 currentNotional, uint256 openNotional) internal pure returns (int256) {
        if (isLong) return int256(currentNotional) - int256(openNotional);
        else return int256(openNotional) - int256(currentNotional);
    }

    function _conformAmountToLots(uint256 amount) internal view returns (uint256) {
        uint256 lotSize = perpManager.getLotSize(ETH);
        return amount / lotSize * lotSize;
    }
}
