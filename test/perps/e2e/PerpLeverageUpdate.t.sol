// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {MarketLib} from "contracts/perps/types/Market.sol";

import "../PerpManagerTestBase.sol";

contract Perp_LeverageUpdate_Test is PerpManagerTestBase {
    using FixedPointMathLib for *;
    using SafeCastLib for *;

    // create control position & orderbook notional in BTC
    function setUp() public override {
        super.setUp();

        vm.prank(rite);
        perpManager.setPositionLeverage({
            asset: BTC,
            account: rite,
            subaccount: 1,
            newLeverage: _hem(_random(), 5e18, 10e18)
        });

        _placeTrade({
            asset: BTC,
            taker: rite,
            maker: jb,
            subaccount: 1,
            price: 100_000e18,
            amount: 1e18,
            side: _randomChance(2) ? Side.BUY : Side.SELL
        });

        _createLimitOrder({subaccount: 1, asset: BTC, price: 100_000e18, amount: 1e18, side: Side.BUY, maker: rite});
    }

    int256 cumulativeFunding;
    uint256 initialLeverage;
    uint256 newLeverage;
    uint256 markPrice;

    int256 marginBefore;
    uint256 freeCollateralBefore;

    int256 expectedMargin;
    uint256 expectedCollateral;

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                SUCCESS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_PerpLeverageUpdate_ExistingPosition(uint256) public {
        initialLeverage = _hem(_random(), 5e18, 10e18);
        newLeverage = _hem(_random(), 1e18, 50e18);
        markPrice = _hem(_random(), 1e18, 200_000e18);

        // random mark
        perpManager.mockSetMarkPrice({asset: ETH, markPrice: markPrice});

        vm.prank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, initialLeverage);

        _placeTrade({
            subaccount: 1,
            asset: ETH,
            taker: rite,
            maker: jb,
            price: _conformTick(ETH, markPrice),
            amount: _conformLots(ETH, _hem(_random(), 1e18, 10e18)),
            side: _randomChance(2) ? Side.BUY : Side.SELL
        });

        _placeRandomOrder();
        _updateFundingForBTC();

        marginBefore = perpManager.getMarginBalance(rite, 1);
        freeCollateralBefore = perpManager.getFreeCollateralBalance(rite);

        expectedMargin = int256(_getNewMargin());
        expectedCollateral = (
            int256(freeCollateralBefore) + (marginBefore - expectedMargin - _getOrderbookCollateralDelta())
                - perpManager.getPendingFundingPayment(rite, 1)
        ).toUint256();

        vm.prank(rite);
        perpManager.setPositionLeverage({asset: ETH, account: rite, subaccount: 1, newLeverage: newLeverage});

        assertEq(perpManager.getMarginBalance(rite, 1), expectedMargin, "margin balance wrong");
        assertEq(perpManager.getFreeCollateralBalance(rite), expectedCollateral, "free collateral balance wrong");
        assertEq(perpManager.getPosition(ETH, rite, 1).leverage, newLeverage, "leverage not updated");
        assertEq(
            perpManager.getPosition(BTC, rite, 1).lastCumulativeFunding, cumulativeFunding, "last funding not updated"
        );
    }

    function test_PerpLeverageUpdate_NoExistingPosition(uint256) public {
        initialLeverage = _hem(_random(), 5e18, 10e18);
        newLeverage = _hem(_random(), 1e18, 50e18);

        marginBefore = perpManager.getMarginBalance(rite, 1);
        freeCollateralBefore = perpManager.getFreeCollateralBalance(rite);

        vm.prank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, initialLeverage);

        assertEq(perpManager.getMarginBalance(rite, 1), marginBefore, "margin balance should not change");
        assertEq(
            perpManager.getFreeCollateralBalance(rite),
            freeCollateralBefore,
            "free collateral balance should not change"
        );
        assertEq(perpManager.getPosition(ETH, rite, 1).leverage, initialLeverage, "leverage should change");

        _placeRandomOrder();
        _updateFundingForBTC();

        marginBefore = perpManager.getMarginBalance(rite, 1);
        freeCollateralBefore = perpManager.getFreeCollateralBalance(rite);

        expectedCollateral = (int256(freeCollateralBefore) - _getOrderbookCollateralDelta()).toUint256();

        vm.prank(rite);
        perpManager.setPositionLeverage({asset: ETH, account: rite, subaccount: 1, newLeverage: newLeverage});

        assertEq(perpManager.getMarginBalance(rite, 1), marginBefore, "margin balance changed");
        assertEq(perpManager.getFreeCollateralBalance(rite), expectedCollateral, "free collateral balance wrong");
        assertEq(perpManager.getPosition(ETH, rite, 1).leverage, newLeverage, "leverage not updated");
        assertEq(perpManager.getPosition(BTC, rite, 1).lastCumulativeFunding, 0, "funding realized");
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                 FAIL
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_PerpLeverageUpdate_Fail_LeverageTooHigh(uint256) public {
        uint256 maxLeverage = _hem(_random(), 2e18, 100e18);

        vm.prank(admin);
        perpManager.setMaxLeverage(ETH, maxLeverage);

        vm.prank(rite);
        vm.expectRevert(MarketLib.MaxLeverageExceeded.selector);
        perpManager.setPositionLeverage({asset: ETH, account: rite, subaccount: 1, newLeverage: maxLeverage + 1});
    }

    function test_PerpLeverageUpdate_Fail_LeverageInvalid(uint256) public {
        vm.prank(rite);
        vm.expectRevert(MarketLib.LeverageInvalid.selector);
        perpManager.setPositionLeverage({
            asset: ETH,
            account: rite,
            subaccount: 1,
            newLeverage: _hem(_random(), 0, 1e18 - 1) // invalid leverage
        });
    }

    function test_PerpLeverageUpdate_Fail_MarketInactiveOrInvalid(uint256) public {
        vm.prank(admin);
        perpManager.deactivateMarket(ETH);

        vm.startPrank(rite);

        vm.expectRevert(MarketLib.MarketInactive.selector);
        perpManager.setPositionLeverage({asset: ETH, account: rite, subaccount: 1, newLeverage: 1e18});

        vm.expectRevert(MarketLib.MarketInactive.selector);
        perpManager.setPositionLeverage({asset: _getRandomAsset(), account: rite, subaccount: 1, newLeverage: 1e18});
    }

    function test_PerpLeverageUpdate_Fail_OpenRequirementUnmet() public {
        vm.prank(rite);
        perpManager.setPositionLeverage({asset: ETH, account: rite, subaccount: 1, newLeverage: 45e18});

        _placeTrade({subaccount: 1, asset: ETH, taker: rite, maker: jb, price: 4000e18, amount: 1e18, side: Side.SELL});

        perpManager.mockSetMarkPrice({asset: ETH, markPrice: 8000e18});

        if (perpManager.getPosition(BTC, rite, 1).isLong) perpManager.mockSetMarkPrice({asset: BTC, markPrice: 1e18});
        else perpManager.mockSetMarkPrice({asset: BTC, markPrice: 200_000e18});

        vm.prank(rite);
        vm.expectRevert(ClearingHouseLib.MarginRequirementUnmet.selector);
        perpManager.setPositionLeverage({asset: ETH, account: rite, subaccount: 1, newLeverage: 50e18});
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _placeRandomOrder() internal {
        _createLimitOrder({
            subaccount: 1,
            asset: ETH,
            price: _conformTick(ETH, _hem(_random(), 1e18, 200_000e18)),
            amount: 1e18,
            side: Side.BUY,
            maker: rite
        });
    }

    function _updateFundingForBTC() internal {
        cumulativeFunding = int256(_hem(_random(), 1e18, 1000e18));

        // 1 quote funding payment owed to trader
        perpManager.mockSetCumulativeFunding(BTC, cumulativeFunding);
    }

    // note: orderbook collateral for BTC should be static since leverage is only changing for ETH
    function _getOrderbookCollateralDelta() internal view returns (int256) {
        uint256 orderbookNotional = perpManager.getOrderbookNotional({asset: ETH, account: rite, subaccount: 1});

        return int256(orderbookNotional.fullMulDiv(1e18, newLeverage))
            - int256(orderbookNotional.fullMulDiv(1e18, initialLeverage));
    }

    function _getNewMargin() internal view returns (uint256) {
        Position memory position = perpManager.getPosition({asset: BTC, account: rite, subaccount: 1});

        uint256 btcIntendedMargin =
            position.amount.fullMulDiv(perpManager.getMarkPrice(BTC), 1e18).fullMulDiv(1e18, position.leverage);

        position = perpManager.getPosition({asset: ETH, account: rite, subaccount: 1});

        uint256 ethIntendedMargin =
            position.amount.fullMulDiv(perpManager.getMarkPrice(ETH), 1e18).fullMulDiv(1e18, newLeverage);

        return ethIntendedMargin + btcIntendedMargin;
    }

    function _getRandomAsset() internal returns (bytes32 asset) {
        asset = bytes32(_random());

        if (asset == ETH || asset == BTC || asset == GTE) return _getRandomAsset();
    }
}
