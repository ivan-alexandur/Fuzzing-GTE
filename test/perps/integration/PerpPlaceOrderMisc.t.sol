// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "../PerpManagerTestBase.sol";

/// @dev test FOK passes with lot dust
/// @dev test MOC passes with lot dust
/// @dev test GTC order that fills on book before posting
/// @dev @todo test maker order.head, order.tail on post | do this for 20 orders on 5 random prices, with 1 random side

contract Perp_PlaceOrder_Misc_Test is PerpManagerTestBase {
    using FixedPointMathLib for *;

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                              LOT ROUNDING
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_Perp_PlaceOrder_Misc_FOK_LotRounding_BaseDenominated(uint256) public {
        Side side = _randomChance(2) ? Side.BUY : Side.SELL;
        uint256 amount = _conformLots(ETH, _hem(_random(), 1e18, 1000e18));
        uint256 lotSize = perpManager.getLotSize(ETH);

        _createLimitOrder({
            asset: ETH,
            maker: jb,
            subaccount: 1,
            price: 4000e18,
            amount: amount,
            side: side == Side.BUY ? Side.SELL : Side.BUY
        });

        PlaceOrderArgs memory fillArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: side,
            limitPrice: 0,
            amount: amount + _hem(_random(), 1, lotSize - 1), // doesn't conform to lot size
            baseDenominated: true,
            tif: TiF.FOK,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        vm.prank(rite);
        PlaceOrderResult memory result = perpManager.placeOrder(rite, fillArgs);

        assertEq(result.baseTraded, amount, "base traded wrong");
    }

    function test_Perp_PlaceOrder_Misc_FOK_LotRounding_QuoteDenominated(uint256) public {
        Side side = _randomChance(2) ? Side.BUY : Side.SELL;
        uint256 quoteAmount = _hem(_random(), 10e18, 40_000_000e18);
        uint256 baseAmount = quoteAmount.fullMulDiv(1e18, 4000e18);
        uint256 lotSize = perpManager.getLotSize(ETH);

        vm.assume(baseAmount % lotSize != 0); // ensure conversion does not conform to lot size

        baseAmount = _conformLots(ETH, baseAmount);

        _createLimitOrder({
            asset: ETH,
            maker: jb,
            subaccount: 1,
            price: 4000e18,
            amount: baseAmount,
            side: side == Side.BUY ? Side.SELL : Side.BUY
        });

        PlaceOrderArgs memory fillArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: side,
            limitPrice: 0,
            amount: quoteAmount,
            baseDenominated: false, // quote denominated
            tif: TiF.FOK,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        vm.prank(rite);
        PlaceOrderResult memory result = perpManager.placeOrder(rite, fillArgs);

        assertEq(result.baseTraded, baseAmount, "base traded wrong");
    }

    function test_Perp_PlaceOrder_Misc_MOC_LotRounding_BaseDenominated(uint256) public {
        Side side = _randomChance(2) ? Side.BUY : Side.SELL;
        uint256 amount = _conformLots(ETH, _hem(_random(), 1e18, 1000e18));
        uint256 lotSize = perpManager.getLotSize(ETH);

        PlaceOrderArgs memory makerArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: side,
            limitPrice: 4000e18,
            amount: amount + _hem(_random(), 1, lotSize - 1), // doesn't conform to lot size
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        vm.prank(rite);
        PlaceOrderResult memory result = perpManager.placeOrder(rite, makerArgs);

        assertEq(result.basePosted, amount, "base posted wrong");
    }

    function test_Perp_PlaceOrder_Misc_MOC_LotRounding_QuoteDenominated(uint256) public {
        Side side = _randomChance(2) ? Side.BUY : Side.SELL;
        uint256 quoteAmount = _hem(_random(), 10e18, 40_000_000e18);
        uint256 baseAmount = quoteAmount.fullMulDiv(1e18, 4000e18);
        uint256 lotSize = perpManager.getLotSize(ETH);

        vm.assume(baseAmount % lotSize != 0); // ensure conversion does not conform to lot size

        baseAmount = _conformLots(ETH, baseAmount);

        PlaceOrderArgs memory makerArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: side,
            limitPrice: 4000e18,
            amount: quoteAmount,
            baseDenominated: false, // quote denominated
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        vm.prank(rite);
        PlaceOrderResult memory result = perpManager.placeOrder(rite, makerArgs);

        assertEq(result.basePosted, baseAmount, "base posted wrong");
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                             GTC TAKER FILL
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_Perp_PlaceOrder_Mic_GTCTakerFill_Buy(uint256) public {
        uint256 fillPrice = _conformTick(ETH, _hem(_random(), 1e18, 10_000e18));
        uint256 fillAmount = _conformLots(ETH, _hem(_random(), 1e18, 100e18));
        uint256 limitPrice = _conformLots(ETH, _hem(_random(), 11_000e18, 100_000e18));
        uint256 postAmount = _conformLots(ETH, _hem(_random(), 1e18, 100e18));

        _createLimitOrder({asset: ETH, maker: jb, subaccount: 1, price: fillPrice, amount: fillAmount, side: Side.SELL});

        perpManager.mockSetMarkPrice(ETH, fillPrice);

        PlaceOrderArgs memory makerArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.BUY,
            limitPrice: limitPrice,
            amount: postAmount + fillAmount,
            baseDenominated: true,
            tif: TiF.GTC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        uint256 freeCollateralBefore = perpManager.getFreeCollateralBalance(rite);

        vm.prank(rite);
        PlaceOrderResult memory result = perpManager.placeOrder(rite, makerArgs);

        assertEq(result.baseTraded, fillAmount, "base traded wrong");
        assertEq(result.basePosted, postAmount, "base posted wrong");
        assertEq(result.quoteTraded, fillAmount.fullMulDiv(fillPrice, 1e18), "quote traded wrong");

        // process trade on empty position
        Position memory expectedPosition;
        expectedPosition.processTrade(Side.BUY, result.quoteTraded, result.baseTraded);

        uint256 tradeCost = result.quoteTraded;
        uint256 postCost = postAmount.fullMulDiv(limitPrice, 1e18);
        uint256 fee = result.quoteTraded * TAKER_BASE_FEE_RATE / 10_000_000;

        Position memory position = perpManager.getPosition(ETH, rite, 1);
        assertEq(position.amount, expectedPosition.amount, "base wrong");
        assertEq(position.openNotional, expectedPosition.openNotional, "open notional wrong");
        assertEq(position.isLong, expectedPosition.isLong, "is long wrong");

        assertEq(perpManager.getMarginBalance(rite, 1), int256(tradeCost - fee), "margin balance wrong");

        assertEq(
            perpManager.getFreeCollateralBalance(rite),
            freeCollateralBefore - tradeCost - postCost,
            "free collateral wrong"
        );
    }

    function test_Perp_PlaceOrder_Mic_GTCTakerFill_Sell(uint256) public {
        uint256 fillPrice = _conformTick(ETH, _hem(_random(), 11_000e18, 100_000e18));
        uint256 fillAmount = _conformLots(ETH, _hem(_random(), 1e18, 100e18));
        uint256 limitPrice = _conformLots(ETH, _hem(_random(), 1e18, 10_000e18));
        uint256 postAmount = _conformLots(ETH, _hem(_random(), 1e18, 100e18));

        _createLimitOrder({asset: ETH, maker: jb, subaccount: 1, price: fillPrice, amount: fillAmount, side: Side.BUY});

        perpManager.mockSetMarkPrice(ETH, fillPrice);

        PlaceOrderArgs memory makerArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.SELL,
            limitPrice: limitPrice,
            amount: postAmount + fillAmount,
            baseDenominated: true,
            tif: TiF.GTC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        uint256 freeCollateralBefore = perpManager.getFreeCollateralBalance(rite);

        vm.prank(rite);
        PlaceOrderResult memory result = perpManager.placeOrder(rite, makerArgs);

        assertEq(result.baseTraded, fillAmount, "base traded wrong");
        assertEq(result.basePosted, postAmount, "base posted wrong");
        assertEq(result.quoteTraded, fillAmount.fullMulDiv(fillPrice, 1e18), "quote traded wrong");

        // process trade on empty position
        Position memory expectedPosition;
        expectedPosition.processTrade(Side.SELL, result.quoteTraded, result.baseTraded);

        uint256 tradeCost = result.quoteTraded;
        uint256 postCost = postAmount.fullMulDiv(limitPrice, 1e18);
        uint256 fee = result.quoteTraded * TAKER_BASE_FEE_RATE / 10_000_000;

        Position memory position = perpManager.getPosition(ETH, rite, 1);
        assertEq(position.amount, expectedPosition.amount, "base wrong");
        assertEq(position.openNotional, expectedPosition.openNotional, "open notional wrong");
        assertEq(position.isLong, expectedPosition.isLong, "is long wrong");

        assertEq(perpManager.getMarginBalance(rite, 1), int256(tradeCost - fee), "margin balance wrong");

        assertEq(
            perpManager.getFreeCollateralBalance(rite),
            freeCollateralBefore - tradeCost - postCost,
            "free collateral wrong"
        );
    }
}
