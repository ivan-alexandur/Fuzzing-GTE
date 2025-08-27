// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {LiquidatorData} from "./Structs.sol";

library BackstopLiquidatorDataLib {
    /// erc7201('TransientLiquidators')
    bytes32 constant TRANSIENT_LIQUIDATORS_SLOT = 0x4241b72dd798242510fb56f3af1b11b473993219eaff939db6095ef4a72ad900;
    /// erc7201('TransientVolume')
    bytes32 constant TRANSIENT_VOLUME_SLOT = 0xddbbbd6c2145904e746c66ce13af468e7d054181c91f1b7fbae06864da072000;

    function addLiquidatorVolume(address liquidator, uint256 volume) internal {
        bytes32 slot = keccak256(abi.encode(TRANSIENT_VOLUME_SLOT, liquidator));

        bool exists;
        assembly ("memory-safe") {
            exists := iszero(iszero(tload(slot)))

            if iszero(exists) { tstore(slot, 1) }

            let totalVolume := tload(add(slot, 1))

            tstore(add(slot, 1), add(totalVolume, volume))
        }

        if (!exists) _addLiquidator(liquidator);
    }

    function getLiquidatorDataAndClearStorage() internal returns (LiquidatorData[] memory liquidatorData) {
        address[] memory liquidators = _getLiquidatorsAndClear();

        uint256 length = liquidators.length;

        liquidatorData = new LiquidatorData[](length);

        uint256 volume;
        for (uint256 i; i < length; i++) {
            volume = _getVolumeAndClear(liquidators[i]);

            liquidatorData[i] = LiquidatorData({liquidator: liquidators[i], volume: volume});
        }
    }

    function _addLiquidator(address liquidator) internal {
        bytes32 slot = TRANSIENT_LIQUIDATORS_SLOT;

        assembly ("memory-safe") {
            let len := tload(slot)

            mstore(0x00, slot)

            let dataSlot := keccak256(0x00, 0x20)

            tstore(add(dataSlot, len), liquidator)
            tstore(slot, add(len, 1))
        }
    }

    function _getLiquidatorsAndClear() internal returns (address[] memory liquidators) {
        bytes32 slot = TRANSIENT_LIQUIDATORS_SLOT;

        assembly ("memory-safe") {
            let len := tload(slot)

            liquidators := mload(0x40)

            mstore(liquidators, len)

            mstore(0x00, slot)

            let dataSlot := keccak256(0x00, 0x20)
            let memPointer := add(liquidators, 0x20)

            for { let i := 0 } lt(i, len) { i := add(i, 1) } {
                mstore(add(memPointer, mul(i, 0x20)), tload(add(dataSlot, i)))
                tstore(add(dataSlot, i), 0) // clear maker
            }

            mstore(0x40, add(memPointer, mul(len, 0x20)))
            tstore(slot, 0) // clear length
        }
    }

    function _getVolumeAndClear(address liquidator) internal returns (uint256 volume) {
        bytes32 slot = keccak256(abi.encode(TRANSIENT_VOLUME_SLOT, liquidator));

        assembly ("memory-safe") {
            volume := tload(add(slot, 1))

            tstore(slot, 0)
            tstore(add(slot, 1), 0)
        }
    }
}
