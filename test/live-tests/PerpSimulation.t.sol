// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {ERC1967Factory} from "@solady/utils/ERC1967Factory.sol";

import "contracts/perps/PerpManager.sol";

contract PerpSimulationTest is Test {
    using SafeTransferLib for address;

    ///  GTE  ///
    address deployer;
    ERC1967Factory factory;
    PerpManager perpManager;

    ///  EXTERNAL  ///
    address cap;

    ///  SIMULATION  ///
    address sender;
    address target;
    bytes data;

    // function setUp() public {
    //     deployer = vm.envOr("DEPLOYER", address(0));
    //     factory = ERC1967Factory(vm.envOr("GTE_FACTORY_TESTNET", address(0)));
    //     perpManager = PerpManager(vm.envOr("PERP_MANAGER_TESTNET", address(0)));

    //     if (deployer == address(0)) return;

    //     vm.createSelectFork("testnet");
    // }

    // function test_Simulation_Perp_HighLevel() public {
    //     // vm.prank(deployer);
    // }

    // function test_Simulation_Perp_LowLevel() public {
    //     // vm.startPrank(sender);

    //     // target.call(data);
    // }
}
