// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/Script.sol";

import {ERC1967Factory} from "@solady/utils/ERC1967Factory.sol";
import {SimpleBondingCurve} from "contracts/launchpad/BondingCurves/SimpleBondingCurve.sol";
import {ScriptProtector} from "../ScriptProtector.s.sol";

contract UpgradeBondingCurveScript is ScriptProtector {
    function run() external override SetupScript {
        vm.startBroadcast(deployerPrivateKey);

        address bondingCurveLogic = address(new SimpleBondingCurve(launchpadProxy));

        (bool s,) = address(factory).call{gas: 800_000}(
            abi.encodeCall(ERC1967Factory.upgrade, (address(bondingCurve), bondingCurveLogic))
        );

        require(s, "upgrade failed");

        vm.stopBroadcast();
    }
}
