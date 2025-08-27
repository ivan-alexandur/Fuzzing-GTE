// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "../PerpManagerTestBase.sol";

contract PerpBackstopLiquidation_Test is PerpManagerTestBase {
    using FixedPointMathLib for *;
    using SafeCastLib for uint256;

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                SETUP
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    struct LiquidationParams {
        Side side;
        uint256 amount;
        uint256 leverage;
        uint256 price;
        uint256 maker1Amount;
        uint256 maker2Amount;
        uint256 maker3Amount;
    }

    struct State {
        Position liquidateePosition;
        uint256 insuranceFundBalance;
        uint256 takerFreeCollateral;
        int256 takerMargin;
        uint256 maker1FreeCollateral;
        uint256 maker2FreeCollateral;
        uint256 maker3FreeCollateral;
    }

    struct ExpectedResult {
        int256 takerMargin;
        uint256 maker1Margin;
        uint256 maker2Margin;
        uint256 maker3Margin;
        int256 proratedMargin;
        int256 rpnl;
        uint256 maker1Reward;
        uint256 maker2Reward;
        uint256 maker3Reward;
        uint256 liquidationFee;
        uint256 badDebt;
        uint256 dust;
    }

    LiquidationParams params;
    State state;
    ExpectedResult expected;

    address maker1 = julien;
    address maker2 = nate;
    address maker3 = moses;

    function setUp() public override {
        super.setUp();

        vm.prank(maker1);
        perpManager.deposit(maker1, 100_000_000e18);
        vm.prank(maker2);
        perpManager.deposit(maker2, 100_000_000e18);
        vm.prank(maker3);
        perpManager.deposit(maker3, 100_000_000e18);

        vm.startPrank(admin);
        perpManager.insuranceFundDeposit(5_000_000e18);
        perpManager.setLiquidatorPoints(maker1, 1);
        perpManager.setLiquidatorPoints(maker2, 1);
        perpManager.setLiquidatorPoints(maker3, 1);
        perpManager.enableCrossMargin(GTE);
        vm.stopPrank();
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            ISOLATED MARGIN
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_Perp_BackstopLiquidation_Isolated_NoBadDebt(uint256) public {
        params.side = _randomChance(2) ? Side.BUY : Side.SELL;

        _backstopLiquidationHelper_Isolated(false);

        assertEq(expected.badDebt, 0, "bad debt should not be realized");
        assertGt(expected.maker1Reward, 0, "maker reward should be > 0");
        assertGt(expected.liquidationFee, 0, "liquidation fee should be > 0");
    }

    function test_Perp_BackstopLiquidation_Isolated_BadDebt(uint256) public {
        params.side = _randomChance(2) ? Side.BUY : Side.SELL;

        _backstopLiquidationHelper_Isolated(true);

        assertGt(expected.badDebt, 0, "bad debt should be realized");
        assertEq(expected.maker1Reward, 0, "maker reward should be 0");
        assertEq(expected.liquidationFee, 0, "liquidation fee should be 0 if no reward");
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            CROSS MARGIN
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_Perp_BackstopLiquidation_Cross(uint256) public {
        params.side = _randomChance(2) ? Side.BUY : Side.SELL;

        _backstopLiquidationHelper_Cross(_randomChance(2));

        assertEq(expected.badDebt, 0, "bad debt should not be realized in cross margin account");

        // prorated margin + rpnl = reward pool
        if (expected.proratedMargin + expected.rpnl <= 0) {
            assertEq(expected.maker1Reward, 0, "maker reward should be 0 if no reward");
            assertEq(expected.liquidationFee, 0, "liquidation fee should be 0 if no reward");
        } else {
            assertGt(expected.maker1Reward, 0, "maker reward should be > 0");
            assertGt(expected.liquidationFee, 0, "liquidation fee should be > 0");
        }
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                        LIQUIDATION ORCHESTRATION
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _backstopLiquidationHelper_Isolated(bool badDebt) public {
        params.amount = _conformAmountToLots(_hem(_randomUnique(), 10e18, 100e18));
        params.leverage = _hem(_randomUnique(), 10e18, 50e18);

        uint256 initialPrice = _conformTick(ETH, _hem(_random(), 10e18, 10_000e18));

        vm.prank(admin);
        perpManager.mockSetMarkPrice(ETH, initialPrice);

        vm.prank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, params.leverage);

        _placeTrade({
            asset: ETH,
            taker: rite,
            subaccount: 1,
            maker: jb,
            price: initialPrice,
            amount: params.amount,
            side: params.side
        });

        _setupLiquidationPrice(badDebt);

        vm.prank(admin);
        perpManager.mockSetMarkPrice(ETH, params.price);

        assertTrue(perpManager.isLiquidatableBackstop(rite, 1), "liquidatee should be backstop liquidatable");

        _setupMakerOrders();
        _cachePreLiquidationState();
        _predictLiquidationFill();
        _predictLiquidationSettle();

        vm.prank(admin);
        perpManager.backstopLiquidate(ETH, rite, 1);

        _assertPostLiquidationState();
    }

    function _backstopLiquidationHelper_Cross(bool badDebt) public {
        params.amount = _conformAmountToLots(_hem(_randomUnique(), 50e18, 100e18));
        params.leverage = _hem(_randomUnique(), 10e18, 50e18);

        uint256 initialPrice = _conformTick(ETH, _hem(_random(), 40e18, 10_000e18));

        vm.prank(admin);
        perpManager.mockSetMarkPrice(ETH, initialPrice);

        vm.startPrank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, params.leverage);
        perpManager.setPositionLeverage(GTE, rite, 1, 5e18);
        vm.stopPrank();

        // small position in another asset to create cross margin
        _placeTrade({asset: GTE, taker: rite, subaccount: 1, maker: jb, price: 5e18, amount: 0.5e18, side: params.side});

        _placeTrade({
            asset: ETH,
            taker: rite,
            subaccount: 1,
            maker: jb,
            price: initialPrice,
            amount: params.amount,
            side: params.side
        });

        _setupLiquidationPrice(badDebt);

        vm.startPrank(admin);
        perpManager.mockSetMarkPrice(ETH, params.price);

        // heavy upnl loss for other position
        if (params.side == Side.BUY) perpManager.mockSetMarkPrice(GTE, 1e18);
        else perpManager.mockSetMarkPrice(GTE, 10e18);

        vm.stopPrank();

        assertTrue(perpManager.isLiquidatableBackstop(rite, 1), "liquidatee should be backstop liquidatable");

        _setupMakerOrders();
        _cachePreLiquidationState();
        _predictLiquidationFill();
        _predictLiquidationSettle();

        vm.prank(admin);
        perpManager.backstopLiquidate(ETH, rite, 1);

        _assertPostLiquidationState();
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            SETUP HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _setupLiquidationPrice(bool badDebt) internal {
        uint256 price1;
        uint256 price2;
        if (badDebt) {
            price1 = _getBadDebtPrice(ETH, rite, 1, 500e18);
            price2 = _getBankruptcyPrice(ETH, rite, 1);

            if (params.side == Side.BUY) price2 -= perpManager.getTickSize(ETH);
            else price2 += perpManager.getTickSize(ETH);
        } else {
            price1 = _getLiquidationPrice(ETH, rite, 1);
            price2 = _getBankruptcyPrice(ETH, rite, 1);

            if (params.side == Side.BUY) price2 += perpManager.getTickSize(ETH);
            else price2 -= perpManager.getTickSize(ETH);
        }

        (price1, price2) = price1 < price2 ? (price1, price2) : (price2, price1);

        if(price1 == 0) params.price = perpManager.getTickSize(ETH); 

        params.price = _conformTick(ETH, _hem(_randomUnique(), price1, price2));

        if (params.side == Side.SELL) params.price += perpManager.getTickSize(ETH);
    }

    function _setupMakerOrders() internal {
        _generateMakerLiquidityAmounts();

        PlaceOrderArgs memory makerArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: params.side,
            limitPrice: params.price,
            amount: params.maker1Amount,
            baseDenominated: true,
            tif: TiF.MOC, // backstop limit orders must be MOC
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        vm.prank(maker1);
        perpManager.postLimitOrderBackstop(maker1, makerArgs);

        makerArgs.amount = params.maker2Amount;

        vm.prank(maker2);
        perpManager.postLimitOrderBackstop(maker2, makerArgs);

        makerArgs.amount = params.maker3Amount;

        vm.prank(maker3);
        perpManager.postLimitOrderBackstop(maker3, makerArgs);
    }

    function _generateMakerLiquidityAmounts() internal {
        uint256 ratio1 = _hem(_randomUnique(), 1e18, 33e18);
        uint256 ratio2 = _hem(_randomUnique(), 1e18, 66e18 - ratio1);
        uint256 ratio3 = 100e18 - ratio1 - ratio2;

        params.maker1Amount = _conformAmountToLots(params.amount.fullMulDiv(ratio1, 100e18));
        params.maker2Amount = _conformAmountToLots(params.amount.fullMulDiv(ratio2, 100e18));
        params.maker3Amount = _conformAmountToLots(params.amount.fullMulDiv(ratio3, 100e18));

        // Add any remainder due to lot size rounding to the last maker to ensure exact coverage
        uint256 totalAssigned = params.maker1Amount + params.maker2Amount + params.maker3Amount;
        if (totalAssigned < params.amount) params.maker3Amount += params.amount - totalAssigned;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                        STATE CACHING & PREDICTION
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _cachePreLiquidationState() internal {
        state.liquidateePosition = perpManager.getPosition(ETH, rite, 1);
        state.insuranceFundBalance = perpManager.getInsuranceFundBalance();
        state.takerFreeCollateral = perpManager.getFreeCollateralBalance(rite);
        state.takerMargin = perpManager.getMarginBalance(rite, 1);
        state.maker1FreeCollateral = perpManager.getFreeCollateralBalance(maker1);
        state.maker2FreeCollateral = perpManager.getFreeCollateralBalance(maker2);
        state.maker3FreeCollateral = perpManager.getFreeCollateralBalance(maker3);
    }

    function _predictLiquidationFill() internal {
        uint256 tradedQuote = params.amount.fullMulDiv(params.price, 1e18);

        expected.rpnl = _getPnl({
            isLong: state.liquidateePosition.isLong,
            currentNotional: tradedQuote,
            openNotional: state.liquidateePosition.openNotional
        });

        expected.maker1Margin = params.maker1Amount.fullMulDiv(params.price, 1e18);
        expected.maker2Margin = params.maker2Amount.fullMulDiv(params.price, 1e18);
        expected.maker3Margin = params.maker3Amount.fullMulDiv(params.price, 1e18);
    }

    function _predictLiquidationSettle() internal {
        bool isolated = perpManager.getAssets(rite, 1).length == 1;

        uint256 reward;
        if (!isolated) {
            expected.proratedMargin = _prorateMargin(state.takerMargin, rite, 1);

            expected.takerMargin = state.takerMargin - expected.proratedMargin;

            if (expected.proratedMargin + expected.rpnl < 0) {
                expected.takerMargin += expected.proratedMargin + expected.rpnl;
                return;
            }

            reward = uint256(expected.proratedMargin + expected.rpnl);
        } else if (isolated && state.takerMargin + expected.rpnl < 0) {
            expected.badDebt = uint256(-(state.takerMargin + expected.rpnl));
            return;
        } else {
            reward = uint256((state.takerMargin + expected.rpnl));
        }

        expected.liquidationFee = reward.fullMulDiv(perpManager.getLiquidationFeeRate(ETH), 1e18);

        reward -= expected.liquidationFee;

        // reward split
        // note: using static points because there is already a detailed unit test
        uint256 staticPointShare = 1.fullMulDiv(1e18, 3);

        uint256 volume1 = params.maker1Amount.fullMulDiv(params.price, 1e18);
        uint256 volume2 = params.maker2Amount.fullMulDiv(params.price, 1e18);
        uint256 volume3 = params.maker3Amount.fullMulDiv(params.price, 1e18);

        uint256 totalVolume = volume1 + volume2 + volume3;

        uint256 rate = (volume1.fullMulDiv(1e18, totalVolume) + staticPointShare) / 2;
        expected.maker1Reward = reward.fullMulDiv(rate, 1e18);

        rate = (volume2.fullMulDiv(1e18, totalVolume) + staticPointShare) / 2;
        expected.maker2Reward = reward.fullMulDiv(rate, 1e18);

        rate = (volume3.fullMulDiv(1e18, totalVolume) + staticPointShare) / 2;
        expected.maker3Reward = reward.fullMulDiv(rate, 1e18);

        expected.dust = reward - (expected.maker1Reward + expected.maker2Reward + expected.maker3Reward);
    }

    function _prorateMargin(int256 margin, address account, uint256 subaccount) internal view returns (int256) {
        if (margin < 0) return 0;

        uint256 ethValue =
            perpManager.getPosition(ETH, account, subaccount).amount.fullMulDiv(perpManager.getMarkPrice(ETH), 1e18);
        uint256 gteValue =
            perpManager.getPosition(GTE, account, subaccount).amount.fullMulDiv(perpManager.getMarkPrice(GTE), 1e18);

        uint256 totalValue = ethValue + gteValue;

        return uint256(margin).fullMulDiv(ethValue, totalValue).toInt256();
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                             ASSERTIONS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _assertPostLiquidationState() internal {
        // taker
        _assertFullyLiquidatedPosition(perpManager.getPosition(ETH, rite, 1));
        assertEq(perpManager.getMarginBalance(rite, 1), expected.takerMargin, "taker margin wrong");

        // maker 1
        assertEq(perpManager.getMarginBalance(maker1, 1), int256(expected.maker1Margin), "maker1 margin wrong");
        assertEq(
            perpManager.getFreeCollateralBalance(maker1),
            state.maker1FreeCollateral + expected.maker1Reward,
            "maker1 free collateral wrong"
        );

        // maker 2
        assertEq(perpManager.getMarginBalance(maker2, 1), int256(expected.maker2Margin), "maker2 margin wrong");
        assertEq(
            perpManager.getFreeCollateralBalance(maker2),
            state.maker2FreeCollateral + expected.maker2Reward,
            "maker2 free collateral wrong"
        );

        // maker 3
        assertEq(perpManager.getMarginBalance(maker3, 1), int256(expected.maker3Margin), "maker3 margin wrong");
        assertEq(
            perpManager.getFreeCollateralBalance(maker3),
            state.maker3FreeCollateral + expected.maker3Reward,
            "maker3 free collateral wrong"
        );

        // protocol
        assertEq(
            perpManager.getInsuranceFundBalance(),
            state.insuranceFundBalance + expected.liquidationFee - expected.badDebt,
            "insurance fund balance wrong"
        );

        _assertProtocolSolvency();
    }

    function _assertProtocolSolvency() internal {
        // close original counterparty to realize upnl
        _placeTrade({
            asset: ETH,
            taker: maker1,
            subaccount: 1,
            maker: jb,
            price: params.price,
            amount: params.maker1Amount,
            side: params.side == Side.BUY ? Side.SELL : Side.BUY
        });
        _placeTrade({
            asset: ETH,
            taker: maker2,
            subaccount: 1,
            maker: jb,
            price: params.price,
            amount: params.maker2Amount,
            side: params.side == Side.BUY ? Side.SELL : Side.BUY
        });
        _placeTrade({
            asset: ETH,
            taker: maker3,
            subaccount: 1,
            maker: jb,
            price: params.price,
            amount: params.maker3Amount,
            side: params.side == Side.BUY ? Side.SELL : Side.BUY
        });

        uint256 totalFreeCollateral = perpManager.getFreeCollateralBalance(maker1)
            + perpManager.getFreeCollateralBalance(maker2) + perpManager.getFreeCollateralBalance(maker3)
            + perpManager.getFreeCollateralBalance(rite) + perpManager.getFreeCollateralBalance(jb);

        int256 totalMargin = perpManager.getMarginBalance(maker1, 1) + perpManager.getMarginBalance(maker2, 1)
            + perpManager.getMarginBalance(maker3, 1) + perpManager.getMarginBalance(rite, 1)
            + perpManager.getMarginBalance(jb, 1);

        assertEq(
            int256(usdc.balanceOf(address(perpManager))),
            int256(perpManager.getInsuranceFundBalance()) + int256(totalFreeCollateral) + totalMargin
                + int256(expected.dust),
            "protocol accounting wrong"
        );
    }

    function _assertFullyLiquidatedPosition(Position memory position) internal view {
        assertEq(position.amount, 0, "position: amount not zero");
        assertEq(position.openNotional, 0, "position: openNotional not zero");
        assertEq(position.lastCumulativeFunding, 0, "position: lastCumulativeFunding not zero");
        assertEq(position.isLong, false, "position: isLong not false");

        assertEq(position.leverage, params.leverage, "position: leverage changed");
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            UTILITY FUNCTIONS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _getLiquidationPrice(bytes32 asset, address account, uint256 subaccount)
        internal
        view
        returns (uint256 liquidationPrice)
    {
        uint256 currentPrice = perpManager.getMarkPrice(asset);
        Position memory position = perpManager.getPosition(asset, account, subaccount);

        uint256 margin = uint256(perpManager.getMarginBalance(account, subaccount));

        // if cross margin account, prorate margin
        if (perpManager.getAssets(account, subaccount).length > 1) {
            margin = uint256(_prorateMargin(int256(margin), account, subaccount));
        }

        uint256 minMarginRatio = perpManager.getMinMarginRatioBackstop(asset);

        int256 side = position.isLong ? int256(-1) : int256(1);

        uint256 numerator =
            (currentPrice.toInt256() + (margin.fullMulDiv(1e18, position.amount).toInt256() * side)).abs();
        uint256 denominator = (1e18 + minMarginRatio.toInt256() * side).abs();

        liquidationPrice = ((numerator).fullMulDiv(1e18, denominator).toInt256() + side).abs();
    }

    function _getBankruptcyPrice(bytes32 asset, address account, uint256 subaccount)
        internal
        view
        returns (uint256 bankruptcyPrice)
    {
        Position memory position = perpManager.getPosition(asset, account, subaccount);

        uint256 openNotional = position.openNotional;
        int256 margin = perpManager.getMarginBalance(account, subaccount);

        // if cross margin account, prorate margin
        if (perpManager.getAssets(account, subaccount).length > 1) margin = _prorateMargin(margin, account, subaccount);

        int256 side = position.isLong ? int256(-1) : int256(1);
        uint256 numerator = (openNotional.toInt256() + (margin * side)).abs();

        bankruptcyPrice = numerator.fullMulDiv(1e18, position.amount);
    }

    function _getBadDebtPrice(bytes32 asset, address account, uint256 subaccount, uint256 badDebt)
        internal
        view
        returns (uint256)
    {
        // note: for cross margin test will have to prorate margin here
        Position memory position = perpManager.getPosition(asset, account, subaccount);

        int256 margin = perpManager.getMarginBalance(account, subaccount);

        // if cross margin account, prorate margin
        if (perpManager.getAssets(account, subaccount).length > 1) margin = _prorateMargin(margin, account, subaccount);

        int256 side = position.isLong ? int256(-1) : int256(1);

        uint256 numerator = (position.openNotional.toInt256() + ((margin) + int256(badDebt) * side)).abs();

        if (position.isLong) {
            uint256 loss = uint256(margin + int256(badDebt));
            if (loss > position.openNotional) return 0;
            numerator = position.openNotional - loss;
        } else {
            numerator = position.openNotional + uint256(margin + int256(badDebt));
        }

        return numerator.fullMulDiv(1e18, position.amount);
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
