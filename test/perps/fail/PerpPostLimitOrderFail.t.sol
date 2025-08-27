// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "../PerpManagerTestBase.sol";

/// note reduce only cap is tested separately

import {BookLib} from "../../../contracts/perps/types/Book.sol";

contract PerpPostLimitOrderFailTest is PerpManagerTestBase {
    using FixedPointMathLib for *;
    using SafeCastLib for uint256;

    error OrderPriceOutOfBounds();
    error LimitOrderAmountOutOfBounds();
    error LimitsPlacedExceedsMaxThisTx();
    error PostOnlyOrderWouldBeFilled();
    error LimitOrderAmountNotOnLotSize();
    error NotReduceOnly();
    error InvalidMakerPrice();
    error ZeroOrder();

    function test_Perp_LimitFail_NoLimitPrice(uint256) public {
        PlaceOrderArgs memory args = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: _randomChance(2) ? Side.BUY : Side.SELL,
            limitPrice: 0, // limit price is zero
            amount: _hem(_random(), 1e18, 100_000e18),
            baseDenominated: true,
            tif: _randomChance(2) ? TiF.GTC : TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        vm.prank(rite);
        vm.expectRevert(InvalidMakerPrice.selector);
        perpManager.placeOrder(rite, args);
    }

    function test_Perp_LimitFail_TickSize(uint256) public {
        PlaceOrderArgs memory args = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: _randomChance(2) ? Side.BUY : Side.SELL,
            limitPrice: _hem(_random(), 1e18, 100_000e18),
            amount: 1e18,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        uint256 tickSize = perpManager.getTickSize(ETH);

        args.limitPrice -= args.limitPrice % tickSize;

        // price does not conform to tick size
        args.limitPrice += _hem(_random(), 1, tickSize - 1);

        vm.prank(rite);
        vm.expectRevert(OrderPriceOutOfBounds.selector);
        perpManager.placeOrder(rite, args);
    }

    function test_Perp_LimitFail_MinLimitOrder(uint256) public {
        uint256 minLimitOrder = perpManager.getMinLimitOrderAmountInBase(ETH);

        PlaceOrderArgs memory args = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: _randomChance(2) ? Side.BUY : Side.SELL,
            limitPrice: _hem(_random(), 1e18, 100_000e18),
            amount: _hem(_random(), 1, minLimitOrder - 1), // amount is less than min limit order,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        args.limitPrice -= args.limitPrice % perpManager.getTickSize(ETH);

        vm.prank(rite);
        vm.expectRevert(ZeroOrder.selector);
        perpManager.placeOrder(rite, args);
    }

    function test_LimitFail_MaxLimitsPerTx(uint256) public {
        uint256 maxLimits = _hem(_random(), 1, 10);

        vm.prank(admin);
        perpManager.setMaxLimitsPerTx(ETH, uint8(maxLimits));

        PlaceOrderArgs memory args = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: _randomChance(2) ? Side.BUY : Side.SELL,
            limitPrice: 10e18,
            amount: _conformLots(ETH, _hem(_random(), 1e18, 100_000e18)),
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        args.limitPrice -= args.limitPrice % perpManager.getTickSize(ETH);

        vm.startPrank(rite);
        for (uint256 i; i < maxLimits; i++) {
            perpManager.placeOrder(rite, args);
        }

        vm.expectRevert(LimitsPlacedExceedsMaxThisTx.selector);
        perpManager.placeOrder(rite, args);
    }

    function test_Perp_LimitFail_NotPostOnly_Buy(uint256) public {
        PlaceOrderArgs memory args = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.SELL,
            limitPrice: _hem(_random(), 1e18, 50_000e18),
            amount: 1e18,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        args.limitPrice -= args.limitPrice % perpManager.getTickSize(ETH);

        vm.prank(jb);
        perpManager.placeOrder(jb, args);

        args.side = Side.BUY;
        args.limitPrice = _hem(_random(), args.limitPrice, 100_000e18);

        args.limitPrice -= args.limitPrice % perpManager.getTickSize(ETH);

        vm.prank(rite);
        vm.expectRevert(PostOnlyOrderWouldBeFilled.selector);
        perpManager.placeOrder(rite, args);
    }

    function test_Perp_LimitFail_NotPostOnly_Sell(uint256) public {
        PlaceOrderArgs memory args = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.BUY,
            limitPrice: _hem(_random(), 50e18, 100_000e18),
            amount: 1e18,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        args.limitPrice -= args.limitPrice % perpManager.getTickSize(ETH);

        vm.prank(jb);
        perpManager.placeOrder(jb, args);

        args.side = Side.SELL;
        args.limitPrice = _hem(_random(), 1e18, args.limitPrice);

        args.limitPrice -= args.limitPrice % perpManager.getTickSize(ETH);

        vm.prank(rite);
        vm.expectRevert(PostOnlyOrderWouldBeFilled.selector);
        perpManager.placeOrder(rite, args);
    }

    function test_Perp_LimitFail_CustomClientOrderId(uint256) public {
        address maker = _randomNonZeroAddress();

        vm.assume(maker.code.length == 0); // ensure it's not a contract

        usdc.mint(maker, 100_000e18);

        uint96 clientOrderId = uint96(_hem(_random(), 1, type(uint96).max));

        PlaceOrderArgs memory makerArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: _randomChance(2) ? Side.BUY : Side.SELL,
            limitPrice: 4000e18,
            amount: 1e18,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: clientOrderId,
            reduceOnly: false
        });

        vm.startPrank(maker);

        usdc.approve(address(perpManager), 100_000e18);
        perpManager.deposit(maker, 100_000e18);

        perpManager.placeOrder(maker, makerArgs);

        vm.expectRevert(BookLib.OrderIdInUse.selector);
        perpManager.placeOrder(maker, makerArgs);
    }

    function test_Perp_LimitOrderFail_NotReduceOnly_NoPosition(uint256) public {
        PlaceOrderArgs memory makerArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: _randomChance(2) ? Side.BUY : Side.SELL,
            limitPrice: _conformTick(ETH, _hem(_random(), 1e18, 100_000e18)),
            amount: _conformLots(ETH, _hem(_random(), 1e18, 1000e18)),
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: true
        });

        vm.prank(rite);
        vm.expectRevert(NotReduceOnly.selector);
        perpManager.placeOrder(rite, makerArgs);
    }

    function test_Perp_LimitOrderFail_NotReduceOnly_WrongSide(uint256) public {
        Side side = _randomChance(2) ? Side.BUY : Side.SELL;

        _placeTrade({subaccount: 1, asset: ETH, taker: rite, maker: jb, price: 4000e18, amount: 1e18, side: side});

        PlaceOrderArgs memory makerArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: side, // same side as position
            limitPrice: 4000e18,
            amount: 1e18,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: true
        });

        vm.prank(rite);
        vm.expectRevert(NotReduceOnly.selector);
        perpManager.placeOrder(rite, makerArgs);
    }

    function test_Perp_LimitOrderFail_NotReduceOnly_InsufficientPosition(uint256) public {
        Side side = _randomChance(2) ? Side.BUY : Side.SELL;
        uint256 lotSize = perpManager.getLotSize(ETH);

        uint256 amount = _conformAmountToLots(_hem(_random(), 1e18, 100e18));

        _placeTrade({
            subaccount: 1,
            asset: ETH,
            taker: rite,
            maker: jb,
            price: 4000e18,
            amount: amount - lotSize, // ensure position is less than amount
            side: side
        });

        PlaceOrderArgs memory args = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: side == Side.BUY ? Side.SELL : Side.BUY,
            limitPrice: 4000e18,
            amount: amount,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: true
        });

        vm.prank(rite);
        vm.expectRevert(NotReduceOnly.selector);
        perpManager.placeOrder(rite, args);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               HELPER
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _conformAmountToLots(uint256 amount) internal view returns (uint256) {
        uint256 lotSize = perpManager.getLotSize(ETH);
        return amount / lotSize * lotSize;
    }
}
