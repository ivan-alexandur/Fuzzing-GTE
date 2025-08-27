// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import {ERC1967Factory} from "@solady/utils/ERC1967Factory.sol";
import {Launchpad} from "contracts/launchpad/Launchpad.sol";

contract UpgradeLaunchpadTest is Test {
    address deployer;

    ERC1967Factory factory;
    address clobManager;
    Launchpad launchpad;
    address gteRouter;
    address uniV2Router;
    address launchpadLPVault;

    function setUp() public {
        deployer = vm.envOr("DEPLOYER", address(0));

        factory = ERC1967Factory(vm.envOr("GTE_FACTORY_TESTNET", address(0)));
        clobManager = vm.envOr("CLOB_FACTORY_TESTNET", address(0));
        launchpad = Launchpad(vm.envOr("GTE_LAUNCHPAD_TESTNET", address(0)));
        gteRouter = vm.envOr("GTE_ROUTER_TESTNET", address(0));
        uniV2Router = vm.envOr("UNIV2_VANILLA_ROUTER_TESTNET", address(0));
        launchpadLPVault = vm.envOr("GTE_LAUNCHPAD_LP_VAULT_TESTNET", address(0));

        if (address(deployer) == address(0)) return;

        vm.createSelectFork("testnet");
    }

    function est_UpgradeLaunchpad() public {
        if (deployer == address(0)) return;

        //        address launchpadLogic = address(new Launchpad(uniV2Router, gteRouter, clobManager));

        //vm.prank(deployer);
        //factory.upgrade(address(launchpad), launchpadLogic);
    }
}
