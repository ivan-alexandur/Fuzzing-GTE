// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {ERC1967Factory} from "@solady/utils/ERC1967Factory.sol";
import {Launchpad} from "contracts/launchpad/Launchpad.sol";
import {LaunchpadLPVault} from "contracts/launchpad/LaunchpadLPVault.sol";
import {SimpleBondingCurve} from "contracts/launchpad/BondingCurves/SimpleBondingCurve.sol";
import {GTERouter} from "contracts/router/GTERouter.sol";
import {UpgradeableBeacon} from "@openzeppelin/proxy/beacon/UpgradeableBeacon.sol";
import {Distributor} from "contracts/launchpad/Distributor.sol";

import "contracts/clob/CLOBManager.sol";
import "contracts/clob/CLOB.sol";
import "contracts/clob/ICLOB.sol";

interface IWETH {
    function deposit() external payable;
}

contract SimulationTest is Test {
    using SafeTransferLib for address;

    ///  GTE  ///
    address deployer;
    ERC1967Factory factory;
    Launchpad launchpad;
    LaunchpadLPVault launchpadLPVault;
    SimpleBondingCurve bondingCurve;
    GTERouter gteRouter;
    UpgradeableBeacon beacon;
    CLOBManager clobManager;

    Distributor distributor;

    ///  EXTERNAL  ///
    address weth;
    address uniV2Router;
    address permit2;

    ///  SIMULATION  ///
    address sender;
    address target;
    bytes data;
    bytes[] hops;

    function setUp() public {
        deployer = vm.envOr("DEPLOYER", address(0));

        factory = ERC1967Factory(vm.envOr("GTE_FACTORY_TESTNET", address(0)));
        bondingCurve = SimpleBondingCurve(vm.envOr("GTE_SIMPLE_BONDING_CURVE_TESTNET", address(0)));
        launchpad = Launchpad(vm.envOr("GTE_LAUNCHPAD_TESTNET", address(0)));
        launchpadLPVault = LaunchpadLPVault(vm.envOr("GTE_LAUNCHPAD_LP_VAULT_TESTNET", address(0)));
        gteRouter = GTERouter(payable(vm.envOr("GTE_ROUTER_TESTNET", address(0))));
        weth = vm.envOr("WETH_TESTNET", address(0));
        beacon = UpgradeableBeacon(vm.envOr("CLOB_BEACON_TESTNET", address(0)));
        clobManager = CLOBManager(vm.envOr("CLOB_MANAGER_TESTNET", address(0)));
        uniV2Router = vm.envOr("UNIV2_VANILLA_ROUTER_TESTNET", address(0));
        permit2 = vm.envOr("PERMIT2_TESTNET", address(0));
        distributor = Distributor(vm.envOr("DISTRIBUTOR_TESTNET", address(0)));

        if (address(beacon) == address(0)) return;

        vm.createSelectFork("testnet");

        _upgradeCLOBManager();
        _upgradeCLOB();
        _upgradeRouter();
        _upgradeLaunchpad();
    }

    /// @dev so the function doesn't without env
    modifier onlyFork() {
        if (block.timestamp == 1) return;
        _;
    }

    function test_Simulation_HighLevel() public onlyFork {
        // vm.rollFork();

        vm.startPrank(sender);
    }

    /// @dev 'data' should be: hex'<calldata with no leading 0x>'
    function test_Simulation_LowLevel() public onlyFork {
        // vm.rollFork();

        vm.startPrank(sender);

        // target.call(data);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                      FUNCTION / STRUCT TEMPLATES
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    // gteRouter.executeRoute({
    //     tokenIn: ,
    //     amountIn: ,
    //     amountOutMin: 0,
    //     deadline: ,
    //     isUnwrapping: ,
    //     settlementIn: ,
    //     hops: hops
    // });

    // ICLOB.PostFillOrderArgs memory fillArgs = ICLOB.PostFillOrderArgs({
    //     amount: ,
    //     priceLimit: ,
    //     side: ,
    //     amountIsBase: ,
    //     fillOrderType: ,
    //     settlement:
    // });

    // ICLOB.PostFillOrderArgs memory fillArgs = ICLOB.PostFillOrderArgs({
    //     amount: ,
    //     priceLimit: ,
    //     side: ,
    //     amountIsBase: ,
    //     fillOrderType: ,
    //     settlement:
    // });

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    // function _addCLOBHop(ICLOB clob, ICLOB.PostFillOrderArgs memory fillArgs) internal {
    //     hops.push(abi.encode(GTERouter.ClobHopArgs({hopType: GTERouter.HopType.CLOB_FILL, tokenOut: })))
    //     hops.push(bytes.concat(abi.encodePacked(GTERouterAPI.clobPostFillOrder.selector), abi.encode(clob, fillArgs)));
    // }
    function _addCLOBHop(ICLOB clob, ICLOB.PlaceOrderArgs memory orderArgs) internal {
        hops.push(bytes.concat(abi.encodePacked(GTERouter.clobPlaceOrder.selector), abi.encode(clob, orderArgs)));
    }

    // /// @dev 'path' is an array of token addresses, [tokenIn, tokenOut]
    // function _addUniHop(uint256 amountIn, uint256 amountOut, address[] memory path) internal {
    //     hops.push(
    //         bytes.concat(
    //             abi.encodePacked(GTERouterAPI.uniV2SwapExactTokensForTokens.selector),
    //             abi.encode(amountIn, amountOut, path)
    //         )
    //     );
    // }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            UPGRADE HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _upgradeCLOBManager() internal {
        uint16[] memory makerFees = new uint16[](2);
        uint16[] memory takerFees = new uint16[](2);

        makerFees[0] = 750; // .75 bps
        makerFees[1] = 375; // .375 bps
        takerFees[0] = 7500; // 7.5 bps
        takerFees[1] = 3750; // 3.75 bps

        address cmLogic = address(new CLOBManager(address(beacon), address(0)));

        vm.prank(deployer);
        factory.upgrade(address(clobManager), cmLogic);
    }

    function _upgradeCLOB() internal {
        // TODO: Update CLOB constructor signature after operator refactoring
        // address clobLogic = address(new CLOB(address(gteRouter), address(0), 1000, address(0), address(0)));

        // vm.prank(deployer);
        // beacon.upgradeTo(clobLogic);
    }

    function _upgradeRouter() internal {
        // TODO: Update GTERouter constructor after operator refactoring
        address routerLogic = address(
            new GTERouter(payable(weth), address(launchpad), address(0), address(clobManager), uniV2Router, permit2)
        );

        vm.prank(deployer);
        factory.upgrade(address(gteRouter), routerLogic);
    }

    function _upgradeLaunchpad() internal {
        address launchpadLogic = address(
            new Launchpad(uniV2Router, address(gteRouter), address(clobManager), address(0), address(distributor))
        );

        vm.prank(deployer);
        factory.upgrade(address(launchpad), launchpadLogic);
    }
}
