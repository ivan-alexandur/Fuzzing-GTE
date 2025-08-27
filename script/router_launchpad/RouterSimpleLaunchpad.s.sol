// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {Launchpad} from "contracts/launchpad/Launchpad.sol";
import {SimpleBondingCurve as Curve} from "contracts/launchpad/BondingCurves/SimpleBondingCurve.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {ERC1967Factory} from "@solady/utils/ERC1967Factory.sol";
import {GTERouter} from "contracts/router/GTERouter.sol";

contract LaunchpadScript is Script {
    address uniV2Router;
    address weth;
    Launchpad launchpad;
    Curve bondingCurve;
    ERC1967Factory factory;
    GTERouter router;
    address permit2;

    bytes32 routerSalt;
    bytes32 launchpadSalt;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.envAddress("DEPLOYER");
        factory = ERC1967Factory(vm.envAddress("GTE_FACTORY_TESTNET"));

        routerSalt = bytes32(bytes.concat(abi.encodePacked(deployer), keccak256("GTE.V1.TESTNET.ROUTER.SALT")));
        launchpadSalt =
            bytes32(bytes.concat(abi.encodePacked(deployer), keccak256("GTE.V1.TESTNET.LAUNCHPAD.SALT")));

        vm.startBroadcast(deployerPrivateKey);

        router = GTERouter(payable(factory.predictDeterministicAddress(routerSalt)));
        launchpad = Launchpad(factory.predictDeterministicAddress(launchpadSalt));

        if (block.chainid == 6342) {
            weth = vm.envAddress("WETH_TESTNET");
            uniV2Router = vm.envAddress("UNIV2_VANILLA_ROUTER_TESTNET");
            permit2 = vm.envAddress("PERMIT2_TESTNET");
        } else {
            revert("unsupported chain");
        }

        if (weth != address(0) && MockERC20(weth).decimals() != 18) revert("unsupported decimals");

        address bondingCurveLogic = address(new Curve(address(launchpad)));

        bondingCurve = Curve(factory.deploy({implementation: bondingCurveLogic, admin: deployer}));

        // TODO add factory
        //address launchpad_logic = address(new Launchpad(uniV2Router, address(router)));

        // Launchpad(
        //     factory.deployDeterministicAndCall({
        //         implementation: launchpad_logic,
        //         admin: deployer,
        //         salt: launchpadSalt,
        //         data: abi.encodeCall(
        //             Launchpad.initialize, (deployer, weth, address(bondingCurve), 200_000_000 ether, 10 ether)
        //         )
        //     })
        // );

        // TODO: Update GTERouter constructor after operator refactoring
        address router_logic = address(
            new GTERouter(
                payable(0), address(launchpad), address(0), address(0), address(uniV2Router), address(permit2)
            )
        );

        factory.deployDeterministic({implementation: router_logic, admin: deployer, salt: routerSalt});

        vm.stopBroadcast();

        console.log("launchpad", address(launchpad));
        console.log("router", address(router));
        console.log("factory (this is how we upgrade)", address(factory));
    }
}
