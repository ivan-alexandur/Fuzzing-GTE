// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {DynamicArrayLib} from "@solady/utils/DynamicArrayLib.sol";

import "../PerpManagerTestBase.sol";

contract Perp_Rebalance_Test is PerpManagerTestBase {
    using FixedPointMathLib for *;
    using SafeCastLib for *;
    using DynamicArrayLib for *;

    uint256 openMarkETH;
    uint256 openMarkBTC;
    Position openPositionETH;
    Position openPositionBTC;
    int256 marginDeltaBefore;
    int256 marginBefore;
    uint256 markETH;
    uint256 markBTC;
    int256 estimatedMarginDelta;
    int256 estimatedMargin;
    int256 marginDelta;
    int256 margin;

    /// forge-config: default.fuzz.runs = 2000
    function test_Rebalance_Open(uint256) public {
        markETH = _conformTick(ETH, _hem(_random(), 1e18, 500_000e18));
        markBTC = _conformTick(BTC, _hem(_random(), 1e18, 500_000e18));

        perpManager.mockSetMarkPrice(ETH, markETH);
        perpManager.mockSetMarkPrice(BTC, markBTC);

        DynamicArrayLib.DynamicArray memory assets = _generateAssets();
        Position[] memory positions = _generateRandomPositions();

        marginDeltaBefore = _hem(_random(), 1e18, 100_000e18).toInt256();
        marginBefore = _hem(_random(), 1e18, 100_000e18).toInt256();

        if (_randomChance(20)) marginBefore = -marginBefore;

        _predictRebalance();

        (margin, marginDelta) = perpManager.mockRebalance({
            assets: assets,
            positions: positions,
            margin: marginBefore,
            marginDelta: marginDeltaBefore
        });

        assertEq(margin, estimatedMargin, "margin after rebalance open incorrect");
        assertEq(marginDelta, estimatedMarginDelta, "marginDelta after rebalance open incorrect");
        assertTrue(marginDelta >= 0, "marginDelta negative after rebalance open");
        assertTrue(marginDelta <= marginDeltaBefore, "marginDelta exceeds estimate on rebalance open");
        assertEq(margin, marginBefore + marginDelta, "margin after delta incorrect");
    }

    /// forge-config: default.fuzz.runs = 2000
    function test_Rebalance_Decrease(uint256) public {
        markETH = _conformTick(ETH, _hem(_random(), 1e18, 500_000e18));
        markBTC = _conformTick(BTC, _hem(_random(), 1e18, 500_000e18));

        perpManager.mockSetMarkPrice(ETH, markETH);
        perpManager.mockSetMarkPrice(BTC, markBTC);

        DynamicArrayLib.DynamicArray memory assets = _generateAssets();
        Position[] memory positions = _generateRandomPositions();

        marginDeltaBefore = -_hem(_random(), 1e18, 100_000e18).toInt256();
        marginBefore = _hem(_random(), 1e18, 100_000e18).toInt256();

        if (_randomChance(20)) marginBefore = -marginBefore;

        _predictRebalance();

        (margin, marginDelta) = perpManager.mockRebalance({
            assets: assets,
            positions: positions,
            margin: marginBefore,
            marginDelta: marginDeltaBefore
        });

        assertEq(margin, estimatedMargin, "margin after rebalance decrease incorrect");
        assertEq(marginDelta, estimatedMarginDelta, "marginDelta after rebalance decrease incorrect");
        assertTrue(marginDelta <= 0, "marginDelta positive after rebalance decrease");
        assertTrue(marginDelta.abs() <= marginDeltaBefore.abs(), "marginDelta exceeds estimate on rebalance decrease");
        assertEq(margin, marginBefore + marginDelta, "margin after delta incorrect");
    }

    function test_Rebalance_Close(uint256) public {
        markETH = _conformTick(ETH, _hem(_random(), 1e18, 500_000e18));
        markBTC = _conformTick(BTC, _hem(_random(), 1e18, 500_000e18));

        perpManager.mockSetMarkPrice(ETH, markETH);
        perpManager.mockSetMarkPrice(BTC, markBTC);

        DynamicArrayLib.DynamicArray memory assets = _generateAssets();

        // empty positions, note: in reality array would be 1 and not 2 length, but this suffices for test
        Position[] memory positions = new Position[](2);

        marginDeltaBefore = -_hem(_random(), 1e18, 100_000e18).toInt256();
        marginBefore = _hem(_random(), 1e18, 100_000e18).toInt256();

        if (_randomChance(5)) marginBefore = -marginBefore;

        _predictRebalance();

        (margin, marginDelta) = perpManager.mockRebalance({
            assets: assets,
            positions: positions,
            margin: marginBefore,
            marginDelta: marginDeltaBefore
        });

        assertEq(margin, estimatedMargin, "margin after rebalance close incorrect");
        assertEq(marginDelta, estimatedMarginDelta, "marginDelta after rebalance close incorrect");
        assertTrue(marginDelta <= 0, "marginDelta positive after rebalance close");

        if (marginBefore > 0) {
            assertEq(margin, 0, "margin not zero after close above water");
            assertEq(marginDelta, -marginBefore, "margin returned isn't equal to margin after close above water");
        } else {
            assertEq(margin, marginBefore, "margin isn't static after close below water");
            assertEq(marginDelta, 0, "margin returned isn't zero after close below water");
        }
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _predictRebalance() internal {
        // account close
        if (openPositionETH.amount == 0 && openPositionBTC.amount == 0) return _predictRebalanceClose();

        uint256 currentNotionalETH = openPositionETH.amount.fullMulDiv(markETH, 1e18);
        uint256 currentNotionalBTC = openPositionBTC.amount.fullMulDiv(markBTC, 1e18);

        int256 upnlETH = _calcUpnl({
            currentNotional: currentNotionalETH,
            openNotional: openPositionETH.openNotional,
            isLong: openPositionETH.isLong
        });
        int256 upnlBTC = _calcUpnl({
            currentNotional: currentNotionalBTC,
            openNotional: openPositionBTC.openNotional,
            isLong: openPositionBTC.isLong
        });

        uint256 intendedMarginETH = currentNotionalETH.fullMulDiv(1e18, openPositionETH.leverage);
        uint256 intendedMarginBTC = currentNotionalBTC.fullMulDiv(1e18, openPositionBTC.leverage);

        if (marginDeltaBefore >= 0) {
            _predictRebalanceIncrease({intendedMargin: intendedMarginETH + intendedMarginBTC, upnl: upnlETH + upnlBTC});
        } else {
            _predictRebalanceDecrease({intendedMargin: intendedMarginETH + intendedMarginBTC, upnl: upnlETH + upnlBTC});
        }
    }

    function _predictRebalanceIncrease(uint256 intendedMargin, int256 upnl) internal {
        int256 equity = marginBefore + upnl + marginDeltaBefore;

        if (equity > intendedMargin.toInt256()) {
            equity -= marginDeltaBefore;

            if (equity < intendedMargin.toInt256()) estimatedMarginDelta = intendedMargin.toInt256() - equity;
            else estimatedMarginDelta = 0;
        } else {
            estimatedMarginDelta = marginDeltaBefore;
        }

        estimatedMargin = marginBefore + estimatedMarginDelta;
    }

    function _predictRebalanceDecrease(uint256 intendedMargin, int256 upnl) internal {
        int256 equity = marginBefore + upnl + marginDeltaBefore;

        if (equity < intendedMargin.toInt256()) {
            equity -= marginDeltaBefore;

            if (equity > intendedMargin.toInt256()) estimatedMarginDelta = intendedMargin.toInt256() - equity;
            else estimatedMarginDelta = 0;
        } else {
            estimatedMarginDelta = marginDeltaBefore;
        }

        estimatedMargin = marginBefore + estimatedMarginDelta;
    }

    function _predictRebalanceClose() internal {
        if (marginBefore < 0) estimatedMargin = marginBefore;
        else estimatedMarginDelta = -marginBefore;
    }

    function _generateRandomPositions() internal returns (Position[] memory positions) {
        openMarkETH = _hem(_random(), 1e18, 500_000e18);
        openMarkBTC = _hem(_random(), 1e18, 500_000e18);

        openPositionETH.amount = _conformLots(ETH, _hem(_random(), 1e18, 1000e18));
        openPositionETH.openNotional = openPositionETH.amount.fullMulDiv(openMarkETH, 1e18);
        openPositionETH.leverage = _hem(_random(), 1e18, 50e18);
        openPositionETH.isLong = _randomChance(2);

        openPositionBTC.amount = _conformLots(BTC, _hem(_random(), 1e18, 1000e18));
        openPositionBTC.openNotional = openPositionBTC.amount.fullMulDiv(openMarkBTC, 1e18);
        openPositionBTC.leverage = _hem(_random(), 1e18, 50e18);
        openPositionBTC.isLong = _randomChance(2);

        positions = new Position[](2);
        positions[0] = openPositionETH;
        positions[1] = openPositionBTC;
    }

    function _generateAssets() internal pure returns (DynamicArrayLib.DynamicArray memory assets) {
        bytes32[] memory assetArray = new bytes32[](2);
        assetArray[0] = ETH;
        assetArray[1] = BTC;

        assets = assetArray.wrap();
    }

    function _calcUpnl(uint256 currentNotional, uint256 openNotional, bool isLong)
        internal
        pure
        returns (int256 upnl)
    {
        if (isLong) return int256(currentNotional) - int256(openNotional);
        else return int256(openNotional) - int256(currentNotional);
    }
}
