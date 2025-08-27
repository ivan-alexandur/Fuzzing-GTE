// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {AdminPanel} from "contracts/perps/modules/AdminPanel.sol";
import {ViewPort} from "contracts/perps/modules/ViewPort.sol";
import {ClearingHouseLib} from "contracts/perps/types/ClearingHouse.sol";
import {StorageLib} from "contracts/perps/types/StorageLib.sol";
import {PlaceOrderArgs, PlaceOrderResult} from "contracts/perps/types/Structs.sol";
import {FeeTier, BookType} from "contracts/perps/types/Enums.sol";

contract MockAdminPanel is AdminPanel, ViewPort {
    function deposit(address account, uint256 amount) external {
        require(msg.sender == account, "Only sender can deposit collateral");
        StorageLib.loadCollateralManager().depositFreeCollateral(account, account, amount);
    }

    function placeOrder(address account, PlaceOrderArgs calldata args) external returns (PlaceOrderResult memory) {
        require(msg.sender == account, "Only sender can place order");
        return StorageLib.loadClearingHouse().placeOrder(account, args, BookType.STANDARD);
    }

    function getAccountFeeTier(address account) public view returns (FeeTier) {
        return StorageLib.loadFeeManager().getAccountFeeTier(account);
    }

    function getLiquidatorPoints(address account) public view returns (uint256) {
        return StorageLib.loadClearingHouse().liquidatorPoints[account];
    }

    function mockSetMarkPrice(bytes32 asset, uint256 markPrice) external {
        StorageLib.loadClearingHouse().market[asset].markPrice = markPrice;
    }
}
