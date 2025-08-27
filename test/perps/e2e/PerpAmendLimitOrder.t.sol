// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "../PerpManagerTestBase.sol";

contract PerpAmendLimitOrderTest is PerpManagerTestBase {
    using FixedPointMathLib for *;

    PlaceOrderArgs limitArgs;
    AmendLimitOrderArgs amendArgs;
    uint256 balanceBefore;
    uint256 orderValueBefore;
    uint256 orderValue;
    int256 collateralDelta;
    uint256 quoteOI;
    uint256 baseOI;

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                             NO REDUCE ONLY
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_Perp_Amend_NewOrder_NewPrice_NoReduceOnly(uint256) public {
        vm.startPrank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, _hem(_random(), 1e18, 50e18));

        _generateRandomOrder(false);

        uint256 orderId = perpManager.placeOrder(rite, limitArgs).orderId;

        balanceBefore = perpManager.getFreeCollateralBalance(rite);

        amendArgs = AmendLimitOrderArgs({
            asset: ETH,
            subaccount: 1,
            orderId: orderId,
            price: _conformToTick(_hem(_random(), 100e18, 5000e18)),
            baseAmount: limitArgs.amount,
            expiryTime: 0,
            side: limitArgs.side,
            reduceOnly: false
        });

        orderValueBefore = _getOrderValue(rite, limitArgs);
        orderValue = _getOrderValue(rite, amendArgs);

        collateralDelta = perpManager.amendLimitOrder({account: rite, args: amendArgs});

        _assertPostAmendState();
    }

    function test_Perp_Amend_NewOrder_NewExpiry_NoReduceOnly(uint256) public {
        vm.startPrank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, _hem(_random(), 1e18, 50e18));

        _generateRandomOrder(false);

        uint256 orderId = perpManager.placeOrder(rite, limitArgs).orderId;

        balanceBefore = perpManager.getFreeCollateralBalance(rite);

        amendArgs = AmendLimitOrderArgs({
            asset: ETH,
            subaccount: 1,
            orderId: orderId,
            price: limitArgs.limitPrice,
            baseAmount: limitArgs.amount,
            expiryTime: uint32(block.timestamp + _hem(_random(), 1, 1000)),
            side: limitArgs.side,
            reduceOnly: false
        });

        orderValueBefore = _getOrderValue(rite, limitArgs);
        orderValue = _getOrderValue(rite, amendArgs);

        collateralDelta = perpManager.amendLimitOrder({account: rite, args: amendArgs});

        _assertPostAmendState();
    }

    function test_Perp_Amend_NewOrder_NewSide_NoReduceOnly(uint256) public {
        vm.startPrank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, _hem(_random(), 1e18, 50e18));

        _generateRandomOrder(false);

        orderValueBefore = _getOrderValue(rite, limitArgs);

        uint256 orderId = perpManager.placeOrder(rite, limitArgs).orderId;

        balanceBefore = perpManager.getFreeCollateralBalance(rite);

        amendArgs = AmendLimitOrderArgs({
            asset: ETH,
            subaccount: 1,
            orderId: orderId,
            price: limitArgs.limitPrice,
            baseAmount: limitArgs.amount,
            expiryTime: 0,
            side: limitArgs.side == Side.BUY ? Side.SELL : Side.BUY, // Change side
            reduceOnly: false
        });

        orderValue = _getOrderValue(rite, amendArgs);

        collateralDelta = perpManager.amendLimitOrder({account: rite, args: amendArgs});

        _assertPostAmendState();
    }

    function test_Perp_Amend_NewAmount_NoReduceOnly(uint256) public {
        vm.startPrank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, _hem(_random(), 1e18, 50e18));

        _generateRandomOrder(false);

        orderValueBefore = _getOrderValue(rite, limitArgs);

        uint256 orderId = perpManager.placeOrder(rite, limitArgs).orderId;

        balanceBefore = perpManager.getFreeCollateralBalance(rite);

        amendArgs = AmendLimitOrderArgs({
            asset: ETH,
            subaccount: 1,
            orderId: orderId,
            price: limitArgs.limitPrice,
            baseAmount: _conformToLots(_hem(_random(), 1e18, 100e18)),
            expiryTime: 0,
            side: limitArgs.side,
            reduceOnly: false
        });

        orderValue = _getOrderValue(rite, amendArgs);

        collateralDelta = perpManager.amendLimitOrder({account: rite, args: amendArgs});

        _assertPostAmendState();
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                              REDUCE ONLY
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_Perp_Amend_NewOrder_NewPrice_ReduceOnlyToReduceOnly(uint256) public {
        vm.prank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, _hem(_random(), 1e18, 50e18));

        _generateRandomOrder(true);

        _placeTrade({
            subaccount: 1,
            asset: ETH,
            taker: rite,
            maker: jb,
            price: 4000e18,
            amount: limitArgs.amount,
            side: limitArgs.side == Side.BUY ? Side.SELL : Side.BUY
        });

        vm.startPrank(rite);
        uint256 orderId = perpManager.placeOrder(rite, limitArgs).orderId;

        balanceBefore = perpManager.getFreeCollateralBalance(rite);

        amendArgs = AmendLimitOrderArgs({
            asset: ETH,
            subaccount: 1,
            orderId: orderId,
            price: _conformToTick(_hem(_random(), 100e18, 5000e18)),
            baseAmount: limitArgs.amount,
            expiryTime: 0,
            side: limitArgs.side,
            reduceOnly: true
        });

        collateralDelta = perpManager.amendLimitOrder({account: rite, args: amendArgs});

        _assertPostAmendState();
    }

    function test_Perp_Amend_NewOrder_NewPrice_ReduceOnlyToNonReduceOnly(uint256) public {
        vm.prank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, _hem(_random(), 1e18, 50e18));

        _generateRandomOrder(true);

        _placeTrade({
            subaccount: 1,
            asset: ETH,
            taker: rite,
            maker: jb,
            price: 4000e18,
            amount: limitArgs.amount,
            side: limitArgs.side == Side.BUY ? Side.SELL : Side.BUY
        });

        vm.startPrank(rite);
        uint256 orderId = perpManager.placeOrder(rite, limitArgs).orderId;

        balanceBefore = perpManager.getFreeCollateralBalance(rite);

        amendArgs = AmendLimitOrderArgs({
            asset: ETH,
            subaccount: 1,
            orderId: orderId,
            price: _conformToTick(_hem(_random(), 100e18, 5000e18)),
            baseAmount: limitArgs.amount,
            expiryTime: 0,
            side: limitArgs.side,
            reduceOnly: false
        });

        orderValue = _getOrderValue(rite, amendArgs);

        collateralDelta = perpManager.amendLimitOrder({account: rite, args: amendArgs});

        _assertPostAmendState();
    }

    function test_Perp_Amend_NewOrder_NewPrice_NonReduceOnlyToReduceOnly(uint256) public {
        vm.prank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, _hem(_random(), 1e18, 50e18));

        _generateRandomOrder(false);

        orderValueBefore = _getOrderValue(rite, limitArgs);

        _placeTrade({
            subaccount: 1,
            asset: ETH,
            taker: rite,
            maker: jb,
            price: 4000e18,
            amount: limitArgs.amount,
            side: limitArgs.side == Side.BUY ? Side.SELL : Side.BUY
        });

        vm.startPrank(rite);
        uint256 orderId = perpManager.placeOrder(rite, limitArgs).orderId;

        balanceBefore = perpManager.getFreeCollateralBalance(rite);

        amendArgs = AmendLimitOrderArgs({
            asset: ETH,
            subaccount: 1,
            orderId: orderId,
            price: _conformToTick(_hem(_random(), 100e18, 5000e18)),
            baseAmount: limitArgs.amount,
            expiryTime: 0,
            side: limitArgs.side,
            reduceOnly: true
        });

        collateralDelta = perpManager.amendLimitOrder({account: rite, args: amendArgs});

        _assertPostAmendState();
    }

    function test_Perp_Amend_NewOrder_NewSide_ReduceOnlyToNonReduceOnly(uint256) public {
        vm.prank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, _hem(_random(), 1e18, 50e18));

        _generateRandomOrder(true);

        _placeTrade({
            subaccount: 1,
            asset: ETH,
            taker: rite,
            maker: jb,
            price: 4000e18,
            amount: limitArgs.amount,
            side: limitArgs.side == Side.BUY ? Side.SELL : Side.BUY
        });

        vm.startPrank(rite);
        uint256 orderId = perpManager.placeOrder(rite, limitArgs).orderId;

        balanceBefore = perpManager.getFreeCollateralBalance(rite);

        amendArgs = AmendLimitOrderArgs({
            asset: ETH,
            subaccount: 1,
            orderId: orderId,
            price: limitArgs.limitPrice,
            baseAmount: limitArgs.amount,
            expiryTime: 0,
            side: limitArgs.side == Side.BUY ? Side.SELL : Side.BUY, // Change side
            reduceOnly: false
        });

        orderValue = _getOrderValue(rite, amendArgs);

        collateralDelta = perpManager.amendLimitOrder({account: rite, args: amendArgs});

        _assertPostAmendState();
    }

    function test_Perp_Amend_NewOrder_NewSide_NonReduceOnlyToReduceOnly(uint256) public {
        vm.prank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, _hem(_random(), 1e18, 50e18));

        _generateRandomOrder(false);

        orderValueBefore = _getOrderValue(rite, limitArgs);

        _placeTrade({
            subaccount: 1,
            asset: ETH,
            taker: rite,
            maker: jb,
            price: 4000e18,
            amount: limitArgs.amount,
            side: limitArgs.side
        });

        vm.startPrank(rite);
        uint256 orderId = perpManager.placeOrder(rite, limitArgs).orderId;

        balanceBefore = perpManager.getFreeCollateralBalance(rite);

        amendArgs = AmendLimitOrderArgs({
            asset: ETH,
            subaccount: 1,
            orderId: orderId,
            price: limitArgs.limitPrice,
            baseAmount: limitArgs.amount,
            expiryTime: 0,
            side: limitArgs.side == Side.BUY ? Side.SELL : Side.BUY, // Change side
            reduceOnly: true
        });

        collateralDelta = perpManager.amendLimitOrder({account: rite, args: amendArgs});

        _assertPostAmendState();
    }

    function test_Perp_Amend_NewAmount_ReduceOnlyToReduceOnly(uint256) public {
        vm.prank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, _hem(_random(), 1e18, 50e18));

        _generateRandomOrder(true);

        _placeTrade({
            subaccount: 1,
            asset: ETH,
            taker: rite,
            maker: jb,
            price: 4000e18,
            amount: limitArgs.amount,
            side: limitArgs.side == Side.BUY ? Side.SELL : Side.BUY
        });

        vm.startPrank(rite);
        uint256 orderId = perpManager.placeOrder(rite, limitArgs).orderId;

        balanceBefore = perpManager.getFreeCollateralBalance(rite);

        amendArgs = AmendLimitOrderArgs({
            asset: ETH,
            subaccount: 1,
            orderId: orderId,
            price: limitArgs.limitPrice,
            baseAmount: _conformToLots(_hem(_random(), 1e18, limitArgs.amount)),
            expiryTime: 0,
            side: limitArgs.side,
            reduceOnly: true
        });

        collateralDelta = perpManager.amendLimitOrder({account: rite, args: amendArgs});

        _assertPostAmendState();
    }

    function test_Perp_Amend_NewAmount_ReduceOnlyToNonReduceOnly(uint256) public {
        vm.prank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, _hem(_random(), 1e18, 50e18));

        _generateRandomOrder(true);

        _placeTrade({
            subaccount: 1,
            asset: ETH,
            taker: rite,
            maker: jb,
            price: 4000e18,
            amount: limitArgs.amount,
            side: limitArgs.side == Side.BUY ? Side.SELL : Side.BUY
        });

        vm.startPrank(rite);
        uint256 orderId = perpManager.placeOrder(rite, limitArgs).orderId;

        balanceBefore = perpManager.getFreeCollateralBalance(rite);

        amendArgs = AmendLimitOrderArgs({
            asset: ETH,
            subaccount: 1,
            orderId: orderId,
            price: limitArgs.limitPrice,
            baseAmount: _conformToLots(_hem(_random(), 1e18, limitArgs.amount)),
            expiryTime: 0,
            side: limitArgs.side,
            reduceOnly: false
        });

        orderValue = _getOrderValue(rite, amendArgs);

        collateralDelta = perpManager.amendLimitOrder({account: rite, args: amendArgs});

        _assertPostAmendState();
    }

    function test_Perp_Amend_NewAmount_NonReduceOnlyToReduceOnly(uint256) public {
        vm.prank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, _hem(_random(), 1e18, 50e18));

        _generateRandomOrder(false);

        orderValueBefore = _getOrderValue(rite, limitArgs);

        _placeTrade({
            subaccount: 1,
            asset: ETH,
            taker: rite,
            maker: jb,
            price: 4000e18,
            amount: limitArgs.amount,
            side: limitArgs.side == Side.BUY ? Side.SELL : Side.BUY
        });

        vm.startPrank(rite);
        uint256 orderId = perpManager.placeOrder(rite, limitArgs).orderId;

        balanceBefore = perpManager.getFreeCollateralBalance(rite);

        amendArgs = AmendLimitOrderArgs({
            asset: ETH,
            subaccount: 1,
            orderId: orderId,
            price: limitArgs.limitPrice,
            baseAmount: _conformToLots(_hem(_random(), 1e18, limitArgs.amount)),
            expiryTime: 0,
            side: limitArgs.side,
            reduceOnly: true
        });

        collateralDelta = perpManager.amendLimitOrder({account: rite, args: amendArgs});

        _assertPostAmendState();
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _generateRandomOrder(bool reduceOnly) internal {
        limitArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: _randomChance(2) ? Side.BUY : Side.SELL,
            limitPrice: _conformToTick(_hem(_random(), 100e18, 5000e18)),
            amount: _conformToLots(_hem(_random(), 1e18, 100e18)),
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0, // no expiry
            clientOrderId: 0,
            reduceOnly: reduceOnly
        });
    }

    function _assertPostAmendState() internal {
        (baseOI, quoteOI) = perpManager.getOpenInterestBook(ETH);
        Order memory order = perpManager.getLimitOrder(ETH, amendArgs.orderId);
        uint256[] memory reduceOnlyOrders = perpManager.getReduceOnlyOrders(ETH, rite, 1);

        // return value
        assertEq(collateralDelta, int256(orderValue) - int256(orderValueBefore), "collateral delta wrong");

        // oi
        if (amendArgs.side == Side.BUY) {
            assertEq(quoteOI, amendArgs.baseAmount.fullMulDiv(amendArgs.price, 1e18), "quote OI wrong");
            assertEq(baseOI, 0, "base OI wrong");
        } else {
            assertEq(baseOI, amendArgs.baseAmount, "base OI wrong");
            assertEq(quoteOI, 0, "quote OI wrong");
        }

        // collateral
        assertEq(
            int256(balanceBefore) - int256(perpManager.getFreeCollateralBalance(rite)),
            collateralDelta,
            "collateral balance wrong"
        );

        // order
        assertEq(order.amount, amendArgs.baseAmount, "order amount wrong");
        assertEq(order.price, amendArgs.price, "order price wrong");
        assertEq(uint8(order.side), uint8(amendArgs.side), "order side wrong");
        assertEq(order.subaccount, 1, "order subaccount wrong");
        assertEq(order.owner, rite, "order owner wrong");
        assertEq(order.reduceOnly, amendArgs.reduceOnly, "order reduceOnly wrong");
        assertEq(order.expiryTime, amendArgs.expiryTime, "order expiryTime wrong");

        // reduce only link
        if (amendArgs.reduceOnly) {
            console.log(reduceOnlyOrders.length);
            assertEq(reduceOnlyOrders.length, 1, "reduce only link wrong");
            assertEq(reduceOnlyOrders[0], amendArgs.orderId, "reduce only link wrong");
        } else {
            assertEq(reduceOnlyOrders.length, 0, "reduce only link wrong");
        }
    }

    function _getOrderValue(address account, PlaceOrderArgs memory args) internal view returns (uint256) {
        return args.amount.fullMulDiv(args.limitPrice, 1e18).fullMulDiv(
            1e18, perpManager.getPositionLeverage(args.asset, account, args.subaccount)
        );
    }

    function _getOrderValue(address account, AmendLimitOrderArgs memory args) internal view returns (uint256) {
        return args.baseAmount.fullMulDiv(args.price, 1e18).fullMulDiv(
            1e18, perpManager.getPositionLeverage(args.asset, account, args.subaccount)
        );
    }

    function _conformToLots(uint256 amount) internal view returns (uint256) {
        uint256 lotSize = perpManager.getLotSize(ETH);
        return amount / lotSize * lotSize;
    }

    function _conformToTick(uint256 price) internal view returns (uint256) {
        uint256 tickSize = perpManager.getTickSize(ETH);
        if (price % tickSize == 0) return price;
        return price - (price % tickSize);
    }
}
