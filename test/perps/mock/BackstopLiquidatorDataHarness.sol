// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {BackstopLiquidatorDataLib, LiquidatorData} from "../../../contracts/perps/types/BackstopLiquidatorDataLib.sol";

contract BackstopLiquidatorDataHarness {
    bool public constant IS_SCRIPT = true;

    function addVolume(address liquidator, uint256 volume) external {
        BackstopLiquidatorDataLib.addLiquidatorVolume(liquidator, volume);
    }

    function getLiquidatorData() external returns (LiquidatorData[] memory) {
        return BackstopLiquidatorDataLib.getLiquidatorDataAndClearStorage();
    }

    function getLiquidators() external returns (address[] memory) {
        return BackstopLiquidatorDataLib._getLiquidatorsAndClear();
    }

    function getVolume(address liquidator) external returns (uint256 volume) {
        volume = BackstopLiquidatorDataLib._getVolumeAndClear(liquidator);
    }
}
