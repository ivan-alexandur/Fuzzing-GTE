// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {AdminPanel} from "../../../contracts/perps/modules/AdminPanel.sol";
import {LiquidatorPanel} from "../../../contracts/perps/modules/LiquidatorPanel.sol";
import {ClearingHouse, ClearingHouseLib} from "../../../contracts/perps/types/ClearingHouse.sol";
import {StorageLib} from "../../../contracts/perps/types/StorageLib.sol";
import {BackstopLiquidatorDataLib} from "../../../contracts/perps/types/BackstopLiquidatorDataLib.sol";
import {CollateralManager} from "../../../contracts/perps/types/CollateralManager.sol";

contract MockBackstopLiquidationSettlement is LiquidatorPanel, AdminPanel {
    modifier onlyActiveProtocol() override (LiquidatorPanel, AdminPanel) {
        _;
    }

    function addLiquidatorVolume(address liquidator, uint256 volume) external {
        BackstopLiquidatorDataLib.addLiquidatorVolume(liquidator, volume);
    }

    function getFreeCollateralBalance(address account) external view returns (uint256 collateralBalance) {
        return StorageLib.loadCollateralManager().getFreeCollateralBalance(account);
    }

    function settleBackstopLiquidation(bytes32 asset, uint256 margin) external returns (uint256 liquidationFee) {
        return _settleBackstopLiquidation(StorageLib.loadClearingHouse(), asset, margin);
    }
}
