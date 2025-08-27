// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "../PerpManagerTestBase.sol";

// // @todo add backstop book
// // @todo add fill on post

contract PerpPostLimitOrderTest is PerpManagerTestBase {
    using FixedPointMathLib for *;
    using SafeCastLib for uint256;

    struct State {
        Position position;
        uint256 quoteOI;
        uint256 baseOI;
        uint256 assetBalance;
        uint256 perpManagerBalance;
        uint256 collateralBalance;
    }

    struct LimitOrderParams {
        Side side;
        uint256 price;
        uint256 amount;
        uint256 leverage;
        uint96 clientOrderId;
        bool reduceOnly;
    }

    State state;
    LimitOrderParams params;

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                        LIMIT ORDER POST SUCCESS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_Perp_Limit_NotReduceOnly(uint256) public {
        params.side = _randomChance(2) ? Side.BUY : Side.SELL;
        params.price = _conformToTick(_hem(_random(), 1e18, 100_000e18));
        params.leverage = _hem(_random(), 1e18, 50e18);
        params.amount = _conformToLots(_hem(_random(), 1e18, 100e18));

        _limitOrderPostHelper(false);

        uint256[] memory reduceOnlyOrders = perpManager.getReduceOnlyOrders(ETH, rite, 1);

        assertEq(reduceOnlyOrders.length, 0, "reduce only orders: should be empty");
    }

    function test_Perp_Limit_ReduceOnly(uint256) public {
        uint256 positionSize = _conformToLots(_hem(_random(), 1e18, 100e18));

        params.side = _randomChance(2) ? Side.BUY : Side.SELL;
        params.price = perpManager.getMarkPrice(ETH);
        params.leverage = 1e18;
        params.amount = _conformToLots(_hem(_random(), 0.1e18, positionSize));
        params.reduceOnly = true;

        _placeTrade({
            subaccount: 1,
            asset: ETH,
            taker: rite,
            maker: jb,
            price: params.price,
            amount: positionSize,
            side: params.side == Side.BUY ? Side.SELL : Side.BUY
        });

        _limitOrderPostHelper(true);

        uint256[] memory reduceOnlyOrders = perpManager.getReduceOnlyOrders(ETH, rite, 1);

        assertEq(reduceOnlyOrders.length, 1, "reduce only orders: should not be empty");
    }

    function test_Perp_Limit_CustomClientOrderId(uint256) public {
        address maker = _randomNonZeroAddress();

        vm.assume(maker.code.length == 0); // ensure it's not a contract

        usdc.mint(maker, 100_000e18);

        params.side = _randomChance(2) ? Side.BUY : Side.SELL;
        params.price = perpManager.getMarkPrice(ETH);
        params.leverage = 1e18;
        params.amount = 1e18;
        params.reduceOnly = false;
        params.clientOrderId = uint96(_hem(_random(), 1, type(uint96).max));

        uint256 expectedOrderId = uint256(bytes32(abi.encodePacked(maker, params.clientOrderId)));

        PlaceOrderArgs memory makerArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: params.side,
            limitPrice: params.price,
            amount: params.amount,
            baseDenominated: true, // @todo test quote denominated
            tif: TiF.MOC,
            expiryTime: 0, // no expiry
            clientOrderId: params.clientOrderId,
            reduceOnly: false
        });

        vm.startPrank(maker);
        usdc.approve(address(perpManager), 100_000e18);
        perpManager.deposit(maker, 100_000e18);

        // _expectEvents(maker, expectedOrderId);

        uint256 orderId = perpManager.placeOrder(maker, makerArgs).orderId;

        assertEq(orderId, expectedOrderId, "order id != expected");
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _limitOrderPostHelper(bool tradePlaced) internal {
        vm.startPrank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, params.leverage);

        PlaceOrderArgs memory args = PlaceOrderArgs({
            subaccount: 1,
            asset: ETH,
            side: params.side,
            limitPrice: params.price,
            amount: params.amount,
            baseDenominated: true, // @todo test quote denominated
            tif: tradePlaced ? TiF.MOC : TiF.GTC,
            expiryTime: 0, // no expiry
            clientOrderId: params.clientOrderId,
            reduceOnly: params.reduceOnly
        });

        _cachePreLimitOrderState();
        // using default orderId means that if `_placeTrade` is called, expected orderId is 3
        // _expectEvents(rite, tradePlaced ? 3 : 1);

        uint256 id = perpManager.placeOrder(rite, args).orderId;

        _assertPostLimitOrderState(id);
    }

    function _cachePreLimitOrderState() internal {
        (state.baseOI, state.quoteOI) = perpManager.getOpenInterestBook(ETH);
        state.position = perpManager.getPosition(ETH, rite, 1);
        state.assetBalance = usdc.balanceOf(rite);
        state.collateralBalance = perpManager.getFreeCollateralBalance(rite);
        state.perpManagerBalance = usdc.balanceOf(address(perpManager));
    }

    // function _expectEvents(address maker, uint256 orderId) internal {
    // vm.expectEmit(true, true, true, true, address(perpManager));

    // emit CLOBLib.LimitOrderSubmitted({
    //     asset: ETH,
    //     owner: maker,
    //     orderId: orderId,
    //     args: PostLimitOrderArgs({
    //         asset: ETH,
    //         amountInBase: params.amount,
    //         price: params.price,
    //         cancelTimestamp: 0,
    //         side: params.side,
    //         limitOrderType: LimitOrderType.POST_ONLY,
    //         clientOrderId: params.clientOrderId,
    //         subaccount: 1,
    //         reduceOnly: params.reduceOnly
    //     }),
    //     bookType: BookType.STANDARD,
    //     nonce: perpManager.getNonce() + 1
    // });

    // vm.expectEmit(true, true, true, true, address(perpManager));
    // emit CLOBLib.LimitOrderProcessed({
    //     asset: ETH,
    //     account: maker,
    //     orderId: orderId,
    //     amountPostedInBase: params.amount,
    //     quoteTokenAmountTraded: 0,
    //     baseTokenAmountTraded: 0,
    //     leverage: params.leverage,
    //     bookType: BookType.STANDARD,
    //     nonce: perpManager.getNonce() + 2
    // });
    // }

    function _assertPostLimitOrderState(uint256 id) internal view {
        uint256 quoteValue = params.amount.fullMulDiv(params.price, 1e18);
        uint256 collateralOwed = params.reduceOnly ? 0 : quoteValue.fullMulDiv(1e18, params.leverage);
        (uint256 baseOI, uint256 quoteOI) = perpManager.getOpenInterestBook(ETH);
        Order memory order = perpManager.getLimitOrder(ETH, id);

        // position
        assertEq(
            perpManager.getPosition(ETH, rite, 1).amount, state.position.amount, "position amount: should not be filled"
        );
        assertEq(
            perpManager.getPosition(ETH, rite, 1).lastCumulativeFunding,
            state.position.lastCumulativeFunding,
            "position lcf: funding payment should not be settled"
        );

        // order
        assertEq(order.amount, params.amount, "order amount: is wrong");
        assertEq(order.price, params.price, "order price: is wrong");
        assertEq(uint8(order.side), uint8(params.side), "order side: is wrong");
        assertEq(order.subaccount, 1, "order subaccount: is wrong");
        assertEq(order.reduceOnly, params.reduceOnly, "order reduceOnly: is wrong");

        // collateral
        assertEq(
            perpManager.getFreeCollateralBalance(rite),
            state.collateralBalance - collateralOwed,
            "collateral: should be decreased"
        );
        assertEq(usdc.balanceOf(rite), state.assetBalance, "asset balance: should not be changed");
        assertEq(
            usdc.balanceOf(address(perpManager)), state.perpManagerBalance, "perp manager balance: should not change"
        );

        // protocol
        if (params.side == Side.BUY) {
            assertEq(
                quoteOI, state.quoteOI + params.amount.fullMulDiv(params.price, 1e18), "quoteOI: should be increased"
            );
            assertEq(baseOI, state.baseOI, "baseOI: should not be changed");
        } else {
            assertEq(baseOI, state.baseOI + params.amount, "baseOI: should be increased");
            assertEq(quoteOI, state.quoteOI, "quoteOI: should not be changed");
        }
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
