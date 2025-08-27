// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../PerpManagerTestBase.sol";

contract Perp_BankruptcyPrice_Test is PerpManagerTestBase {
    using FixedPointMathLib for *;
    using SafeCastLib for *;

    Position position;
    int256 margin;
    uint256 closeSize;
    uint256 realizedLoss;
    uint256 bankruptcyPrice;

    function test_Perp_BankruptcyPrice_Full(uint256) public {
        uint256 openPrice = _hem(_randomUnique(), 1e18, 200_000e18);
        uint256 leverage = _hem(_randomUnique(), 2e18, 50e18);

        position.amount = _hem(_randomUnique(), 1e16, 10_000e18);
        position.openNotional = position.amount.fullMulDiv(openPrice, 1e18);
        position.isLong = _randomChance(2);
        margin = position.openNotional.fullMulDiv(1e18, leverage).toInt256();

        realizedLoss = _hem(_random(), 0, margin.abs() + margin.abs() / 2);

        closeSize = position.amount;

        bankruptcyPrice = perpManager.getBankruptcyPrice(position, closeSize, margin);

        assertApproxEqAbs(margin + _getRpnl(), 0, 10_000, "margin + rpnl should be zero at bankruptcy price");
    }

    function test_Perp_BankruptcyPrice_Partial(uint256) public {
        uint256 openPrice = _hem(_randomUnique(), 1e18, 200_000e18);
        uint256 leverage = _hem(_randomUnique(), 2e18, 50e18);

        position.amount = _hem(_randomUnique(), 1e16, 10_000e18);
        position.openNotional = position.amount.fullMulDiv(openPrice, 1e18);
        position.isLong = _randomChance(2);
        margin = position.openNotional.fullMulDiv(1e18, leverage).toInt256();

        realizedLoss = _hem(_random(), 0, margin.abs() + margin.abs() / 2);

        closeSize = _hem(_randomUnique(), 1e15, position.amount - 10_000);

        bankruptcyPrice = perpManager.getBankruptcyPrice(position, closeSize, margin);

        assertApproxEqAbs(_prorateMargin() + _getRpnl(), 0, 10_000, "margin + rpnl should be zero at bankruptcy price");
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _getRpnl() internal view returns (int256) {
        uint256 currentNotional = closeSize.fullMulDiv(bankruptcyPrice, 1e18);
        uint256 openNotional = position.openNotional.fullMulDiv(closeSize, position.amount);

        if (position.isLong) return currentNotional.toInt256() - openNotional.toInt256();
        else return openNotional.toInt256() - currentNotional.toInt256();
    }

    function _prorateMargin() internal view returns (int256 proratedMargin) {
        proratedMargin = margin.abs().fullMulDiv(closeSize, position.amount).toInt256();

        if (margin < 0) proratedMargin = -proratedMargin;
    }
}
