// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "../PerpManagerTestBase.sol";
import {DynamicArrayLib} from "@solady/utils/DynamicArrayLib.sol";

contract PerpMiscGettersTest is PerpManagerTestBase {
    using FixedPointMathLib for *;
    using SafeCastLib for *;
    using DynamicArrayLib for *;

    uint256 markETH;
    uint256 markBTC;
    Position openPositionETH;
    Position openPositionBTC;
    Position[] positions;
    DynamicArrayLib.DynamicArray assets;

    function test_Perp_MidPrice_BothInitialized(uint256) public {
        uint256 price1 = _conformTick(ETH, _hem(_random(), 1e18, 1_000_000_000e18));
        uint256 price2 = _conformTick(ETH, _hem(_random(), 1e18, 1_000_000_000e18));

        (uint256 bestBid, uint256 bestAsk) = price1 < price2 ? (price1, price2) : (price2, price1);

        if (bestBid == bestAsk) bestAsk += perpManager.getTickSize(ETH);

        _createLimitOrder({asset: ETH, maker: jb, subaccount: 1, price: bestBid, amount: 1e18, side: Side.BUY});

        _createLimitOrder({asset: ETH, maker: rite, subaccount: 1, price: bestAsk, amount: 1e18, side: Side.SELL});

        uint256 mid = (bestBid + bestAsk) / 2;

        assertEq(perpManager.getMidPrice(ETH), mid, "mid price wrong");
    }

    function test_Perp_MidPrice_OneInitialized(uint256) public {
        uint256 price = _conformTick(ETH, _hem(_random(), 1e18, 1_000_000_000e18));
        Side side = _randomChance(2) ? Side.BUY : Side.SELL;

        _createLimitOrder({asset: ETH, maker: jb, subaccount: 1, price: price, amount: 1e18, side: side});

        perpManager.getMidPrice(ETH);

        assertEq(perpManager.getMidPrice(ETH), 0, "mid price wrong");
    }

    /// @notice payment = size * |size| * deltaFunding
    function _getFundingPayment(int256 size, int256 deltaFunding) internal pure returns (int256) {
        int256 amount = _mul(size, int256(size.abs()));

        return _mul(amount, deltaFunding);
    }

    /// @dev wrapper for fullMulDiv to handle int256
    function _mul(int256 a, int256 b) private pure returns (int256) {
        uint256 result = a.abs().fullMulDiv(b.abs(), 1e18);

        return a < 0 == b < 0 ? result.toInt256() : -result.toInt256();
    }

    function test_CH_GetUPNL_By_Assets_Positions(uint256) public {
        markETH = _conformTick(ETH, _hem(_random(), 1e18, 500_000e18));
        markBTC = _conformTick(BTC, _hem(_random(), 1e18, 500_000e18));
        perpManager.mockSetMarkPrice(ETH, markETH);
        perpManager.mockSetMarkPrice(BTC, markBTC);

        assets = _generateAssets();
        positions.push(_generateRandomPosition(ETH));
        positions.push(_generateRandomPosition(BTC));

        int256 upnl = perpManager.harness_CH_GetUpnl_AssetsPositions(assets, positions);

        openPositionETH = positions[0];
        openPositionBTC = positions[1];

        int256 expectedUpnl = 0;

        uint256 currEthNotional = openPositionETH.amount.fullMulDiv(markETH, 1e18);
        uint256 currBtcNotional = openPositionBTC.amount.fullMulDiv(markBTC, 1e18);

        console.log("HERE", openPositionETH.openNotional, currEthNotional);
        expectedUpnl += _calculateUpnl(openPositionETH.isLong, openPositionETH.openNotional, currEthNotional);
        expectedUpnl += _calculateUpnl(openPositionBTC.isLong, openPositionBTC.openNotional, currBtcNotional);

        assertEq(expectedUpnl, upnl, "expected upnl != actual");
    }

    function test_CH_GetNotionalAccountValue(uint256) public {
        markETH = _conformTick(ETH, _hem(_random(), 1e18, 500_000e18));
        markBTC = _conformTick(BTC, _hem(_random(), 1e18, 500_000e18));
        perpManager.mockSetMarkPrice(ETH, markETH);
        perpManager.mockSetMarkPrice(BTC, markBTC);

        assets = _generateAssets();
        positions.push(_generateRandomPosition(ETH));
        positions.push(_generateRandomPosition(BTC));

        uint256 totalNotional = perpManager.harness_CH_GetNotionalAccountValue(assets, positions);

        uint256 currEthNotional = positions[0].amount.fullMulDiv(markETH, 1e18);
        uint256 currBtcNotional = positions[1].amount.fullMulDiv(markBTC, 1e18);

        assertEq(currEthNotional + currBtcNotional, totalNotional, "Expected notional != actual");
    }

    function test_VP_getNumBids(uint256) public {
        vm.startPrank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, _hem(_random(), 1e18, 50e18));

        _createLimitOrder({
            asset: ETH,
            maker: rite,
            subaccount: 1,
            price: _conformTickEth(_hem(_random(), 1e18, 200_000e18)),
            amount: _conformLotsEth(_hem(_random(), 0.01e18, 50e18)),
            side: Side.BUY
        });

        _createLimitOrder({
            asset: ETH,
            maker: rite,
            subaccount: 1,
            price: _conformTickEth(_hem(_random(), 1e18, 200_000e18)),
            amount: _conformLotsEth(_hem(_random(), 0.01e18, 50e18)),
            side: Side.BUY
        });

        // There are 2 bid orders which are pending updates to rite's position on the book
        assertEq(perpManager.getNumBids(ETH), 2);
        assertEq(perpManager.getNumAsks(ETH), 0);
    }

    function test_VP_getNumAsks(uint256) public {
        vm.startPrank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, _hem(_random(), 1e18, 50e18));

        _createLimitOrder({
            asset: ETH,
            maker: rite,
            subaccount: 1,
            price: _conformTickEth(_hem(_random(), 1e18, 200_000e18)),
            amount: _conformLotsEth(_hem(_random(), 0.01e18, 50e18)),
            side: Side.SELL
        });

        _createLimitOrder({
            asset: ETH,
            maker: rite,
            subaccount: 1,
            price: _conformTickEth(_hem(_random(), 1e18, 200_000e18)),
            amount: _conformLotsEth(_hem(_random(), 0.01e18, 50e18)),
            side: Side.SELL
        });

        // There are 2 ask orders which are pending updates to rite's position on the book
        assertEq(perpManager.getNumAsks(ETH), 2);
        assertEq(perpManager.getNumBids(ETH), 0);
    }

    function test_VP_getLastFundingTime(uint256) external {
        uint256 variableSeconds = _hem(_random(), 1, 1000);
        uint256 newTimestamp = vm.getBlockTimestamp() + perpManager.getFundingInterval(ETH) + variableSeconds;

        vm.startPrank(admin);
        uint256 newPrice = _hem(_random(), 1e18, 5000e18);
        perpManager.setMarkPrice(ETH, newPrice);

        vm.warp(newTimestamp);
        perpManager.settleFunding(ETH);

        assertEq(perpManager.getLastFundingTime(ETH), newTimestamp);
    }

    /// @dev This tests that getAccountValue properly adds margin and upnl to a subaccount's positions
    /// It does not include subtracting the unrealized funding payment
    function test_VP_getAccountValue(uint256) public {
        markETH = _conformTick(ETH, _hem(_random(), 1e18, 500_000e18));
        markBTC = _conformTick(BTC, _hem(_random(), 1e18, 500_000e18));
        perpManager.mockSetMarkPrice(ETH, markETH);
        perpManager.mockSetMarkPrice(BTC, markBTC);

        Position memory ePos = _generateRandomPosition(ETH);
        Position memory bPos = _generateRandomPosition(BTC);

        perpManager.mockSetPosition(rite, 1, ETH, ePos);
        perpManager.mockSetPosition(rite, 1, BTC, bPos);

        uint256 currEthNotional = ePos.amount.fullMulDiv(markETH, 1e18);
        uint256 currBtcNotional = bPos.amount.fullMulDiv(markBTC, 1e18);

        // i dont think this will happen, but its here just in case a fuzz causes an overflow
        if (ePos.openNotional + bPos.openNotional > uint256(type(int256).max)) revert("CASTING ISSUE");

        int256 margin = int256((ePos.openNotional + bPos.openNotional) / 10);
        perpManager.mockSetMargin(rite, 1, margin);

        int256 expectedUpnl = _calculateUpnl(ePos.isLong, ePos.openNotional, currEthNotional);
        expectedUpnl += _calculateUpnl(bPos.isLong, bPos.openNotional, currBtcNotional);

        // No funding included because the funding payment in the call is 0
        int256 expectedAccountValue = margin + expectedUpnl;

        assertEq(
            expectedAccountValue, perpManager.getAccountValue(rite, 1), "expected account value != actual account value"
        );
    }

    struct OrderBookTestData {
        uint256 leverage;
        uint256 order1Price;
        uint256 order1BookNotional;
        // PostLimitOrderArgs order1Args;
        uint256 order2BookNotional;
    }
    // PostLimitOrderArgs order2Args;

    function test_VP_getOrderbookCollateral(uint256) public {
        OrderBookTestData memory ethData;
        OrderBookTestData memory btcData;

        // ETH market setup
        vm.prank(rite);
        ethData.leverage = _hem(_random(), 1e18, 50e18);
        perpManager.setPositionLeverage(ETH, rite, 1, ethData.leverage);

        ethData.order1Price = _conformTickEth(_hem(_random(), 1e18, 200_000e18));
        uint256 ethOrder1AmountInBase = _conformLotsEth(_hem(_random(), 0.01e18, 50e18));

        _createLimitOrder({
            asset: ETH,
            maker: rite,
            subaccount: 1,
            price: ethData.order1Price,
            amount: ethOrder1AmountInBase,
            side: Side.SELL
        });

        ethData.order1BookNotional = (ethOrder1AmountInBase * ethData.order1Price) / 1 ether;

        uint256 ethOrder2Price = _conformTickEth(_hem(_random(), 1e18, 200_000e18));
        // Orders dont cross
        vm.assume(ethOrder2Price < ethData.order1Price);

        uint256 ethOrder2AmountInBase = _conformLotsEth(_hem(_random(), 0.01e18, 50e18));

        _createLimitOrder({
            asset: ETH,
            maker: rite,
            subaccount: 1,
            price: ethOrder2Price,
            amount: ethOrder2AmountInBase,
            side: Side.BUY
        });

        ethData.order2BookNotional = (ethOrder2AmountInBase * ethOrder2Price) / 1 ether;

        // BTC market setup
        btcData.leverage = _hem(_random(), 1e18, 50e18);

        vm.prank(rite);
        perpManager.setPositionLeverage(BTC, rite, 1, btcData.leverage);

        btcData.order1Price = _conformTick(BTC, _hem(_random(), 1e18, 200_000e18));
        uint256 btcOrder1AmountInBase = _conformLots(BTC, _hem(_random(), 0.01e18, 50e18));

        _createLimitOrder({
            asset: BTC,
            maker: rite,
            subaccount: 1,
            price: btcData.order1Price,
            amount: btcOrder1AmountInBase,
            side: Side.BUY
        });

        btcData.order1BookNotional = (btcOrder1AmountInBase * btcData.order1Price) / 1 ether;

        uint256 btcOrder2Price = _conformTick(BTC, _hem(_random(), 1e18, 200_000e18));
        // Orders dont cross
        vm.assume(btcOrder2Price < btcData.order1Price);

        uint256 btcOrder2AmountInBase = _conformLots(BTC, _hem(_random(), 0.01e18, 50e18));

        _createLimitOrder({
            asset: BTC,
            maker: rite,
            subaccount: 1,
            price: btcOrder2Price,
            amount: btcOrder2AmountInBase,
            side: Side.BUY
        });

        btcData.order2BookNotional = (btcOrder2AmountInBase * btcOrder2Price) / 1 ether;

        // Add assets to account so getOrderbookCollateral can find them
        perpManager.mockAddAsset(rite, 1, ETH);
        perpManager.mockAddAsset(rite, 1, BTC);

        uint256 ethOrderbookCollateral =
            (ethData.order1BookNotional + ethData.order2BookNotional).fullMulDiv(1e18, ethData.leverage);
        uint256 btcOrderbookCollateral =
            (btcData.order1BookNotional + btcData.order2BookNotional).fullMulDiv(1e18, btcData.leverage);

        uint256 collateral = perpManager.getOrderbookCollateral(rite, 1);

        assertEq(ethOrderbookCollateral + btcOrderbookCollateral, collateral, "expected orderbook collateral != actual");
    }

    function _generateAssets() internal pure returns (DynamicArrayLib.DynamicArray memory) {
        bytes32[] memory assetArray = new bytes32[](2);
        assetArray[0] = ETH;
        assetArray[1] = BTC;

        return assetArray.wrap();
    }

    function _calculateUpnl(bool long, uint256 openNotional, uint256 currentNotional) internal pure returns (int256) {
        (int256 start, int256 end) = (openNotional.toInt256(), currentNotional.toInt256());

        if (!long) (start, end) = (end, start);
        return end - start;
    }
}
