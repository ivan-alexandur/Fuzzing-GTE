// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/Script.sol";

import {ERC1967Factory} from "@solady/utils/ERC1967Factory.sol";
import {GTERouter} from "contracts/router/GTERouter.sol";

import {ScriptProtector} from "../ScriptProtector.s.sol";

contract UpgradeRouterScript is ScriptProtector {
    function run() external override SetupScript {
        vm.startBroadcast(deployerPrivateKey);

        // TODO: Update GTERouter constructor after operator refactoring
        address router_logic = address(
            new GTERouter(payable(weth), launchpadProxy, address(0), clobManagerProxy, uniV2Router, permit2)
        );

        (bool s,) = address(factory).call{gas: 800_000}(
            abi.encodeCall(ERC1967Factory.upgrade, (address(gteRouterProxy), router_logic))
        );

        require(s, "upgrade failed");

        vm.stopBroadcast();
    }
}
