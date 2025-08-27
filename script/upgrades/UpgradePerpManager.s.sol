// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/Script.sol";

import {ERC1967Factory} from "@solady/utils/ERC1967Factory.sol";
import {PerpManager} from "contracts/perps/PerpManager.sol";

import {ScriptProtector} from "../ScriptProtector.s.sol";

contract UpgradePerpManagerScript is ScriptProtector {
    address perpManager;

    function run() external override SetupScript /* UpgradeSafePerpManager*/ {
        perpManager = vm.envAddress("PERP_MANAGER_TESTNET");
        address operatorHub = vm.envAddress("OPERATOR_HUB_TESTNET");
        address spotAccountManager = vm.envAddress("SPOT_ACCOUNT_MANAGER_TESTNET");

        vm.createSelectFork("testnet");
        vm.startBroadcast(deployerPrivateKey);

        address perpManagerLogic = address(new PerpManager({
            _accountManager: spotAccountManager,
            _operatorHub: operatorHub
        }));

        (bool s,) =
            address(factory).call{gas: 800_000}(abi.encodeCall(ERC1967Factory.upgrade, (perpManager, perpManagerLogic)));

        vm.stopBroadcast();

        require(s, "upgrade failed");
    }
}
