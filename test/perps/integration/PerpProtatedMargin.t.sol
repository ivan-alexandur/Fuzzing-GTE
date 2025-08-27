// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "../PerpManagerTestBase.sol";

import {DynamicArrayLib} from "@solady/utils/DynamicArrayLib.sol";

contract Perp_ProratedMargin_Test is PerpManagerTestBase {
    using FixedPointMathLib for *;
    using SafeCastLib for *;
    using DynamicArrayLib for *;

    Position openPositionETH;
    Position openPositionBTC;
    Position[] positions;
    DynamicArrayLib.DynamicArray assets;
    int256 margin;
    uint256 markETH;
    uint256 markBTC;
    int256 estimatedProratedMargin;

    /// forge-config: default.fuzz.runs = 2000
    function test_Perp_ProratedMargin(uint256) external {
        markETH = _conformTick(ETH, _hem(_random(), 1e18, 500_000e18));
        markBTC = _conformTick(BTC, _hem(_random(), 1e18, 500_000e18));

        margin = _hem(_random(), 1e18, 100_000e18).toInt256();
        if (_randomChance(20)) margin = -margin;

        bytes32 asset = _randomChance(2) ? ETH : BTC;

        _generateAssets();
        _generateRandomPositions();
        _estimateProratedMargin(asset);

        perpManager.mockSetMarkPrice(ETH, markETH);
        perpManager.mockSetMarkPrice(BTC, markBTC);

        int256 proratedMargin =
            perpManager.mockGetProratedMargin({assets: assets, positions: positions, asset: asset, margin: margin});

        assertEq(proratedMargin, estimatedProratedMargin, "prorated margin incorrect");
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _estimateProratedMargin(bytes32 asset) internal {
        uint256 ethNotional = openPositionETH.amount.fullMulDiv(markETH, 1e18);
        uint256 btcNotional = openPositionBTC.amount.fullMulDiv(markBTC, 1e18);

        uint256 totalNotional = ethNotional + btcNotional;

        if (asset == ETH) estimatedProratedMargin = margin.abs().fullMulDiv(ethNotional, totalNotional).toInt256();
        else if (asset == BTC) estimatedProratedMargin = margin.abs().fullMulDiv(btcNotional, totalNotional).toInt256();

        if (margin < 0) estimatedProratedMargin = -estimatedProratedMargin;
    }

    function _generateRandomPositions() internal {
        uint256 openMarkETH = _hem(_random(), 1e18, 500_000e18);
        uint256 openMarkBTC = _hem(_random(), 1e18, 500_000e18);

        openPositionETH.amount = _conformLots(ETH, _hem(_random(), 1e18, 1000e18));
        openPositionETH.openNotional = openPositionETH.amount.fullMulDiv(openMarkETH, 1e18);
        openPositionETH.leverage = _hem(_random(), 1e18, 50e18);
        openPositionETH.isLong = _randomChance(2);

        openPositionBTC.amount = _conformLots(BTC, _hem(_random(), 1e18, 1000e18));
        openPositionBTC.openNotional = openPositionBTC.amount.fullMulDiv(openMarkBTC, 1e18);
        openPositionBTC.leverage = _hem(_random(), 1e18, 50e18);
        openPositionBTC.isLong = _randomChance(2);

        positions.push(openPositionETH);
        positions.push(openPositionBTC);
    }

    function _generateAssets() internal {
        bytes32[] memory assetArray = new bytes32[](2);
        assetArray[0] = ETH;
        assetArray[1] = BTC;

        assets = assetArray.wrap();
    }
}
