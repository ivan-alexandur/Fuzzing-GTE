// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {BeforeAfter} from "../BeforeAfter.sol";
import {Properties} from "../Properties.sol";
// Chimera deps
import {vm} from "@chimera/Hevm.sol";

// Helpers
import {Panic} from "@recon/Panic.sol";

import "contracts/perps/PerpManager.sol";

abstract contract PerpManagerTargets is
    BaseTargetFunctions,
    Properties
{
    /// CUSTOM TARGET FUNCTIONS - Add your own target functions here ///


    /// AUTO GENERATED TARGET FUNCTIONS - WARNING: DO NOT DELETE OR MODIFY THIS LINE ///

    function perpManager_activateMarket(bytes32 asset) public asActor {
        perpManager.activateMarket(asset);
    }

    function perpManager_activateProtocol() public asActor {
        perpManager.activateProtocol();
    }

    function perpManager_addMargin(address account, uint256 subaccount, uint256 amount) public asActor {
        perpManager.addMargin(account, subaccount, amount);
    }

    function perpManager_amendLimitOrder(address account, AmendLimitOrderArgs memory args) public asActor {
        perpManager.amendLimitOrder(account, args);
    }

    function perpManager_amendLimitOrderBackstop(address account, AmendLimitOrderArgs memory args) public asActor {
        perpManager.amendLimitOrderBackstop(account, args);
    }

    function perpManager_approveOperator(address account, address operator, uint256 roles) public asActor {
        perpManager.approveOperator(account, operator, roles);
    }

    function perpManager_backstopLiquidate(bytes32 asset, address account, uint256 subaccount) public asActor {
        perpManager.backstopLiquidate(asset, account, subaccount);
    }

    function perpManager_cancelConditionalOrders(address account, uint256[] memory nonces) public asActor {
        perpManager.cancelConditionalOrders(account, nonces);
    }

    function perpManager_cancelLimitOrders(bytes32 asset, address account, uint256 subaccount, uint256[] memory orderIds) public asActor {
        perpManager.cancelLimitOrders(asset, account, subaccount, orderIds);
    }

    function perpManager_cancelLimitOrdersBackstop(bytes32 asset, address account, uint256 subaccount, uint256[] memory orderIds) public asActor {
        perpManager.cancelLimitOrdersBackstop(asset, account, subaccount, orderIds);
    }

    function perpManager_cancelOwnershipHandover() public payable asActor {
        perpManager.cancelOwnershipHandover{value: msg.value}();
    }

    function perpManager_completeOwnershipHandover(address pendingOwner) public payable asActor {
        perpManager.completeOwnershipHandover{value: msg.value}(pendingOwner);
    }

    function perpManager_createMarket(bytes32 asset, MarketParams memory params) public asActor {
        perpManager.createMarket(asset, params);
    }

    function perpManager_deactivateMarket(bytes32 asset) public asActor {
        perpManager.deactivateMarket(asset);
    }

    function perpManager_deactivateProtocol() public asActor {
        perpManager.deactivateProtocol();
    }

    function perpManager_deleverage(bytes32 asset, DeleveragePair[] memory pairs) public asActor {
        perpManager.deleverage(asset, pairs);
    }

    function perpManager_delistClose(bytes32 asset, Account[] memory accounts) public asActor {
        perpManager.delistClose(asset, accounts);
    }

    function perpManager_delistMarket(bytes32 asset) public asActor {
        perpManager.delistMarket(asset);
    }

    function perpManager_deposit(address account, uint256 amount) public asActor {
        perpManager.deposit(account, amount);
    }

    function perpManager_depositFromSpot(address account, uint256 amount) public asActor {
        perpManager.depositFromSpot(account, amount);
    }

    function perpManager_depositTo(address account, uint256 amount) public asActor {
        perpManager.depositTo(account, amount);
    }

    function perpManager_disableCrossMargin(bytes32 asset) public asActor {
        perpManager.disableCrossMargin(asset);
    }

    function perpManager_disapproveOperator(address account, address operator, uint256 roles) public asActor {
        perpManager.disapproveOperator(account, operator, roles);
    }

    function perpManager_enableCrossMargin(bytes32 asset) public asActor {
        perpManager.enableCrossMargin(asset);
    }

    function perpManager_grantAdmin(address account) public asActor {
        perpManager.grantAdmin(account);
    }

    function perpManager_grantRoles(address user, uint256 roles) public payable asActor {
        perpManager.grantRoles{value: msg.value}(user, roles);
    }

    function perpManager_initialize(address owner_, uint16[] memory takerFees, uint16[] memory makerFees) public asActor {
        perpManager.initialize(owner_, takerFees, makerFees);
    }

    function perpManager_insuranceFundDeposit(uint256 amount) public asActor {
        perpManager.insuranceFundDeposit(amount);
    }

    function perpManager_insuranceFundWithdraw(uint256 amount) public asActor {
        perpManager.insuranceFundWithdraw(amount);
    }

    function perpManager_liquidate(bytes32 asset, address account, uint256 subaccount) public asActor {
        perpManager.liquidate(asset, account, subaccount);
    }

    function perpManager_placeOrder(address account, PlaceOrderArgs memory args) public asActor {
        perpManager.placeOrder(account, args);
    }

    function perpManager_placeTPSLOrder(address account, PlaceOrderArgs memory args, Condition memory condition, SignData memory signData) public asActor {
        perpManager.placeTPSLOrder(account, args, condition, signData);
    }

    function perpManager_placeTwapOrder(address account, PlaceOrderArgs memory args, SignData memory signData) public asActor {
        perpManager.placeTwapOrder(account, args, signData);
    }

    function perpManager_postLimitOrderBackstop(address account, PlaceOrderArgs memory args) public asActor {
        perpManager.postLimitOrderBackstop(account, args);
    }

    function perpManager_relistMarket(bytes32 asset) public asActor {
        perpManager.relistMarket(asset);
    }

    function perpManager_removeMargin(address account, uint256 subaccount, uint256 amount) public asActor {
        perpManager.removeMargin(account, subaccount, amount);
    }

    function perpManager_renounceOwnership() public payable asActor {
        perpManager.renounceOwnership{value: msg.value}();
    }

    function perpManager_renounceRoles(uint256 roles) public payable asActor {
        perpManager.renounceRoles{value: msg.value}(roles);
    }

    function perpManager_requestOwnershipHandover() public payable asActor {
        perpManager.requestOwnershipHandover{value: msg.value}();
    }

    function perpManager_revokeAdmin(address account) public asActor {
        perpManager.revokeAdmin(account);
    }

    function perpManager_revokeRoles(address user, uint256 roles) public payable asActor {
        perpManager.revokeRoles{value: msg.value}(user, roles);
    }

    function perpManager_setBookSettings(bytes32 asset, BookSettings memory settings) public asActor {
        perpManager.setBookSettings(asset, settings);
    }

    function perpManager_setDivergenceCap(bytes32 asset, uint256 divergenceCap) public asActor {
        perpManager.setDivergenceCap(asset, divergenceCap);
    }

    function perpManager_setFeeTiers(address[] memory accounts, FeeTier[] memory feeTiers) public asActor {
        perpManager.setFeeTiers(accounts, feeTiers);
    }

    function perpManager_setFundingClamps(bytes32 asset, uint256 innerClamp, uint256 outerClamp) public asActor {
        perpManager.setFundingClamps(asset, innerClamp, outerClamp);
    }

    function perpManager_setFundingInterval(bytes32 asset, uint256 fundingInterval, uint256 resetInterval) public asActor {
        perpManager.setFundingInterval(asset, fundingInterval, resetInterval);
    }

    function perpManager_setFundingRateSettings(bytes32 asset, FundingRateSettings memory settings) public asActor {
        perpManager.setFundingRateSettings(asset, settings);
    }

    function perpManager_setInterestRate(bytes32 asset, int256 interestRate) public asActor {
        perpManager.setInterestRate(asset, interestRate);
    }

    function perpManager_setLiquidationFeeRate(bytes32 asset, uint256 liquidationFeeRate) public asActor {
        perpManager.setLiquidationFeeRate(asset, liquidationFeeRate);
    }

    function perpManager_setLiquidatorPoints(address account, uint256 points) public asActor {
        perpManager.setLiquidatorPoints(account, points);
    }

    function perpManager_setMakerFeeRates(uint16[] memory makerFeeRates) public asActor {
        perpManager.setMakerFeeRates(makerFeeRates);
    }

    function perpManager_setMarkPrice(bytes32 asset, uint256 indexPrice) public asActor {
        perpManager.setMarkPrice(asset, indexPrice);
    }

    function perpManager_setMarketSettings(bytes32 asset, MarketSettings memory settings) public asActor {
        perpManager.setMarketSettings(asset, settings);
    }

    function perpManager_setMaxLeverage(bytes32 asset, uint256 maxOpenLeverage) public asActor {
        perpManager.setMaxLeverage(asset, maxOpenLeverage);
    }

    function perpManager_setMaxLimitsPerTx(bytes32 asset, uint8 maxLimitsPerTx) public asActor {
        perpManager.setMaxLimitsPerTx(asset, maxLimitsPerTx);
    }

    function perpManager_setMaxNumOrders(bytes32 asset, uint256 maxNumOrders) public asActor {
        perpManager.setMaxNumOrders(asset, maxNumOrders);
    }

    function perpManager_setMinLimitOrderAmountInBase(bytes32 asset, uint256 minLimitOrderAmountInBase) public asActor {
        perpManager.setMinLimitOrderAmountInBase(asset, minLimitOrderAmountInBase);
    }

    function perpManager_setMinMarginRatio(bytes32 asset, uint256 maintenanceMarginRatio) public asActor {
        perpManager.setMinMarginRatio(asset, maintenanceMarginRatio);
    }

    function perpManager_setPartialLiquidationRate(bytes32 asset, uint256 partialLiquidationRate) public asActor {
        perpManager.setPartialLiquidationRate(asset, partialLiquidationRate);
    }

    function perpManager_setPartialLiquidationThreshold(bytes32 asset, uint256 partialLiquidationThreshold) public asActor {
        perpManager.setPartialLiquidationThreshold(asset, partialLiquidationThreshold);
    }

    function perpManager_setPositionLeverage(bytes32 asset, address account, uint256 subaccount, uint256 newLeverage) public asActor {
        perpManager.setPositionLeverage(asset, account, subaccount, newLeverage);
    }

    function perpManager_setReduceOnlyCap(bytes32 asset, uint256 reduceOnlyCap) public asActor {
        perpManager.setReduceOnlyCap(asset, reduceOnlyCap);
    }

    function perpManager_setResetIterations(bytes32 asset, uint256 resetIterations) public asActor {
        perpManager.setResetIterations(asset, resetIterations);
    }

    function perpManager_setTakerFeeRates(uint16[] memory takerFeeRates) public asActor {
        perpManager.setTakerFeeRates(takerFeeRates);
    }

    function perpManager_setTickSize(bytes32 asset, uint256 tickSize) public asActor {
        perpManager.setTickSize(asset, tickSize);
    }

    function perpManager_settleFunding(bytes32 asset) public asActor {
        perpManager.settleFunding(asset);
    }

    function perpManager_transferOwnership(address newOwner) public payable asActor {
        perpManager.transferOwnership{value: msg.value}(newOwner);
    }

    function perpManager_withdraw(address account, uint256 amount) public asActor {
        perpManager.withdraw(account, amount);
    }

    function perpManager_withdrawToSpot(address account, uint256 amount) public asActor {
        perpManager.withdrawToSpot(account, amount);
    }
}