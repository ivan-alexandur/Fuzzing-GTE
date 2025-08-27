// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/Script.sol";

import {ERC1967Factory} from "@solady/utils/ERC1967Factory.sol";
import {Launchpad} from "contracts/launchpad/Launchpad.sol";
import {LaunchpadLPVault} from "contracts/launchpad/LaunchpadLPVault.sol";
import {ScriptProtector} from "../ScriptProtector.s.sol";

contract UpgradeLaunchpadScript is ScriptProtector {
    function run() external override SetupScript /*UpgradeSafeLaunchpadV0 */ {
        return;
        // vm.startBroadcast(deployerPrivateKey);

        address distributor = vm.envAddress("GTE_DISTRIBUTOR_TESTNET");

        address launchpadLogic =
            address(new Launchpad(uniV2Router, gteRouterProxy, clobManagerProxy, operatorProxy, distributor));

        // address launchpadLogic = address(new Launchpad(uniV2Router, gteRouterProxy, clobManagerProxy, operatorProxy, distributor));

        // (bool s,) = address(factory).call{gas: 800_000}(
        //     abi.encodeCall(ERC1967Factory.upgrade, (address(launchpadProxy), launchpadLogic))
        // );

        // require(s, "upgrade failed");

        // vm.stopBroadcast();
    }
}
