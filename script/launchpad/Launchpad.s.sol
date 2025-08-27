// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {Launchpad} from "contracts/launchpad/Launchpad.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";

contract LaunchpadScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address uniV2Router = address(0);
        address usdc = address(0);

        if (block.chainid == 6342) {
            usdc = vm.envAddress("USDC_TESTNET");
            uniV2Router = vm.envAddress("UNIV2_VANILLA_ROUTER_TESTNET");
        } else {
            revert("unsupported chain");
        }

        if (usdc > address(0) && MockERC20(usdc).decimals() != 18) {
            revert("unsupported decimals. Launchpad is currently hardcoded for quote to be 18 decimals like capUSDC");
        }

        // Launchpad l = new Launchpad(uniV2Router, address(0), address(0)); // here

        /// Initial cap of $80k 18 decimal usdc
        // l.updateQuoteAsset(usdc, 125 * 1e2);
    }
}
