// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {Launchpad} from "contracts/launchpad/Launchpad.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {ERC1967Factory} from "@solady/utils/ERC1967Factory.sol";
import {GTERouter} from "contracts/router/GTERouter.sol";

contract LaunchpadScript is Script {
    address uniV2Router;
    address usdc;
    Launchpad l;
    ERC1967Factory factory;
    GTERouter router;
    address permit2;

    bytes32 routerSalt;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.envAddress("DEPLOYER");
        routerSalt = bytes32(abi.encode("GTE.V1.TESTNET.ROUTER.SALT", deployer));

        vm.startBroadcast(deployerPrivateKey);

        factory = new ERC1967Factory();

        router = GTERouter(payable(factory.predictDeterministicAddress(routerSalt)));

        if (block.chainid == 6342) {
            usdc = vm.envAddress("USDC_TESTNET");
            uniV2Router = vm.envAddress("UNIV2_VANILLA_ROUTER_TESTNET");
            permit2 = vm.envAddress("PERMIT2_TESTNET");
        } else {
            revert("unsupported chain");
        }

        if (usdc != address(0) && MockERC20(usdc).decimals() != 18) {
            revert("unsupported decimals. Launchpad is currently hardcoded for quote to be 18 decimals like capUSDC");
        }

        // address launchpad_logic = address(new Launchpad(uniV2Router, address(router)));

        // l = Launchpad(
        //     factory.deployAndCall({
        //         implementation: launchpad_logic,
        //         admin: deployer,
        //         data: abi.encodeCall(Launchpad.initialize, (deployer))
        //     })
        // );

        // address router_logic =
        //     address(new GTERouter(payable(0), address(l), address(0), address(uniV2Router), address(permit2)));

        // factory.deployDeterministic({implementation: router_logic, admin: deployer, salt: routerSalt});

        /// Initial cap of $80k 18 decimal usdc
        // l.updateQuoteAsset(address(usdc), 125 * 1e2);

        vm.stopBroadcast();

        console.log("launchpad", address(l));
        console.log("router", address(router));
        console.log("factory (this is how we upgrade)", address(factory));
    }
}
