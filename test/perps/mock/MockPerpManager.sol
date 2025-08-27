// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {DynamicArrayLib} from "@solady/utils/DynamicArrayLib.sol";
import {EnumerableSetLib} from "@solady/utils/EnumerableSetLib.sol";

import {Position} from "../../../contracts/perps/types/Position.sol";
import {Market} from "../../../contracts/perps/types/Market.sol";
import {PerpManager} from "../../../contracts/perps/PerpManager.sol";

import {StorageLib} from "../../../contracts/perps/types/ClearingHouse.sol";
import {StorageLib} from "../../../contracts/perps/types/StorageLib.sol";

contract MockPerpManager is PerpManager {
    using EnumerableSetLib for EnumerableSetLib.Bytes32Set;

    bool public IS_SCRIPT = true;

    constructor(address _operatorHub) PerpManager(address(0), _operatorHub) {}

    event MarkPriceUpdated(bytes32 indexed asset, uint256 markPrice, uint256 p1, uint256 p2, uint256 p3, uint256 nonce);
    event FundingSettled(bytes32 indexed asset, int256 funding, int256 cumulativeFunding, uint256 openInterest, uint256 nonce);

    function mockSetMarkPrice(bytes32 asset, uint256 markPrice) external {
        Market storage market = StorageLib.loadMarket(asset);
        market.markPrice = markPrice;
        emit MarkPriceUpdated(asset, markPrice, 0, 0, 0, StorageLib.incNonce());
    }

    function mockSetCumulativeFunding(bytes32 asset, int256 cumulativeFunding) external {
        int256 fundingBefore = StorageLib.loadFundingRateEngine(asset).cumulativeFundingIndex;

        int256 delta = cumulativeFunding - fundingBefore;

        StorageLib.loadFundingRateEngine(asset).cumulativeFundingIndex = cumulativeFunding;

        emit FundingSettled(
            asset, 
            delta, 
            cumulativeFunding, 
            StorageLib.loadMarketMetadata(asset).longOI,
            StorageLib.incNonce()
        );
    }

    function mockOpenPosition(
        bytes32 asset,
        address account,
        uint256 subaccount,
        Position memory position,
        int256 margin
    ) external {
        StorageLib.loadClearingHouse().market[asset].position[account][subaccount] = position;
        StorageLib.loadCollateralManager().margin[account][subaccount] += margin;
    }

    function mockRebalance(
        DynamicArrayLib.DynamicArray memory assets,
        Position[] memory positions,
        int256 margin,
        int256 marginDelta
    ) external view returns (int256 marginAfterDelta, int256 rebalancedMarginDelta) {
        return StorageLib.loadClearingHouse().rebalanceAccount({
            assets: assets,
            positions: positions,
            margin: margin,
            marginDelta: marginDelta
        });
    }

    function getBankruptcyPrice(Position memory position, uint256 closeSize, int256 margin)
        external
        pure
        returns (uint256 bankruptcyPrice)
    {
        return _getBankruptcyPrice(position, closeSize, margin);
    }

    function mockGetProratedMargin(
        DynamicArrayLib.DynamicArray memory assets,
        Position[] memory positions,
        bytes32 asset,
        int256 margin
    ) external view returns (int256) {
        return StorageLib.loadClearingHouse().getProratedMargin({
            assets: assets,
            positions: positions,
            asset: asset,
            margin: margin
        });
    }

    /// @dev Sets the position and the asset if misisng.
    /// removes position and asset if new position amount is zero
    function mockSetPosition(address account, uint256 subaccount, bytes32 asset, Position memory position) external {
        StorageLib.loadClearingHouse().market[asset].position[account][subaccount] = position;

        // Add the asset to the account's asset set if it doesn't exist and position amount > 0
        if (position.amount > 0) {
            if (!StorageLib.loadClearingHouse().assets[account][subaccount].contains(asset)) {
                StorageLib.loadClearingHouse().assets[account][subaccount].add(asset);
            }
        } else {
            // Remove the asset if position amount is 0 and it exists
            if (StorageLib.loadClearingHouse().assets[account][subaccount].contains(asset)) {
                StorageLib.loadClearingHouse().assets[account][subaccount].remove(asset);
            }
        }
    }

    function mockSetMargin(address account, uint256 subaccount, int256 margin) external {
        StorageLib.loadCollateralManager().margin[account][subaccount] = margin;
    }

    function harness_CH_GetUpnl_AssetsPositions(DynamicArrayLib.DynamicArray memory assets, Position[] memory positions)
        external
        view
        returns (int256 upnl)
    {
        return StorageLib.loadClearingHouse().getUpnl(assets, positions);
    }

    function harness_CH_GetNotionalAccountValue(DynamicArrayLib.DynamicArray memory assets, Position[] memory positions)
        external
        view
        returns (uint256 totalNotional)
    {
        return StorageLib.loadClearingHouse().getNotionalAccountValue(assets, positions);
    }

    function mockAddAsset(address account, uint256 subaccount, bytes32 asset) external {
        if (!StorageLib.loadClearingHouse().assets[account][subaccount].contains(asset)) {
            StorageLib.loadClearingHouse().assets[account][subaccount].add(asset);
        }
    }
}
