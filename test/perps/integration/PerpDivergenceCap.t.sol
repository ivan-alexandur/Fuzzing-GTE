// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "../PerpManagerTestBase.sol";

contract PerpDivergenceCapTest is PerpManagerTestBase {
    using FixedPointMathLib for *;
    using SafeCastLib for *;

    function setUp() public override {
        super.setUp();
        vm.prank(julien);
        perpManager.deposit(julien, 100_000_000e18);
    }

    function test_Perp_DivergenceCap_Buy(uint256) public {
        uint256 mark = _hem(_random(), 0.5e18, 100_000e18);
        uint256 divergenceCap = _hem(_random(), 0.01e18, 0.8e18); // 1% to 80%
        uint256 tickSize = perpManager.getTickSize(GTE);

        uint256 cap = mark + mark.fullMulDiv(divergenceCap, 1e18);

        _setMarkAndDivergenceCap(GTE, mark, divergenceCap);

        cap -= cap % perpManager.getTickSize(GTE);

        // will fill
        _createLimitOrder({asset: GTE, maker: jb, subaccount: 1, price: cap, amount: 1e18, side: Side.SELL});

        // wont fill
        uint256 orderId = _createLimitOrder({
            asset: GTE,
            maker: rite,
            subaccount: 1,
            price: cap + tickSize,
            amount: 1e18,
            side: Side.SELL
        });

        PlaceOrderArgs memory fillArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: GTE,
            side: Side.BUY,
            limitPrice: 0,
            amount: 1e18,
            baseDenominated: true,
            tif: TiF.IOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        vm.prank(julien);
        perpManager.placeOrder(julien, fillArgs);

        assertEq(perpManager.getPosition(GTE, jb, 1).amount, 1e18, "jb position amount wrong");
        assertEq(perpManager.getPosition(GTE, julien, 1).amount, 1e18, "julien position amount wrong");
        assertEq(perpManager.getPosition(GTE, rite, 1).amount, 0, "rite position amount wrong");
        assertEq(perpManager.getLimitOrder(GTE, orderId).amount, 1e18, "rite order amount wrong");
    }

    function test_Perp_DivergenceCap_Sell(uint256) public {
        uint256 mark = _hem(_random(), 1e18, 100_000e18);
        uint256 divergenceCap = _hem(_random(), 0.01e18, 0.2e18); // 1% to 80%

        uint256 cap = mark - mark.fullMulDiv(divergenceCap, 1e18);

        _setMarkAndDivergenceCap(GTE, mark, divergenceCap);

        uint256 tickSize = perpManager.getTickSize(GTE);
        cap += tickSize;
        cap -= cap % tickSize;

        // will fill
        _createLimitOrder({asset: GTE, maker: jb, subaccount: 1, price: cap, amount: 1e18, side: Side.BUY});

        // will fill
        uint256 orderId = _createLimitOrder({
            asset: GTE,
            maker: rite,
            subaccount: 1,
            price: cap - tickSize,
            amount: 1e18,
            side: Side.BUY
        });

        PlaceOrderArgs memory fillArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: GTE,
            side: Side.SELL,
            limitPrice: 0,
            amount: 1e18,
            baseDenominated: true,
            tif: TiF.IOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        vm.prank(julien);
        perpManager.placeOrder(julien, fillArgs);

        assertEq(perpManager.getPosition(GTE, jb, 1).amount, 1e18, "jb position amount wrong");
        assertEq(perpManager.getPosition(GTE, julien, 1).amount, 1e18, "julien position amount wrong");
        assertEq(perpManager.getPosition(GTE, rite, 1).amount, 0, "rite position amount wrong");
        assertEq(perpManager.getLimitOrder(GTE, orderId).amount, 1e18, "rite order amount wrong");
    }

    function _setMarkAndDivergenceCap(bytes32 market, uint256 mark, uint256 divergenceCap) internal {
        vm.startPrank(admin);
        perpManager.setDivergenceCap(market, divergenceCap);
        perpManager.mockSetMarkPrice(market, mark);
        vm.stopPrank();
    }
}
