// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";

import {PackedFeeRates, PackedFeeRatesLib} from "./PackedFeeRatesLib.sol";
import {FeeTier} from "./Enums.sol";

struct FeeManager {
    mapping(address account => FeeTier) accountFeeTier;
    PackedFeeRates takerFeeRates;
    PackedFeeRates makerFeeRates;
}

using FeeManagerLib for FeeManager global;

library FeeManagerLib {
    using FixedPointMathLib for uint256;

    uint256 constant FEE_SCALING = 10_000_000;

    function setAccountFeeTier(FeeManager storage self, address account, FeeTier feeTier) internal {
        self.accountFeeTier[account] = feeTier;
    }

    function setTakerFeeRates(FeeManager storage self, uint16[] memory takerFeeRates) internal {
        self.takerFeeRates = PackedFeeRatesLib.packFeeRates(takerFeeRates);
    }

    function setMakerFeeRates(FeeManager storage self, uint16[] memory makerFeeRates) internal {
        self.makerFeeRates = PackedFeeRatesLib.packFeeRates(makerFeeRates);
    }

    function getTakerFee(FeeManager storage self, address account, uint256 amount) internal view returns (uint256) {
        if (amount == 0) return 0;

        uint16 feeRate = self.getTakerFeeRate(account);
        return amount.fullMulDiv(feeRate, FEE_SCALING);
    }

    function getMakerFee(FeeManager storage self, address account, uint256 amount) internal view returns (uint256) {
        if (amount == 0) return 0;

        uint16 feeRate = self.getMakerFeeRate(account);
        return amount.fullMulDiv(feeRate, FEE_SCALING);
    }

    function getTakerFeeRate(FeeManager storage self, address account) internal view returns (uint16 feeRate) {
        return self.takerFeeRates.getFeeAt(uint256(self.accountFeeTier[account]));
    }

    function getMakerFeeRate(FeeManager storage self, address account) internal view returns (uint16 feeRate) {
        return self.makerFeeRates.getFeeAt(uint256(self.accountFeeTier[account]));
    }

    function getAccountFeeTier(FeeManager storage self, address account) internal view returns (FeeTier tier) {
        return self.accountFeeTier[account];
    }

    function getAccountTakerFeeRate(FeeManager storage self, address account) internal view returns (uint16 feeRate) {
        return self.takerFeeRates.getFeeAt(uint256(self.accountFeeTier[account]));
    }

    function getAccountMakerFeeRate(FeeManager storage self, address account) internal view returns (uint16 feeRate) {
        return self.makerFeeRates.getFeeAt(uint256(self.accountFeeTier[account]));
    }
}
