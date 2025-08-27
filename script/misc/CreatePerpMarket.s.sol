// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/Script.sol";

import {PerpManager} from "contracts/perps/PerpManager.sol";
import {AdminPanel} from "contracts/perps/modules/AdminPanel.sol";
import {MarketParams} from "contracts/perps/types/Structs.sol";

contract CreatePerpMarketScript is Script {
    PerpManager perpManager;

    function run() external {
        /// ENV ///
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        perpManager = PerpManager(vm.envAddress("PERP_MANAGER_TESTNET"));

        /// PARAMS ///
        bytes32 assetId = "BTC";
        MarketParams memory marketParams = MarketParams({
            maxOpenLeverage: 50 ether, // 50x
            maintenanceMarginRatio: 0.01 ether, // 1%
            liquidationFeeRate: 0.01 ether, // 1%
            divergenceCap: 1 ether, // 100%
            reduceOnlyCap: 4,
            partialLiquidationThreshold: 20_000e18, // >= $20k value to partial liquidate
            partialLiquidationRate: 0.2 ether, // 20% of position
            fundingInterval: 1 hours,
            resetInterval: 30 minutes,
            resetIterations: 5,
            innerClamp: 0.01 ether,
            outerClamp: 0.02 ether,
            interestRate: 0.005 ether,
            maxNumOrders: 1_000_000, // 1m orders on book
            maxLimitsPerTx: 5,
            minLimitOrderAmountInBase: 0.001 ether,
            lotSize: 0.001 ether,
            tickSize: 0.001 ether,
            initialPrice: 100_000e18,
            crossMarginEnabled: true
        });

        /// SCRIPT START ///
        vm.createSelectFork("testnet");
        vm.startBroadcast(deployerPrivateKey);

        (bool s,) =
            address(perpManager).call{gas: 8_000_000}(abi.encodeCall(AdminPanel.createMarket, (assetId, marketParams)));

        vm.stopBroadcast();

        require(s, "PerpManager.createMarket failed");
    }
}
