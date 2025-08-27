// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "../PerpManagerTestBase.sol";

import {MarketLib} from "../../../contracts/perps/types/Market.sol";

contract PerpReduceOnlyCapFailTest is PerpManagerTestBase {
    function test_Perp_ReduceOnlyCap_LimitOrderPost(uint256) public {
        uint256 cap = _hem(_random(), 1, 20);

        _placeTrade({subaccount: 1, asset: ETH, taker: rite, maker: jb, price: 4000e18, amount: 1e18, side: Side.BUY});

        PlaceOrderArgs memory args = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.SELL,
            limitPrice: 4000e18,
            amount: 1e18,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: true
        });

        vm.prank(admin);
        perpManager.setReduceOnlyCap(ETH, cap);

        vm.startPrank(rite);
        for (uint256 i; i <= cap; ++i) {
            if (i == cap) vm.expectRevert(MarketLib.ReduceOnlyCapExceeded.selector);
            perpManager.placeOrder(rite, args);
        }
    }

    function test_Perp_ReduceOnlyCap_BackstopLimitOrderPost(uint256) public {
        uint256 cap = _hem(_random(), 1, 20);

        uint256 amount = 1e18;

        _placeTrade({subaccount: 1, asset: ETH, taker: rite, maker: jb, price: 4000e18, amount: amount, side: Side.BUY});

        PlaceOrderArgs memory args = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.SELL,
            limitPrice: 4000e18,
            amount: 1e18,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: true
        });

        vm.prank(admin);
        perpManager.setReduceOnlyCap(ETH, cap);

        vm.startPrank(rite);
        for (uint256 i; i <= cap; ++i) {
            if (i == cap) vm.expectRevert(MarketLib.ReduceOnlyCapExceeded.selector);
            perpManager.postLimitOrderBackstop(rite, args);
        }
    }

    function test_Perp_ReduceOnlyCap_LimitOrderAmend(uint256) public {
        uint256 cap = _hem(_random(), 1, 20);

        uint256 amount = 1e18;

        _placeTrade({subaccount: 1, asset: ETH, taker: rite, maker: jb, price: 4000e18, amount: amount, side: Side.BUY});

        PlaceOrderArgs memory args = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.SELL,
            limitPrice: 4000e18,
            amount: 1e18,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: true
        });

        vm.prank(admin);
        perpManager.setReduceOnlyCap(ETH, cap);

        vm.startPrank(rite);

        for (uint256 i; i < cap; ++i) {
            perpManager.placeOrder(rite, args).orderId;
        }

        args.reduceOnly = false;
        uint256 id = perpManager.placeOrder(rite, args).orderId;

        AmendLimitOrderArgs memory amendArgs = AmendLimitOrderArgs({
            asset: ETH,
            subaccount: 1,
            orderId: id,
            price: args.limitPrice,
            baseAmount: args.amount,
            expiryTime: 0,
            side: args.side,
            reduceOnly: true
        });

        vm.expectRevert(MarketLib.ReduceOnlyCapExceeded.selector);
        perpManager.amendLimitOrder(rite, amendArgs);
    }

    function test_Perp_ReduceOnlyCap_BackstopLimitOrderAmend(uint256) public {
        uint256 cap = _hem(_random(), 1, 20);

        uint256 amount = 2e18;

        _placeTrade({subaccount: 1, asset: ETH, taker: rite, maker: jb, price: 4000e18, amount: amount, side: Side.BUY});

        PlaceOrderArgs memory args = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.SELL,
            limitPrice: 4000e18,
            amount: _conformLots(ETH, _hem(_random(), 1e18, amount)),
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: true
        });

        vm.prank(admin);
        perpManager.setReduceOnlyCap(ETH, cap);

        vm.startPrank(rite);

        for (uint256 i; i < cap; ++i) {
            perpManager.postLimitOrderBackstop(rite, args).orderId;
        }

        args.reduceOnly = false;
        uint256 id = perpManager.postLimitOrderBackstop(rite, args).orderId;

        AmendLimitOrderArgs memory amendArgs = AmendLimitOrderArgs({
            asset: ETH,
            subaccount: 1,
            orderId: id,
            price: args.limitPrice,
            baseAmount: args.amount,
            expiryTime: 0,
            side: args.side,
            reduceOnly: true
        });

        vm.expectRevert(MarketLib.ReduceOnlyCapExceeded.selector);
        perpManager.amendLimitOrderBackstop(rite, amendArgs);
    }

    function test_Perp_ReduceOnlyCap_BackstopVsStandardBook() public {
        uint256 cap = 1;

        _placeTrade({subaccount: 1, asset: ETH, taker: rite, maker: jb, price: 4000e18, amount: 1e18, side: Side.BUY});

        PlaceOrderArgs memory args = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.SELL,
            limitPrice: 4000e18,
            amount: 1e18,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: true
        });

        vm.prank(admin);
        perpManager.setReduceOnlyCap(ETH, cap);

        vm.startPrank(rite);

        perpManager.placeOrder(rite, args);
        perpManager.postLimitOrderBackstop(rite, args);

        vm.expectRevert(MarketLib.ReduceOnlyCapExceeded.selector);
        perpManager.placeOrder(rite, args);

        vm.expectRevert(MarketLib.ReduceOnlyCapExceeded.selector);
        perpManager.postLimitOrderBackstop(rite, args);
    }
}
