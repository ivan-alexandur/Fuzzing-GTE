// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

type PackedFeeRates is uint256;

using PackedFeeRatesLib for PackedFeeRates global;

library PackedFeeRatesLib {
    /// @dev sig: 0x08498ba1
    error TooManyFeeTiers();
    /// @dev sig: 0x4e23d035
    error IndexOutOfBounds();

    function packFeeRates(uint16[] memory fees) internal pure returns (PackedFeeRates) {
        if (fees.length > 15) revert TooManyFeeTiers();

        uint256 packedValue;
        for (uint256 i; i < fees.length; i++) {
            packedValue = packedValue | (uint256(fees[i]) << (i * 16));
        }

        return PackedFeeRates.wrap(packedValue);
    }

    function getFeeAt(PackedFeeRates fees, uint256 index) internal pure returns (uint16) {
        if (index > 15) revert IndexOutOfBounds();

        uint256 shiftBits = index * 16;

        return uint16((PackedFeeRates.unwrap(fees) >> shiftBits) & 0xFFFF);
    }
}
