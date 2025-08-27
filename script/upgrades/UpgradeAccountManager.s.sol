// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/Script.sol";

import {ERC1967Factory} from "@solady/utils/ERC1967Factory.sol";
import {AccountManager} from "contracts/account-manager/AccountManager.sol";

contract UpgradeAccountManagerScript is Script {
    function run() public {

        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        ERC1967Factory factory = ERC1967Factory(vm.envAddress("GTE_FACTORY_TESTNET"));

        address gteRouter = vm.envAddress("GTE_ROUTER_TESTNET");
        address operatorHub = vm.envAddress("OPERATOR_HUB_TESTNET");
        address clobManager = vm.envAddress("CLOB_MANAGER_TESTNET");
        address perpManager = vm.envAddress("PERP_MANAGER_TESTNET");
        address accountManager = vm.envAddress("SPOT_ACCOUNT_MANAGER_TESTNET");

        vm.createSelectFork("testnet");

        vm.startBroadcast(deployerPrivateKey);

        uint16[] memory makerFees = new uint16[](2);
        uint16[] memory takerFees = new uint16[](2);
        makerFees[0] = 750; // .75 bps
        makerFees[1] = 375; // .375 bps
        takerFees[0] = 7500; // 7.5 bps
        takerFees[1] = 3750; // 3.75 bps

        address accountManagerLogic = address(new AccountManager({
            _gteRouter: gteRouter,
            _clobManager: clobManager,
            _operatorHub: operatorHub,
            _spotMakerFees: makerFees,
            _spotTakerFees: takerFees,
            _perpManager: perpManager
        }));

        (bool s,) = address(factory).call{gas: 800_000}(
            abi.encodeCall(ERC1967Factory.upgrade, (accountManager, accountManagerLogic))
        );

        require(s, "upgrade failed");

        vm.stopBroadcast();
    }
}
