// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";

import {Side} from "./Enums.sol";
import {FundingPaymentResult, PositionUpdateResult, OIDelta} from "./Structs.sol";

struct Position {
    bool isLong;
    uint256 amount;
    uint256 openNotional;
    uint256 leverage;
    int256 lastCumulativeFunding;
}

using PositionLib for Position global;

library PositionLib {
    using FixedPointMathLib for *;
    using SafeCastLib for uint256;

    struct __CloseCache__ {
        uint256 closeSize;
        uint256 closedOpenNotional;
        uint256 currentNotional;
        uint256 marginRemoved;
        int256 remainingMargin;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                          POSITION MANAGEMENT
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function processTrade(Position memory self, Side side, uint256 quoteTraded, uint256 baseTraded)
        internal
        pure
        returns (PositionUpdateResult memory result)
    {
        bool openLong = side == Side.BUY && (self.isLong || self.amount == 0);
        bool openShort = side == Side.SELL && (!self.isLong || self.amount == 0);

        if (openLong || openShort) {
            result.marginDelta = _open(self, side, quoteTraded, baseTraded);

            if (side == Side.BUY) result.oiDelta.long += baseTraded.toInt256();
            else result.oiDelta.short += baseTraded.toInt256();
        } else {
            result = _close(self, side, quoteTraded, baseTraded);
        }
    }

    function realizeFundingPayment(Position memory self, int256 cumulativeFunding)
        internal
        pure
        returns (int256 fundingPayment)
    {
        if (self.lastCumulativeFunding == cumulativeFunding) return 0;

        fundingPayment = _getFundingPayment({
            amount: self.isLong ? self.amount.toInt256() : -self.amount.toInt256(),
            lastCumulativePremiumFunding: self.lastCumulativeFunding,
            cumulativePremiumFunding: cumulativeFunding
        });

        self.lastCumulativeFunding = cumulativeFunding;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               FILL LOGIC
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _open(Position memory self, Side side, uint256 quoteTraded, uint256 baseTraded)
        private
        pure
        returns (int256 marginDelta)
    {
        if (self.leverage == 0) self.leverage = 1e18; // default leverage

        self.isLong = side == Side.BUY;

        self.amount += baseTraded;
        self.openNotional += quoteTraded;

        marginDelta = quoteTraded.fullMulDiv(1e18, self.leverage).toInt256();
    }

    /// @dev covers decrease, close, reverse open
    function _close(Position memory self, Side side, uint256 quoteTraded, uint256 baseTraded)
        private
        pure
        returns (PositionUpdateResult memory result)
    {
        __CloseCache__ memory cache;

        cache.closeSize = self.amount.min(baseTraded);

        // pro rate quote amounts by close
        cache.closedOpenNotional = self.openNotional.fullMulDiv(cache.closeSize, self.amount);
        cache.currentNotional = quoteTraded.fullMulDiv(cache.closeSize, baseTraded);

        result.rpnl = _pnl(self.isLong, cache.closedOpenNotional, cache.currentNotional);
        result.marginDelta = -cache.closedOpenNotional.fullMulDiv(1e18, self.leverage).toInt256();

        self.openNotional -= cache.closedOpenNotional;
        self.amount -= cache.closeSize;

        quoteTraded -= cache.currentNotional;
        baseTraded -= cache.closeSize;

        if (self.isLong) result.oiDelta.long = -cache.closeSize.toInt256();
        else result.oiDelta.short = -cache.closeSize.toInt256();

        if (result.sideClose = self.amount == 0) {
            // reverse open
            if (baseTraded > 0) {
                result.marginDelta = _open(self, side, quoteTraded, baseTraded);

                if (self.isLong) result.oiDelta.long += baseTraded.toInt256();
                else result.oiDelta.short += baseTraded.toInt256();
            } else {
                // full close, set to defaults
                delete self.lastCumulativeFunding;
                delete self.isLong;
            }
        }
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _getFundingPayment(int256 amount, int256 lastCumulativePremiumFunding, int256 cumulativePremiumFunding)
        private
        pure
        returns (int256)
    {
        if (amount == 0) return 0;

        return _mul(amount, cumulativePremiumFunding - lastCumulativePremiumFunding);
    }

    /// @dev wrapper for fullMulDiv to handle int256
    function _mul(int256 amt, int256 fundingDelta) private pure returns (int256) {
        uint256 result = amt.abs().fullMulDiv(fundingDelta.abs(), 1e18);
        return amt < 0 != fundingDelta < 0 ? -result.toInt256() : result.toInt256();
    }

    function _pnl(bool isLong, uint256 openNotional, uint256 currentNotional) private pure returns (int256 pnl) {
        if (isLong) pnl = currentNotional.toInt256() - openNotional.toInt256();
        else pnl = openNotional.toInt256() - currentNotional.toInt256();
    }
}
