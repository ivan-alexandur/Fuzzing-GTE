// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import {ERC1967Factory} from "@solady/utils/ERC1967Factory.sol";
import {SimpleBondingCurve} from "contracts/launchpad/BondingCurves/SimpleBondingCurve.sol";

contract UpgradeSimpleBondingCurveTest is Test {
    address deployer;

    ERC1967Factory factory;
    SimpleBondingCurve bondingCurve;
    address launchpad;

    function setUp() public {
        deployer = vm.envOr("DEPLOYER", address(0));

        factory = ERC1967Factory(vm.envOr("GTE_FACTORY_TESTNET", address(0)));
        bondingCurve = SimpleBondingCurve(vm.envOr("GTE_SIMPLE_BONDING_CURVE_TESTNET", address(0)));
        launchpad = vm.envOr("GTE_LAUNCHPAD_TESTNET", address(0));

        if (address(deployer) == address(0)) return;

        vm.createSelectFork("testnet");
    }

    modifier envCheck( // for github actions
    ) {
        if (deployer == address(0)) return;
        _;
    }

    function est_UpgradeSimpleBondingCurve() public envCheck {
        if (deployer == address(0)) return;

        address bondingCurveLogic = address(new SimpleBondingCurve(launchpad));

        vm.prank(deployer);
        factory.upgrade(address(bondingCurve), bondingCurveLogic);
    }
}
