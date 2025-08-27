// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "../PerpManagerTestBase.sol";

/// note reduce only cap is tested separately

import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

import {CLOBLib} from "../../../contracts/perps/types/CLOBLib.sol";
import {CollateralManagerLib} from "../../../contracts/perps/types/CollateralManager.sol";
import {MarketLib} from "../../../contracts/perps/types/Market.sol";
import {OrderLib} from "../../../contracts/perps/types/Order.sol";
import {BookLib} from "../../../contracts/perps/types/Book.sol";

contract PerpAmendLimitOrderFailTest is PerpManagerTestBase {
    using FixedPointMathLib for uint256;

    function test_Perp_AmendFail_NoOrder(uint256) public {
        vm.prank(rite);
        vm.expectRevert(OrderLib.OrderNotFound.selector);
        perpManager.amendLimitOrder({
            account: rite,
            args: AmendLimitOrderArgs({
                asset: ETH,
                subaccount: 1,
                orderId: _hem(_random(), 1, type(uint72).max),
                price: 4000e18,
                baseAmount: 2e18,
                expiryTime: 0,
                side: Side.BUY,
                reduceOnly: false
            })
        });
    }

    function test_Perp_AmendFail_NotOwner(uint256) public {
        PlaceOrderArgs memory limitArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: _randomChance(2) ? Side.BUY : Side.SELL,
            limitPrice: 10e18,
            amount: 1e18,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        address maker = _randomUniqueNonZeroAddress();

        usdc.mint(maker, 10e18);

        vm.startPrank(maker);
        usdc.approve(address(perpManager), type(uint256).max);
        perpManager.deposit(maker, 10e18);
        uint256 orderId = perpManager.placeOrder(maker, limitArgs).orderId;
        vm.stopPrank();

        address notOwner = _randomUniqueNonZeroAddress();

        vm.prank(notOwner);
        vm.expectRevert(CLOBLib.UnauthorizedAmend.selector);
        perpManager.amendLimitOrder({
            account: notOwner,
            args: AmendLimitOrderArgs({
                asset: ETH,
                subaccount: 1,
                orderId: orderId,
                price: 4000e18,
                baseAmount: 2e18,
                expiryTime: 0,
                side: Side.BUY,
                reduceOnly: false
            })
        });
    }

    function test_Perp_AmendFail_WrongSubaccount(uint256) public {
        PlaceOrderArgs memory limitArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: _randomChance(2) ? Side.BUY : Side.SELL,
            limitPrice: 4000e18,
            amount: 1e18,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        vm.startPrank(rite);
        uint256 orderId = perpManager.placeOrder(rite, limitArgs).orderId;

        vm.expectRevert(CLOBLib.IncorrectSubaccount.selector);
        perpManager.amendLimitOrder({
            account: rite,
            args: AmendLimitOrderArgs({
                asset: ETH,
                subaccount: _hem(_random(), 2, type(uint16).max),
                orderId: orderId,
                price: 4000e18,
                baseAmount: 2e18,
                expiryTime: 0,
                side: Side.BUY,
                reduceOnly: false
            })
        });
    }

    function test_Perp_AmendFail_InvalidTickSize(uint256) public {
        PlaceOrderArgs memory limitArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: _randomChance(2) ? Side.BUY : Side.SELL,
            limitPrice: 4000e18,
            amount: 1e18,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        vm.startPrank(rite);
        uint256 orderId = perpManager.placeOrder(rite, limitArgs).orderId;

        uint256 tickSize = perpManager.getTickSize(ETH);

        vm.expectRevert(BookLib.LimitPriceOutOfBounds.selector);
        perpManager.amendLimitOrder({
            account: rite,
            args: AmendLimitOrderArgs({
                asset: ETH,
                subaccount: 1,
                orderId: orderId,
                price: limitArgs.limitPrice + _hem(_random(), 1, tickSize - 1), // Invalid tick size
                baseAmount: 2e18,
                expiryTime: 0,
                side: Side.BUY,
                reduceOnly: false
            })
        });
    }

    function test_Perp_AmendFail_NotReduceOnly_NoPosition() public {
        PlaceOrderArgs memory limitArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.SELL,
            limitPrice: 4000e18,
            amount: 1e18,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        vm.startPrank(rite);
        uint256 orderId = perpManager.placeOrder(rite, limitArgs).orderId;

        vm.expectRevert(MarketLib.NotReduceOnly.selector);
        perpManager.amendLimitOrder({
            account: rite,
            args: AmendLimitOrderArgs({
                asset: ETH,
                subaccount: 1,
                orderId: orderId,
                price: limitArgs.limitPrice,
                baseAmount: limitArgs.amount,
                expiryTime: 0,
                side: limitArgs.side,
                reduceOnly: true
            })
        });
    }

    function test_Perp_AmendFail_NotReduceOnly_InsufficientPosition(uint256) public {
        PlaceOrderArgs memory limitArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: _randomChance(2) ? Side.BUY : Side.SELL,
            limitPrice: 4000e18,
            amount: 1e18,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

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

        vm.expectRevert(MarketLib.NotReduceOnly.selector);
        perpManager.amendLimitOrder({
            account: rite,
            args: AmendLimitOrderArgs({
                asset: ETH,
                subaccount: 1,
                orderId: orderId,
                price: limitArgs.limitPrice,
                baseAmount: _hem(_random(), limitArgs.amount + 1, 1000e18),
                expiryTime: 0,
                side: limitArgs.side,
                reduceOnly: true
            })
        });
    }

    function test_Perp_AmendFail_NotReduceOnly_WrongSide() public {
        PlaceOrderArgs memory limitArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.SELL,
            limitPrice: 4000e18,
            amount: 1e18,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

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

        vm.expectRevert(MarketLib.NotReduceOnly.selector);
        perpManager.amendLimitOrder({
            account: rite,
            args: AmendLimitOrderArgs({
                asset: ETH,
                subaccount: 1,
                orderId: orderId,
                price: limitArgs.limitPrice,
                baseAmount: limitArgs.amount,
                expiryTime: 0,
                side: limitArgs.side == Side.BUY ? Side.SELL : Side.BUY, // Wrong side
                reduceOnly: true
            })
        });
    }

    function test_Perp_AmendFail_InsufficientBalance() public {
        PlaceOrderArgs memory limitArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.SELL,
            limitPrice: 4000e18,
            amount: 1e18,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        address maker = _randomNonZeroAddress();

        usdc.mint(maker, 4000e18);

        vm.startPrank(maker);
        usdc.approve(address(perpManager), type(uint256).max);
        perpManager.deposit(maker, 4000e18);
        uint256 orderId = perpManager.placeOrder(maker, limitArgs).orderId;

        vm.expectRevert(CollateralManagerLib.InsufficientBalance.selector);
        perpManager.amendLimitOrder({
            account: maker,
            args: AmendLimitOrderArgs({
                asset: ETH,
                subaccount: 1,
                orderId: orderId,
                price: limitArgs.limitPrice + 1e18,
                baseAmount: limitArgs.amount,
                expiryTime: 0,
                side: limitArgs.side,
                reduceOnly: false
            })
        });
    }
}
