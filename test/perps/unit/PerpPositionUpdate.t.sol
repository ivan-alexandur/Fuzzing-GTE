// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import {TestPlus} from "lib/solady/test/utils/TestPlus.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";

import {Position, PositionUpdateResult, Side, OIDelta} from "contracts/perps/types/Position.sol";

contract Perp_PositionUpdate_Test is Test, TestPlus {
    using FixedPointMathLib for uint256;
    using SafeCastLib for *;

    struct PositionUpdateParams {
        Position position;
        Side side;
        uint256 quoteAmount;
        uint256 baseAmount;
    }

    struct ExpectedPositionUpdateResult {
        Position position;
        PositionUpdateResult result;
    }

    struct ActualResult {
        Position position;
        PositionUpdateResult result;
    }

    PositionUpdateParams params;
    ExpectedPositionUpdateResult expected;
    ActualResult actual;

    function test_Perp_Position_Open(uint256) public {
        params.position.lastCumulativeFunding = _getRandomCumulativeFunding();
        params.position.leverage = _hem(_random(), 1e18, 100e18);

        params.side = _randomChance(2) ? Side.BUY : Side.SELL;
        params.quoteAmount = _hem(_randomUnique(), 1e15, 1_000_000e18);
        params.baseAmount = _hem(_randomUnique(), 1e15, 10_000e18);

        _predictOpen();

        Position memory position = params.position;

        actual.result =
            position.processTrade({side: params.side, quoteTraded: params.quoteAmount, baseTraded: params.baseAmount});
        actual.position = position;

        _assertPositionUpdate();
    }

    function test_Perp_Position_Increase(uint256) public {
        params.position.amount = _hem(_randomUnique(), 1e15, 10_000e18);
        params.position.openNotional = _hem(_randomUnique(), 1e15, 1_000_000e18);
        params.position.isLong = _randomChance(2);
        params.position.leverage = _hem(_random(), 1e18, 100e18);
        params.position.lastCumulativeFunding = _getRandomCumulativeFunding();

        params.side = params.position.isLong ? Side.BUY : Side.SELL;
        params.quoteAmount = _hem(_randomUnique(), 1e15, 1_000_000e18);
        params.baseAmount = _hem(_randomUnique(), 1e15, 10_000e18);

        _predictOpen();

        Position memory position = params.position;

        actual.result =
            position.processTrade({side: params.side, quoteTraded: params.quoteAmount, baseTraded: params.baseAmount});
        actual.position = position;

        _assertPositionUpdate();
    }

    function test_Perp_Position_Decrease(uint256) public {
        params.position.amount = _hem(_randomUnique(), 1e15, 10_000e18);
        params.position.openNotional = _hem(_randomUnique(), 1e15, 1_000_000e18);
        params.position.isLong = _randomChance(2);
        params.position.leverage = _hem(_random(), 1e18, 100e18);
        params.position.lastCumulativeFunding = _getRandomCumulativeFunding();

        params.side = params.position.isLong ? Side.SELL : Side.BUY;
        params.quoteAmount = _hem(_randomUnique(), 1e15, 1_000_000e18);
        params.baseAmount = _hem(_randomUnique(), 1e14, params.position.amount - 100); // ensure we don't close completely

        _predictDecrease();

        Position memory position = params.position;

        actual.result =
            position.processTrade({side: params.side, quoteTraded: params.quoteAmount, baseTraded: params.baseAmount});
        actual.position = position;

        _assertPositionUpdate();
    }

    function test_Perp_Position_Close(uint256) public {
        params.position.amount = _hem(_randomUnique(), 1e15, 10_000e18);
        params.position.openNotional = _hem(_randomUnique(), 1e15, 1_000_000e18);
        params.position.isLong = _randomChance(2);
        params.position.leverage = _hem(_random(), 1e18, 100e18);
        params.position.lastCumulativeFunding = _getRandomCumulativeFunding();

        params.side = params.position.isLong ? Side.SELL : Side.BUY;
        params.quoteAmount = _hem(_randomUnique(), 1e15, 1_000_000e18);
        params.baseAmount = params.position.amount; // close full position

        Position memory position = params.position;

        _predictClose();

        actual.result =
            position.processTrade({side: params.side, quoteTraded: params.quoteAmount, baseTraded: params.baseAmount});
        actual.position = position;

        _assertPositionUpdate();
    }

    function test_Perp_Position_ReverseOpen(uint256) public {
        params.position.amount = _hem(_randomUnique(), 1e15, 10_000e18);
        params.position.openNotional = _hem(_randomUnique(), 1e15, 1_000_000e18);
        params.position.isLong = _randomChance(2);
        params.position.leverage = _hem(_random(), 1e18, 100e18);
        params.position.lastCumulativeFunding = _getRandomCumulativeFunding();

        params.side = params.position.isLong ? Side.SELL : Side.BUY;
        params.quoteAmount = _hem(_randomUnique(), 1e15, 1_000_000e18);
        params.baseAmount = _hem(_randomUnique(), params.position.amount + 10_000, params.position.amount * 2); // ensure we flip position

        // traded amounts used to close
        uint256 closeBaseAmount = params.position.amount;
        uint256 openBaseAmount = params.baseAmount - closeBaseAmount;

        // traded amounts used to open
        uint256 closedNotional = params.quoteAmount.fullMulDiv(closeBaseAmount, params.baseAmount);
        uint256 openedNotional = params.quoteAmount - closedNotional;

        Position memory position = params.position;

        // bound traded to close
        params.quoteAmount = closedNotional;
        params.baseAmount = closeBaseAmount;

        _predictClose();

        // set traded to open
        params.quoteAmount = openedNotional;
        params.baseAmount = openBaseAmount;

        _predictOpen();

        // reset traded
        params.quoteAmount = closedNotional + openedNotional;
        params.baseAmount = closeBaseAmount + openBaseAmount;

        actual.result =
            position.processTrade({side: params.side, quoteTraded: params.quoteAmount, baseTraded: params.baseAmount});
        actual.position = position;

        _assertPositionUpdate();
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                              ASSERTION
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _assertPositionUpdate() internal view {
        // position
        assertEq(actual.position.amount, expected.position.amount, "position: amount incorrect");
        assertEq(actual.position.openNotional, expected.position.openNotional, "position: openNotional incorrect");
        assertEq(actual.position.leverage, expected.position.leverage, "position: leverage incorrect");
        assertEq(actual.position.isLong, expected.position.isLong, "position: isLong incorrect");
        assertEq(
            actual.position.lastCumulativeFunding,
            expected.position.lastCumulativeFunding,
            "position: lastCumulativeFunding incorrect"
        );

        // result
        assertEq(actual.result.marginDelta, expected.result.marginDelta, "result marginDelta incorrect");
        assertEq(actual.result.rpnl, expected.result.rpnl, "result rpnl incorrect");
        assertEq(actual.result.oiDelta.long, expected.result.oiDelta.long, "result oiDelta long incorrect");
        assertEq(actual.result.oiDelta.short, expected.result.oiDelta.short, "result oiDelta short incorrect");
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _predictOpen() internal {
        expected.position.amount = params.baseAmount + params.position.amount;
        expected.position.openNotional = params.quoteAmount + params.position.openNotional;
        expected.position.leverage = params.position.leverage;
        expected.position.lastCumulativeFunding = params.position.lastCumulativeFunding;

        expected.result.marginDelta = params.quoteAmount.fullMulDiv(1e18, params.position.leverage).toInt256();

        if (params.side == Side.BUY) {
            expected.position.isLong = true;
            expected.result.oiDelta.long = params.baseAmount.toInt256();
        } else {
            expected.position.isLong = false;
            expected.result.oiDelta.short = params.baseAmount.toInt256();
        }
    }

    function _predictDecrease() internal {
        uint256 closedOpenNotional = params.position.openNotional.fullMulDiv(params.baseAmount, params.position.amount);

        expected.position.amount = params.position.amount - params.baseAmount;
        expected.position.openNotional = params.position.openNotional - closedOpenNotional;
        expected.position.leverage = params.position.leverage;
        expected.position.isLong = params.position.isLong;
        expected.position.lastCumulativeFunding = params.position.lastCumulativeFunding;

        expected.result.rpnl = _getRpnl({
            currentNotional: params.quoteAmount,
            openNotional: closedOpenNotional,
            isLong: params.position.isLong
        });

        expected.result.marginDelta = -closedOpenNotional.fullMulDiv(1e18, params.position.leverage).toInt256();

        if (params.side == Side.BUY) {
            // closing short
            expected.result.oiDelta.short = -params.baseAmount.toInt256();
        } else {
            // closing long
            expected.result.oiDelta.long = -params.baseAmount.toInt256();
        }
    }

    function _predictClose() internal {
        expected.position.leverage = params.position.leverage;

        expected.result.rpnl = _getRpnl({
            currentNotional: params.quoteAmount,
            openNotional: params.position.openNotional,
            isLong: params.position.isLong
        });

        expected.result.marginDelta =
            -params.position.openNotional.fullMulDiv(1e18, params.position.leverage).toInt256();

        if (params.side == Side.BUY) {
            // closing short
            expected.result.oiDelta.short = -params.position.amount.toInt256();
        } else {
            // closing long
            expected.result.oiDelta.long = -params.position.amount.toInt256();
        }

        // note: for reverse open test, delete old position size & open notional
        delete params.position.amount;
        delete params.position.openNotional;
    }

    function _getRandomCumulativeFunding() internal returns (int256 cumulativeFunding) {
        cumulativeFunding = _hem(_random(), 1e18, 1_000_000e18).toInt256();

        if (_randomChance(50)) cumulativeFunding = -cumulativeFunding;
    }

    function _getRpnl(uint256 currentNotional, uint256 openNotional, bool isLong) internal pure returns (int256 rpnl) {
        if (isLong) return currentNotional.toInt256() - openNotional.toInt256();
        else return openNotional.toInt256() - currentNotional.toInt256();
    }
}
