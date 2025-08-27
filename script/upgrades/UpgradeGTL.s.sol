// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/Script.sol";

import {GTL} from "contracts/perps/GTL.sol";

import {ScriptProtector, ERC1967Factory} from "../ScriptProtector.s.sol";

contract UpgradeGTLScript is ScriptProtector {
    GTL gtl;

    function run() external override /* ensureValidScript */ {
        deployer = vm.envAddress("DEPLOYER");
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address perpManager = vm.envAddress("PerpManager_TESTNET");
        address usdc = vm.envAddress("USDC_TESTNET");
        gtl = GTL(vm.envAddress("GTL_TESTNET"));

        factory = ERC1967Factory(vm.envAddress("GTE_FACTORY_TESTNET"));

        vm.createSelectFork("testnet");

        vm.startBroadcast(deployerPrivateKey);

        address gtlLogic = address(new GTL(usdc, perpManager));

        (bool s,) =
            address(factory).call{gas: 800_000}(abi.encodeCall(ERC1967Factory.upgrade, (address(gtl), gtlLogic)));

        require(s, "upgrade failed");
    }
}
