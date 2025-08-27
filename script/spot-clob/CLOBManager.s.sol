// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/Script.sol";

import {ERC1967Factory} from "@solady/utils/ERC1967Factory.sol";
import {CLOBManager} from "contracts/clob/CLOBManager.sol";
import {CLOB} from "contracts/clob/CLOB.sol";
import {AccountManager} from "contracts/account-manager/AccountManager.sol";
import {UpgradeableBeacon} from "@openzeppelin/proxy/beacon/UpgradeableBeacon.sol";

contract CLOBManagerScript is Script {
    ERC1967Factory factory;
    address clobManager;
    address accountManager;
    address gteRouter;
    address clobLogic;
    UpgradeableBeacon beacon;
    address operatorHub;
    address perpManager;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey); // Get the address from the private key

        factory = ERC1967Factory(vm.envAddress("GTE_FACTORY_TESTNET"));
        gteRouter = vm.envAddress("GTE_ROUTER_TESTNET");
        operatorHub = vm.envAddress("OPERATOR_HUB_TESTNET");
        perpManager = vm.envAddress("PERP_MANAGER_TESTNET");

        vm.createSelectFork("testnet");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy CLOB logic and beacon (with correct addresses from start)
        clobLogic = address(new CLOB(address(0), gteRouter, address(0), 2_147_483_647));
        beacon = new UpgradeableBeacon(clobLogic, deployer);

        // Setup fee tiers
        uint16[] memory makerFees = new uint16[](2);
        uint16[] memory takerFees = new uint16[](2);
        makerFees[0] = 750; // .75 bps
        makerFees[1] = 375; // .375 bps
        takerFees[0] = 7500; // 7.5 bps
        takerFees[1] = 3750; // 3.75 bps

        // Step 1: Deploy CLOBManager with dummy AccountManager (address(0))
        address tempClobManagerLogic = address(new CLOBManager(address(beacon), address(0)));

        clobManager =
            factory.deployAndCall(tempClobManagerLogic, deployer, abi.encodeCall(CLOBManager.initialize, (deployer)));

        // Step 2: Deploy AccountManager with the actual CLOBManager address
        address accountManagerLogic = address(new AccountManager(gteRouter, clobManager, operatorHub, makerFees, takerFees, perpManager));

        accountManager =
            factory.deployAndCall(accountManagerLogic, deployer, abi.encodeCall(AccountManager.initialize, (deployer)));

        // Step 3: Upgrade CLOBManager with the correct AccountManager address
        address finalClobManagerLogic = address(new CLOBManager(address(beacon), accountManager));
        factory.upgrade(clobManager, finalClobManagerLogic);

        // Step 4: Upgrade CLOB beacon with the correct addresses
        clobLogic = address(new CLOB(accountManager, gteRouter, clobManager, 2_147_483_647));
        beacon.upgradeTo(clobLogic);

        vm.stopBroadcast();

        console.log("CLOBManager:", clobManager);
        console.log("AccountManager:", accountManager);
        console.log("CLOB beacon:", address(beacon));
    }
}
