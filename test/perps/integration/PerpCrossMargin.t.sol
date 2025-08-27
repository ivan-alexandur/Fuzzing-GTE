// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "../PerpManagerTestBase.sol";

contract PerpCrossMarginTest is PerpManagerTestBase {
    using FixedPointMathLib for *;

    function setUp() public override {
        super.setUp();

        assertFalse(perpManager.isCrossMarginEnabled(GTE), "cross margin should be disabled for GTE");

        vm.prank(julien);
        perpManager.deposit(julien, 1_000_000e18);
    }

    // + pnl from one position can subsidize margin requirements of new position
    function test_Perp_CrossMargin_SubsidizeOpen() public {
        // open short at 100k
        _placeTrade({
            subaccount: 1,
            asset: BTC,
            taker: rite,
            maker: jb,
            price: 100_000e18,
            amount: 5e18,
            side: Side.SELL
        });

        // mark moves down
        perpManager.mockSetMarkPrice(BTC, 10_000e18);

        uint256 collateralBefore = perpManager.getFreeCollateralBalance(rite);
        int256 marginBefore = perpManager.getMarginBalance(rite, 1);
        uint256 fee = uint256(4000e18) * TAKER_BASE_FEE_RATE / 10_000_000;

        _createLimitOrder({asset: ETH, maker: nate, subaccount: 1, price: 4000e18, amount: 1e18, side: Side.SELL});

        PlaceOrderArgs memory takerArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.BUY,
            limitPrice: 4000e18,
            amount: 1e18,
            baseDenominated: true,
            tif: TiF.IOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        vm.prank(rite);
        perpManager.placeOrder(rite, takerArgs);

        assertEq(
            perpManager.getFreeCollateralBalance(rite), collateralBefore, "opening new position should have no cost"
        );

        assertEq(
            perpManager.getMarginBalance(rite, 1), marginBefore - int256(fee), "margin should only change by fee amount"
        );
    }

    function test_Perp_CrossMargin_SubsidizeLoss() public {
        vm.prank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, 2e18);

        // open at eth 4k w/ 2x leverage
        _placeTrade({subaccount: 1, asset: ETH, taker: rite, maker: jb, price: 4000e18, amount: 1e18, side: Side.BUY});

        // open at btc 100k
        _placeTrade({subaccount: 1, asset: BTC, taker: rite, maker: jb, price: 100_000e18, amount: 1e18, side: Side.BUY});

        // mark drops, leaving ETH position underwater
        perpManager.mockSetMarkPrice(ETH, 1000e18);

        // still not liquidatable due to cross margin
        assertFalse(perpManager.isLiquidatable(rite, 1), "account should not be liquidatable due to cross margin");
    }

    function test_Perp_CrossMargin_Funding() public {
        vm.warp(vm.getBlockTimestamp() + 1 hours);

        _placeTrade({asset: ETH, taker: rite, maker: jb, subaccount: 1, price: 4000e18, amount: 1e18, side: Side.BUY});

        int256 cumulativeFunding = 1e18;

        perpManager.mockSetCumulativeFunding(ETH, cumulativeFunding);

        _createLimitOrder({asset: BTC, maker: julien, subaccount: 1, price: 100_000e18, amount: 1e18, side: Side.SELL});

        PlaceOrderArgs memory fillArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: BTC,
            side: Side.BUY,
            limitPrice: 100_000e18,
            amount: 1e18,
            baseDenominated: true,
            tif: TiF.IOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        Position memory positionBefore = perpManager.getPosition(ETH, rite, 1);
        int256 marginBefore = perpManager.getMarginBalance(rite, 1);
        uint256 marginRequired = 100_000e18;
        uint256 fee = marginRequired * TAKER_BASE_FEE_RATE / 10_000_000;

        // vm.expectEmit(true, true, true, true);
        // emit ClearingHouseLib.FundingPaymentRealized({
        //     account: rite,
        //     subaccount: 1,
        //     fundingPayment: 1e18,
        //     nonce: perpManager.getNonce() + 2
        // });

        vm.prank(rite);
        perpManager.placeOrder(rite, fillArgs);

        Position memory positionAfter = perpManager.getPosition(ETH, rite, 1);

        assertEq(positionAfter.amount, positionBefore.amount, "non traded position size should be unchanged");
        assertEq(
            positionAfter.openNotional, positionBefore.openNotional, "non traded open notional should be unchanged"
        );
        assertEq(positionAfter.lastCumulativeFunding, cumulativeFunding, "last cumulative funding should be updated");

        assertEq(
            perpManager.getMarginBalance(rite, 1),
            marginBefore + int256(marginRequired) - int256(fee) - int256(1e18),
            "margin should decrease by funding payment and fee"
        );
    }

    function test_Perp_CrossMargin_Fail_CrossMarginDisabled_IncomingAsset() public {
        _placeTrade({asset: ETH, taker: rite, maker: jb, subaccount: 1, price: 4000e18, amount: 1e18, side: Side.BUY});

        PlaceOrderArgs memory fillArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: GTE,
            side: Side.BUY,
            limitPrice: 5e18,
            amount: 1e18,
            baseDenominated: true,
            tif: TiF.IOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        _createLimitOrder({asset: GTE, maker: nate, subaccount: 1, price: 5e18, amount: 1e18, side: Side.SELL});

        vm.prank(rite);
        vm.expectRevert(ClearingHouseLib.CrossMarginIsDisabled.selector);
        perpManager.placeOrder(rite, fillArgs);
    }

    function test_Perp_CrossMargin_Fail_CrossMarginDisabled_ExistingAsset() public {
        _placeTrade({asset: GTE, taker: rite, maker: jb, subaccount: 1, price: 10e18, amount: 1e18, side: Side.BUY});

        PlaceOrderArgs memory fillArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: Side.BUY,
            limitPrice: 4000e18,
            amount: 1e18,
            baseDenominated: true,
            tif: TiF.IOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        _createLimitOrder({asset: ETH, maker: nate, subaccount: 1, price: 4000e18, amount: 1e18, side: Side.SELL});

        vm.prank(rite);
        vm.expectRevert(ClearingHouseLib.CrossMarginIsDisabled.selector);
        perpManager.placeOrder(rite, fillArgs);
    }

    function test_Perp_CrossMargin_CrossMarginDisabled_MakerUnfillable() public {
        _placeTrade({asset: ETH, taker: rite, maker: nate, subaccount: 1, price: 4000e18, amount: 1e18, side: Side.BUY});

        PlaceOrderArgs memory limitArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: GTE,
            side: Side.SELL,
            limitPrice: 5e18,
            amount: 1e18,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        PlaceOrderArgs memory fillArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: GTE,
            side: Side.BUY,
            limitPrice: 5e18,
            amount: 1e18,
            baseDenominated: true,
            tif: TiF.IOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        uint256 collateral = limitArgs.amount.fullMulDiv(limitArgs.limitPrice, 1e18);

        vm.prank(rite);
        uint256 unfillableId = perpManager.placeOrder(rite, limitArgs).orderId;

        vm.prank(jb);
        perpManager.placeOrder(jb, limitArgs);

        Position memory ritePositionBefore = perpManager.getPosition(GTE, rite, 1);
        uint256 riteCollateralBefore = perpManager.getFreeCollateralBalance(rite);

        vm.expectEmit(true, true, true, true);
        emit CLOBLib.OrderCanceled({
            asset: GTE,
            orderId: unfillableId,
            owner: rite,
            subaccount: 1,
            collateralRefunded: collateral,
            bookType: BookType.STANDARD,
            nonce: perpManager.getNonce() + 1
        });

        vm.prank(julien);
        perpManager.placeOrder(julien, fillArgs);

        assertEq(perpManager.getLimitOrder(GTE, unfillableId).amount, 0, "order should be cancelled: amount");
        assertEq(perpManager.getLimitOrder(GTE, unfillableId).owner, address(0), "order should be cancelled: owner");
        assertEq(
            perpManager.getPosition(GTE, rite, 1).amount, ritePositionBefore.amount, "position should be unchanged"
        );
        assertEq(
            perpManager.getFreeCollateralBalance(rite),
            riteCollateralBefore + collateral,
            "collateral should be refunded"
        );
    }
}
