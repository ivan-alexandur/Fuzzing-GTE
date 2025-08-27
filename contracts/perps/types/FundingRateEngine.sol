// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";

import {StorageLib} from "./StorageLib.sol";

struct FundingRateSettings {
    uint256 fundingInterval;
    uint256 resetInterval;
    uint256 resetIterations;
    uint256 innerClamp;
    uint256 outerClamp;
    int256 interestRate;
}

struct FundingRateEngine {
    int256 fundingRate;
    int256 cumulativeFundingIndex;
    uint256 lastFundingTime;
    uint256 resetIterationsLeft;
}

using FundingLib for FundingRateEngine global;
using FundingLib for FundingRateSettings global;

library FundingLib {
    using FixedPointMathLib for *;
    using SafeCastLib for uint256;

    error FundingIntervalNotElapsed();

    function init(FundingRateSettings storage settings, FundingRateSettings memory initSettings) internal {
        settings.fundingInterval = initSettings.fundingInterval;
        settings.resetInterval = initSettings.resetInterval;
        settings.resetIterations = initSettings.resetIterations;
        settings.innerClamp = initSettings.innerClamp;
        settings.outerClamp = initSettings.outerClamp;
        settings.interestRate = initSettings.interestRate;
    }

    function settleFunding(FundingRateEngine storage self, bytes32 asset, uint256 markTwap, uint256 indexTwap)
        internal
        returns (int256 fundingIndex, int256 cumulativeFundingIndex)
    {
        FundingRateSettings storage settings = StorageLib.loadFundingRateSettings(asset);

        self.assertFundingIntervalElapsed(asset);

        self.lastFundingTime = block.timestamp;

        int256 fundingRate;
        (fundingIndex, fundingRate) = _calcFundingIndex({
            self: self,
            settings: settings,
            markTwap: markTwap.toInt256(),
            indexTwap: indexTwap.toInt256()
        });

        cumulativeFundingIndex = self.cumulativeFundingIndex += fundingIndex;
        self.fundingRate = fundingRate;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               GETTERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function getFundingInterval(FundingRateEngine storage self, bytes32 asset) internal view returns (uint256) {
        FundingRateSettings storage settings = StorageLib.loadFundingRateSettings(asset);

        return self.resetIterationsLeft == 0 ? settings.fundingInterval : settings.resetInterval;
    }

    function getCumulativeFunding(FundingRateEngine storage self) internal view returns (int256) {
        return self.cumulativeFundingIndex;
    }

    function getTimeSinceLastFunding(FundingRateEngine storage self) internal view returns (uint256) {
        return block.timestamp - self.lastFundingTime;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               ASSERTIONS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function assertFundingIntervalElapsed(FundingRateEngine storage self, bytes32 asset) internal view {
        uint256 elapsedTime = self.getTimeSinceLastFunding();
        uint256 interval = self.getFundingInterval(asset);

        if (interval > elapsedTime) revert FundingIntervalNotElapsed();
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            PRIVATE HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _calcFundingIndex(
        FundingRateEngine storage self,
        FundingRateSettings storage settings,
        int256 markTwap,
        int256 indexTwap
    ) private returns (int256 fundingIndex, int256 fundingRate) {
        int256 innerClamp = settings.innerClamp.toInt256();
        int256 outerClamp = settings.outerClamp.toInt256();

        int256 premium = _div(markTwap - indexTwap, indexTwap);

        int256 rawFunding = premium + (settings.interestRate - premium).clamp(-innerClamp, innerClamp);

        fundingRate = rawFunding.clamp(-outerClamp, outerClamp);

        if (fundingRate != rawFunding) self.resetIterationsLeft = settings.resetIterations;
        else if (self.resetIterationsLeft > 0) --self.resetIterationsLeft;

        fundingIndex = _mul(fundingRate, indexTwap);
    }

    // @dev wrapper for fullMulDiv to handle int256
    function _div(int256 a, int256 b) private pure returns (int256) {
        uint256 result = a.abs().fullMulDiv(1e18, b.abs());
        return a < 0 != b < 0 ? -result.toInt256() : result.toInt256();
    }

    function _mul(int256 a, int256 b) private pure returns (int256) {
        uint256 result = a.abs().fullMulDiv(b.abs(), 1e18);
        return a < 0 != b < 0 ? -result.toInt256() : result.toInt256();
    }
}
