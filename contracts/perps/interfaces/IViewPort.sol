// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Status, Side} from "../types/Enums.sol";

import {Position} from "../types/Position.sol";
import {Order} from "../types/Order.sol";
import {PackedFeeRates} from "../types/PackedFeeRatesLib.sol";

interface IViewPort {
    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                ACCOUNT
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function getPosition(bytes32 asset, address account, uint256 subaccount) external view returns (Position memory);

    function getAssets(address account, uint256 subaccount) external view returns (bytes32[] memory);

    function getMarginBalance(address account, uint256 subaccount) external view returns (int256);

    function getFreeCollateralBalance(address account) external view returns (uint256);

    function getOrderbookCollateral(address account, uint256 subaccount)
        external
        view
        returns (uint256 orderbookCollateral);

    function getPositionLeverage(bytes32 asset, address account, uint256 subaccount)
        external
        view
        returns (uint256 leverage);

    function getAccountValue(address account, uint256 subaccount) external view returns (int256);

    function isLiquidatable(address account, uint256 subaccount) external view returns (bool);

    function isLiquidatableBackstop(address account, uint256 subaccount) external view returns (bool);

    function getReduceOnlyOrders(bytes32 asset, address account, uint256 subaccount)
        external
        view
        returns (uint256[] memory orderIds);

    function getPendingFundingPayment(address account, uint256 subaccount) external view returns (int256);

    function getOrderbookNotional(bytes32 asset, address account, uint256 subaccount) external view returns (uint256);

    function getMaintenanceMargin(bytes32 asset, uint256 positionAmount) external view returns (uint256);

    function getIntendedMarginAndUpnl(bytes32 asset, Position memory position)
        external
        view
        returns (uint256, int256);

    function getNextEmptySubaccount(address account) external view returns (uint256 subaccount);

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                ORDERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function getLimitOrder(bytes32 asset, uint256 orderId) external view returns (Order memory);

    function getLimitOrderBackstop(bytes32 asset, uint256 orderId) external view returns (Order memory);

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               PROTOCOL
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function getCollateralAsset() external pure returns (address);

    function getTakerFeeRates() external view returns (PackedFeeRates);

    function getMakerFeeRates() external view returns (PackedFeeRates);

    function getInsuranceFundBalance() external view returns (uint256);

    function isAdmin(address account) external view returns (bool);

    function getNonce() external view returns (uint256);

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                              MARKET DATA
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function getMarkPrice(bytes32 asset) external view returns (uint256);

    function getIndexPrice(bytes32 asset) external view returns (uint256);

    function getFundingRate(bytes32 asset) external view returns (int256);

    function getCumulativeFunding(bytes32 asset) external view returns (int256);

    function getLastFundingTime(bytes32 asset) external view returns (uint256);

    function getOpenInterest(bytes32 asset) external view returns (uint256 longOi, uint256 shortOi);

    function getOpenInterestBook(bytes32 asset) external view returns (uint256 baseOi, uint256 quoteOi);

    function getOpenInterestBackstopBook(bytes32 asset) external view returns (uint256 baseOi, uint256 quoteOi);

    function getNumBids(bytes32 asset) external view returns (uint256);

    function getNumBidsBackstop(bytes32 asset) external view returns (uint256);

    function getNumAsks(bytes32 asset) external view returns (uint256);

    function getNumAsksBackstop(bytes32 asset) external view returns (uint256);

    function getNextOrderId(bytes32 asset) external view returns (uint96);

    function getNextOrderIdBackstop(bytes32 asset) external view returns (uint96);

    function getMidPrice(bytes32 asset) external view returns (uint256);

    function quoteBookInBase(bytes32 asset, uint256 baseAmount, Side side)
        external
        view
        returns (uint256 quoteAmount, uint256 baseUsed);

    function quoteBookInQuote(bytes32 asset, uint256 quoteAmount, Side side)
        external
        view
        returns (uint256 baseAmount, uint256 quoteUsed);

    function quoteBackstopBookInBase(bytes32 asset, uint256 baseAmount, Side side)
        external
        view
        returns (uint256 quoteAmount, uint256 baseUsed);

    function quoteBackstopBookInQuote(bytes32 asset, uint256 quoteAmount, Side side)
        external
        view
        returns (uint256 baseAmount, uint256 quoteUsed);

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            MARKET SETTINGS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function getMarketStatus(bytes32 asset) external view returns (Status);

    function isCrossMarginEnabled(bytes32 asset) external view returns (bool);

    function getMaxLeverage(bytes32 asset) external view returns (uint256);

    function getMinMarginRatio(bytes32 asset) external view returns (uint256);

    function getMinMarginRatioBackstop(bytes32 asset) external view returns (uint256);

    function getLiquidationFeeRate(bytes32 asset) external view returns (uint256);

    function getDivergenceCap(bytes32 asset) external view returns (uint256);

    function getReduceOnlyCap(bytes32 asset) external view returns (uint256);

    function getPartialLiquidationThreshold(bytes32 asset) external view returns (uint256);

    function getPartialLiquidationRate(bytes32 asset) external view returns (uint256);

    function getCurrentFundingInterval(bytes32 asset) external view returns (uint256);

    function getFundingInterval(bytes32 asset) external view returns (uint256);

    function getResetInterval(bytes32 asset) external view returns (uint256);

    function getResetIterations(bytes32 asset) external view returns (uint256);

    function getInterestRate(bytes32 asset) external view returns (int256);

    function getFundingClamps(bytes32 asset) external view returns (uint256 innerClamp, uint256 outerClamp);

    function getMaxNumOrders(bytes32 asset) external view returns (uint256);

    function getMaxLimitsPerTx(bytes32 asset) external view returns (uint8);

    function getMinLimitOrderAmountInBase(bytes32 asset) external view returns (uint256);

    function getTickSize(bytes32 asset) external view returns (uint256);

    function getLotSize(bytes32 asset) external view returns (uint256);
}
