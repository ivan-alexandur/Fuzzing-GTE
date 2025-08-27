// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "../PerpManagerTestBase.sol";

contract OrderbookNotionalTest is PerpManagerTestBase {
    using FixedPointMathLib for uint256;

    function setUp() public override {
        super.setUp();

        vm.prank(rite);
        perpManager.deposit(rite, 70_000_000e18);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                POST
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_Perp_OrderbookNotional_Post_NoReduceOnly(uint256) public {
        vm.startPrank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, _hem(_random(), 1e18, 50e18));

        PlaceOrderArgs memory order1Args = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.BUY,
            limitPrice: _conformTickEth(_hem(_random(), 1e18, 200_000e18)),
            amount: _conformLotsEth(_hem(_random(), 0.01e18, 50e18)),
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0, // no expiry
            clientOrderId: 0,
            reduceOnly: false
        });

        PlaceOrderArgs memory order2Args = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.BUY,
            limitPrice: _conformTickEth(_hem(_random(), 1e18, 200_000e18)),
            amount: _conformLotsEth(_hem(_random(), 0.01e18, 50e18)),
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0, // no expiry
            clientOrderId: 0,
            reduceOnly: false
        });

        uint256 notional1 = order1Args.amount.fullMulDiv(order1Args.limitPrice, 1e18);
        uint256 notional2 = order2Args.amount.fullMulDiv(order2Args.limitPrice, 1e18);

        perpManager.placeOrder(rite, order1Args);

        assertEq(perpManager.getOrderbookNotional(ETH, rite, 1), notional1, "orderbook notional 1 wrong");

        perpManager.placeOrder(rite, order2Args);

        assertEq(perpManager.getOrderbookNotional(ETH, rite, 1), notional1 + notional2, "orderbook notional 2 wrong");
    }

    function test_Perp_OrderbookNotional_Post_ReduceOnly(uint256) public {
        vm.startPrank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, _hem(_random(), 1e18, 50e18));

        uint256 orderAmount = _conformLotsEth(_hem(_random(), 1e18, 50e18));

        _placeTrade({
            subaccount: 1,
            asset: ETH,
            taker: rite,
            maker: jb,
            price: 4000e18,
            amount: orderAmount,
            side: Side.SELL
        });

        vm.startPrank(rite);
        PlaceOrderArgs memory order1Args = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.BUY,
            limitPrice: _conformTickEth(_hem(_random(), 1e18, 200_000e18)),
            amount: _conformLotsEth(_hem(_random(), 0.01e18, 50e18)),
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0, // no expiry
            clientOrderId: 0,
            reduceOnly: false
        });

        PlaceOrderArgs memory order2Args = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.BUY,
            limitPrice: _conformTickEth(_hem(_random(), 1e18, 200_000e18)),
            amount: _conformLotsEth(_hem(_random(), 0.1e18, orderAmount)),
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0, // no expiry
            clientOrderId: 0,
            reduceOnly: true
        });

        uint256 notional = order1Args.amount.fullMulDiv(order1Args.limitPrice, 1e18);

        perpManager.placeOrder(rite, order1Args);

        assertEq(perpManager.getOrderbookNotional(ETH, rite, 1), notional, "orderbook notional 1 wrong");

        perpManager.placeOrder(rite, order2Args);

        assertEq(perpManager.getOrderbookNotional(ETH, rite, 1), notional, "orderbook notional 2 wrong");
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                FILL
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_Perp_OrderbookNotional_Fill_NoReduceOnly(uint256) public {
        vm.startPrank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, _hem(_random(), 1e18, 10e18));

        PlaceOrderArgs memory makerArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.BUY,
            limitPrice: _conformTickEth(_hem(_random(), 1e18, 200_000e18)),
            amount: _conformLotsEth(_hem(_random(), 0.1e18, 50e18)),
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0, // no expiry
            clientOrderId: 0,
            reduceOnly: false
        });

        perpManager.mockSetMarkPrice(ETH, makerArgs.limitPrice);

        uint256 orderId = perpManager.placeOrder(rite, makerArgs).orderId;

        PlaceOrderArgs memory takerArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.SELL,
            limitPrice: makerArgs.limitPrice,
            amount: _conformLotsEth(_hem(_random(), 0.01e18, makerArgs.amount)),
            baseDenominated: true,
            tif: TiF.IOC,
            expiryTime: 0, // no expiry
            clientOrderId: 0,
            reduceOnly: false
        });

        vm.startPrank(jb);
        perpManager.deposit(jb, 10_000_000e18);
        perpManager.placeOrder(jb, takerArgs);

        uint256 notional = perpManager.getLimitOrder(ETH, orderId).amount.fullMulDiv(makerArgs.limitPrice, 1e18);

        assertEq(perpManager.getOrderbookNotional(ETH, rite, 1), notional, "orderbook notional wrong after fill");
    }

    function test_Perp_OrderbookNotional_Fill_ReduceOnly(uint256) public {
        vm.prank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, _hem(_random(), 1e18, 10e18));

        uint256 orderAmount = _conformLotsEth(_hem(_random(), 2e18, 50e18));

        _placeTrade({
            subaccount: 1,
            asset: ETH,
            taker: rite,
            maker: jb,
            price: 4000e18,
            amount: orderAmount,
            side: Side.SELL
        });

        vm.startPrank(rite);

        PlaceOrderArgs memory makerArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.BUY,
            limitPrice: _conformTickEth(_hem(_random(), 3995e18, 4005e18)),
            amount: orderAmount,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0, // no expiry
            clientOrderId: 0,
            reduceOnly: true
        });

        perpManager.placeOrder(rite, makerArgs);

        PlaceOrderArgs memory takerArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.SELL,
            limitPrice: makerArgs.limitPrice,
            amount: orderAmount,
            baseDenominated: true,
            tif: TiF.IOC,
            expiryTime: 0, // no expiry
            clientOrderId: 0,
            reduceOnly: false
        });

        vm.startPrank(jb);
        perpManager.deposit(jb, 100_000e18);
        perpManager.placeOrder(jb, takerArgs);

        assertEq(perpManager.getOrderbookNotional(ETH, rite, 1), 0, "orderbook notional wrong after fill");
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                AMEND
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_Perp_OrderbookNotional_Amend_Notional(uint256) public {
        vm.startPrank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, _hem(_random(), 1e18, 50e18));

        PlaceOrderArgs memory orderArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.BUY,
            amount: _conformLotsEth(_hem(_random(), 0.01e18, 50e18)),
            limitPrice: _conformTickEth(_hem(_random(), 1e18, 200_000e18)),
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0, // no expiry
            clientOrderId: 0,
            reduceOnly: false
        });

        uint256 orderId = perpManager.placeOrder(rite, orderArgs).orderId;

        AmendLimitOrderArgs memory amendArgs = AmendLimitOrderArgs({
            asset: ETH,
            subaccount: 1,
            orderId: orderId,
            baseAmount: _conformLotsEth(_hem(_random(), 0.01e18, 50e18)),
            price: _conformTickEth(_hem(_random(), 1e18, 200_000e18)),
            expiryTime: 0,
            side: Side.BUY,
            reduceOnly: false
        });

        uint256 notional = amendArgs.baseAmount.fullMulDiv(amendArgs.price, 1e18);

        perpManager.amendLimitOrder(rite, amendArgs);

        assertEq(perpManager.getOrderbookNotional(ETH, rite, 1), notional, "orderbook notional wrong after amend");
    }

    function test_Perp_OrderbookNotional_Amend_ToReduceOnly(uint256) public {
        vm.startPrank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, _hem(_random(), 1e18, 50e18));

        uint256 orderAmount = _conformLotsEth(_hem(_random(), 1e18, 50e18));

        _placeTrade({
            subaccount: 1,
            asset: ETH,
            taker: rite,
            maker: jb,
            price: 4000e18,
            amount: orderAmount,
            side: Side.SELL
        });

        uint256 orderId = _createLimitOrder({
            asset: ETH,
            maker: rite,
            subaccount: 1,
            price: _conformTickEth(_hem(_random(), 1e18, 200_000e18)),
            amount: _conformLotsEth(_hem(_random(), 0.01e18, 50e18)),
            side: Side.BUY
        });

        AmendLimitOrderArgs memory amendArgs = AmendLimitOrderArgs({
            asset: ETH,
            subaccount: 1,
            orderId: orderId,
            baseAmount: _conformLotsEth(_hem(_random(), 0.1e18, orderAmount)),
            price: _conformTickEth(_hem(_random(), 1e18, 200_000e18)),
            expiryTime: 0,
            side: Side.BUY,
            reduceOnly: true
        });

        vm.prank(rite);
        perpManager.amendLimitOrder(rite, amendArgs);

        assertEq(perpManager.getOrderbookNotional(ETH, rite, 1), 0, "orderbook notional wrong after amend");
    }

    function test_Perp_OrderbookNotional_Amend_FromReduceOnly(uint256) public {
        vm.startPrank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, _hem(_random(), 1e18, 50e18));

        uint256 orderAmount = _conformLotsEth(_hem(_random(), 1e18, 50e18));

        _placeTrade({
            subaccount: 1,
            asset: ETH,
            taker: rite,
            maker: jb,
            price: 4000e18,
            amount: orderAmount,
            side: Side.SELL
        });

        vm.startPrank(rite);

        PlaceOrderArgs memory orderArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.BUY,
            amount: _conformLotsEth(_hem(_random(), 0.01e18, orderAmount)),
            limitPrice: _conformTickEth(_hem(_random(), 1e18, 200_000e18)),
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0, // no expiry
            clientOrderId: 0,
            reduceOnly: true
        });

        uint256 orderId = perpManager.placeOrder(rite, orderArgs).orderId;

        AmendLimitOrderArgs memory amendArgs = AmendLimitOrderArgs({
            asset: ETH,
            subaccount: 1,
            orderId: orderId,
            baseAmount: _conformLotsEth(_hem(_random(), 0.01e18, 50e18)),
            price: _conformTickEth(_hem(_random(), 1e18, 200_000e18)),
            expiryTime: 0,
            side: Side.BUY,
            reduceOnly: false
        });

        uint256 notional = amendArgs.baseAmount.fullMulDiv(amendArgs.price, 1e18);

        perpManager.amendLimitOrder(rite, amendArgs);

        assertEq(perpManager.getOrderbookNotional(ETH, rite, 1), notional, "orderbook notional wrong after amend");
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                 CANCEL
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_Perp_OrderbookNotional_Cancel_NoReduceOnly(uint256) public {
        vm.prank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, _hem(_random(), 1e18, 50e18));

        uint256[] memory orderIds = new uint256[](2);

        orderIds[0] = _createLimitOrder({
            asset: ETH,
            maker: rite,
            subaccount: 1,
            price: _conformTickEth(_hem(_random(), 1e18, 200_000e18)),
            amount: _conformLotsEth(_hem(_random(), 0.01e18, 50e18)),
            side: Side.BUY
        });

        orderIds[1] = _createLimitOrder({
            asset: ETH,
            maker: rite,
            subaccount: 1,
            price: _conformTickEth(_hem(_random(), 1e18, 200_000e18)),
            amount: _conformLotsEth(_hem(_random(), 0.01e18, 50e18)),
            side: Side.BUY
        });

        vm.prank(rite);
        perpManager.cancelLimitOrders(ETH, rite, 1, orderIds);

        assertEq(perpManager.getOrderbookNotional(ETH, rite, 1), 0, "orderbook notional wrong after cancel");
    }

    function test_Perp_OrderbookNotional_Cancel_ReduceOnly(uint256) public {
        vm.startPrank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, _hem(_random(), 1e18, 50e18));

        uint256 orderAmount = _conformLotsEth(_hem(_random(), 1e18, 50e18));

        _placeTrade({
            subaccount: 1,
            asset: ETH,
            taker: rite,
            maker: jb,
            price: 4000e18,
            amount: orderAmount,
            side: Side.SELL
        });

        vm.startPrank(rite);

        PlaceOrderArgs memory order1Args = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.BUY,
            amount: _conformLotsEth(_hem(_random(), 0.01e18, orderAmount)),
            limitPrice: _conformTickEth(_hem(_random(), 1e18, 200_000e18)),
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0, // no expiry
            clientOrderId: 0,
            reduceOnly: true
        });

        PlaceOrderArgs memory order2Args = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.BUY,
            amount: _conformLotsEth(_hem(_random(), 0.01e18, 50e18)),
            limitPrice: _conformTickEth(_hem(_random(), 1e18, 200_000e18)),
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0, // no expiry
            clientOrderId: 0,
            reduceOnly: false
        });

        uint256 notional = order2Args.amount.fullMulDiv(order2Args.limitPrice, 1e18);

        uint256[] memory orderIds = new uint256[](1);

        orderIds[0] = perpManager.placeOrder(rite, order1Args).orderId;
        perpManager.placeOrder(rite, order2Args);

        perpManager.cancelLimitOrders(ETH, rite, 1, orderIds);

        assertEq(perpManager.getOrderbookNotional(ETH, rite, 1), notional, "orderbook notional wrong after cancel");
    }

    function test_Perp_OrderbookNotional_Expired_NoReduceOnly(uint256) public {
        vm.startPrank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, _hem(_random(), 1e18, 50e18));

        PlaceOrderArgs memory order1Args = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.SELL,
            amount: _conformLotsEth(_hem(_random(), 0.01e18, 50e18)),
            limitPrice: 4000e18,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: uint32(vm.getBlockTimestamp() + 1),
            clientOrderId: 0,
            reduceOnly: false
        });

        PlaceOrderArgs memory order2Args = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.SELL,
            amount: _conformLotsEth(_hem(_random(), 0.01e18, 50e18)),
            limitPrice: _conformTickEth(_hem(_random(), 5000e18, 200_000e18)), // far from traded price
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        perpManager.placeOrder(rite, order1Args);
        perpManager.placeOrder(rite, order2Args);

        uint256 notional = order2Args.amount.fullMulDiv(order2Args.limitPrice, 1e18);

        vm.warp(vm.getBlockTimestamp() + 10);

        _placeTrade({subaccount: 1, asset: ETH, taker: nate, maker: jb, price: 4000e18, amount: 1e18, side: Side.BUY});

        assertEq(perpManager.getPosition(ETH, rite, 1).amount, 0, "order was not cancelled");
        assertEq(perpManager.getOrderbookNotional(ETH, rite, 1), notional, "orderbook notional wrong after cancel");
    }

    function test_Perp_OrderbookNotional_Expired_ReduceOnly(uint256) public {
        vm.startPrank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, _hem(_random(), 1e18, 50e18));

        _placeTrade({subaccount: 1, asset: ETH, taker: rite, maker: jb, price: 4000e18, amount: 1e18, side: Side.BUY});

        vm.startPrank(rite);
        PlaceOrderArgs memory order1Args = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.SELL,
            amount: 1e18,
            limitPrice: 4000e18,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: uint32(vm.getBlockTimestamp() + 1),
            clientOrderId: 0,
            reduceOnly: true
        });

        PlaceOrderArgs memory order2Args = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.SELL,
            amount: _conformLotsEth(_hem(_random(), 0.01e18, 50e18)),
            limitPrice: _conformTickEth(_hem(_random(), 5000e18, 200_000e18)), // far from traded price
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: uint32(vm.getBlockTimestamp() + 1),
            clientOrderId: 0,
            reduceOnly: false
        });

        perpManager.placeOrder(rite, order1Args);
        perpManager.placeOrder(rite, order2Args);

        uint256 notional = order2Args.amount.fullMulDiv(order2Args.limitPrice, 1e18);

        vm.warp(vm.getBlockTimestamp() + 2);

        _placeTrade({subaccount: 1, asset: ETH, taker: nate, maker: jb, price: 4000e18, amount: 1e18, side: Side.BUY});

        assertEq(perpManager.getPosition(ETH, rite, 1).amount, 1e18, "order was not cancelled");
        assertEq(perpManager.getOrderbookNotional(ETH, rite, 1), notional, "orderbook notional wrong after cancel");
    }
}
