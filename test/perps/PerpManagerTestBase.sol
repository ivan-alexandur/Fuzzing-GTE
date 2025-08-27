// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/Test.sol";
import {TestUSDC} from "./mock/TestUSDC.sol";
import {TestPlus} from "../../lib/solady/test/utils/TestPlus.sol";

import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";
import {ERC1967Factory} from "@solady/utils/ERC1967Factory.sol";

import "../../contracts/perps/types/Enums.sol";
import "../../contracts/perps/types/Structs.sol";

import {Order} from "../../contracts/perps/types/Order.sol";
import {Position} from "../../contracts/perps/types/Position.sol";

import {MockPerpManager} from "./mock/MockPerpManager.sol";

import {PerpManager} from "../../contracts/perps/PerpManager.sol";
import {GTL} from "../../contracts/perps/GTL.sol";
import {AdminPanel} from "../../contracts/perps/modules/AdminPanel.sol";
import {OperatorPanel} from "../../contracts/utils/OperatorPanel.sol";
import {ClearingHouseLib} from "../../contracts/perps/types/ClearingHouse.sol";
import {CLOBLib} from "../../contracts/perps/types/CLOBLib.sol";

contract PerpManagerTestBase is Test, TestPlus {
    using FixedPointMathLib for *;

    ERC1967Factory internal factory;

    MockPerpManager internal perpManager;
    GTL internal gtl;

    TestUSDC internal usdc = TestUSDC(0xE9b6e75C243B6100ffcb1c66e8f78F96FeeA727F);

    bytes32 internal constant ETH = bytes32("ETH");
    bytes32 internal constant GTE = bytes32("GTE");
    bytes32 internal constant BTC = bytes32("BTC");

    address internal admin = makeAddr("admin");
    address internal rite = makeAddr("rite");
    address internal jb = makeAddr("jb");
    address internal nate = makeAddr("nate");
    address internal julien = makeAddr("julien");
    address internal moses = makeAddr("moses");

    uint16 internal constant MAKER_BASE_FEE_RATE = 1000;
    uint16 internal constant TAKER_BASE_FEE_RATE = 2000;

    uint16[] internal takerFees;
    uint16[] internal makerFees;

    function setUp() public virtual {
        factory = new ERC1967Factory();

        takerFees.push(TAKER_BASE_FEE_RATE);
        makerFees.push(MAKER_BASE_FEE_RATE);

        address perpManagerLogic = address(new MockPerpManager(address(0)));

        perpManager = MockPerpManager(
            factory.deployAndCall({
                admin: admin,
                implementation: perpManagerLogic,
                data: abi.encodeCall(AdminPanel.initialize, (admin, takerFees, makerFees))
            })
        );

        vm.prank(admin);
        perpManager.activateProtocol();

        deployCodeTo("TestUSDC.sol", 0xE9b6e75C243B6100ffcb1c66e8f78F96FeeA727F);

        address gtlLogic = address(new GTL(address(usdc), address(perpManager)));

        vm.prank(admin);
        gtl = GTL(factory.deployAndCall(gtlLogic, admin, abi.encodeCall(GTL.initialize, (admin))));

        _createMarket(ETH, 4000e18, true);
        _createMarket(GTE, 5e18, false);
        _createMarket(BTC, 100_000e18, true);
        _mintAndApproveAndDeposit();
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            ORDER HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _placeTrade(
        bytes32 asset,
        address taker,
        address maker,
        uint256 price,
        uint256 amount,
        Side side,
        uint256 subaccount
    ) internal {
        uint256 id = _createLimitOrder({
            asset: asset,
            maker: maker,
            subaccount: subaccount,
            price: price,
            amount: amount,
            side: side == Side.BUY ? Side.SELL : Side.BUY
        });

        vm.startPrank(taker);

        perpManager.deposit(
            taker,
            amount.fullMulDiv(price, 1e18).fullMulDiv(1e18, perpManager.getPositionLeverage(asset, taker, subaccount))
        );

        PlaceOrderArgs memory takerArgs = PlaceOrderArgs({
            subaccount: subaccount,
            asset: asset,
            side: side,
            limitPrice: price,
            amount: amount,
            baseDenominated: true,
            tif: TiF.IOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        perpManager.placeOrder(taker, takerArgs);

        vm.stopPrank();

        // clear remaining order if it exists
        if (perpManager.getLimitOrder(asset, 1).amount != 0) {
            uint256[] memory orderIds = new uint256[](1);
            orderIds[0] = id;

            vm.prank(maker);
            perpManager.cancelLimitOrders({asset: ETH, account: maker, subaccount: subaccount, orderIds: orderIds});
        }
    }

    function _createLimitOrder(
        bytes32 asset,
        address maker,
        uint256 subaccount,
        uint256 price,
        uint256 amount,
        Side side
    ) internal returns (uint256 orderId) {
        vm.startPrank(maker);

        perpManager.deposit(
            maker,
            amount.fullMulDiv(price, 1e18).fullMulDiv(1e18, perpManager.getPositionLeverage(asset, maker, subaccount))
        );

        PlaceOrderArgs memory makerArgs = PlaceOrderArgs({
            subaccount: subaccount,
            asset: asset,
            side: side,
            limitPrice: price,
            amount: amount,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        orderId = perpManager.placeOrder(maker, makerArgs).orderId;

        vm.stopPrank();
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                             SET UP HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _createMarket(bytes32 asset, uint256 price, bool crossMarginEnabled) internal {
        MarketParams memory marketParams = MarketParams({
            maxOpenLeverage: 50 ether, // 50x
            maintenanceMarginRatio: 0.01 ether, // 1%
            liquidationFeeRate: 0.01 ether, // 1%
            divergenceCap: 1 ether, // 100%
            reduceOnlyCap: 4,
            partialLiquidationThreshold: type(uint256).max, // max = no partial liquidation
            partialLiquidationRate: 0.2 ether, // 20% of position
            fundingInterval: 1 hours,
            resetInterval: 30 minutes,
            resetIterations: 5,
            innerClamp: 0.01 ether,
            outerClamp: 0.02 ether,
            interestRate: 0.005 ether,
            maxNumOrders: 1_000_000,
            maxLimitsPerTx: 40,
            minLimitOrderAmountInBase: 0.001 ether,
            lotSize: 0.001 ether,
            tickSize: 0.001 ether,
            initialPrice: price,
            crossMarginEnabled: crossMarginEnabled
        });

        vm.startPrank(admin);
        perpManager.createMarket({asset: asset, params: marketParams});
        perpManager.activateMarket(asset);
        vm.stopPrank();
    }

    function _mintAndApproveAndDeposit() private {
        usdc.mint(admin, 100_000_000_000e18);
        usdc.mint(rite, 100_000_000_000e18);
        usdc.mint(jb, 100_000_000_000e18);
        usdc.mint(nate, 100_000_000_000e18);
        usdc.mint(julien, 100_000_000_000e18);
        usdc.mint(moses, 100_000_000_000e18);

        vm.startPrank(admin);
        usdc.approve(address(perpManager), type(uint256).max);
        usdc.approve(address(gtl), type(uint256).max);
        vm.startPrank(rite);
        usdc.approve(address(perpManager), type(uint256).max);
        usdc.approve(address(gtl), type(uint256).max);
        perpManager.deposit(rite, 50_000_000e18);
        vm.startPrank(jb);
        usdc.approve(address(perpManager), type(uint256).max);
        usdc.approve(address(gtl), type(uint256).max);
        perpManager.deposit(jb, 50_000_000e18);
        vm.startPrank(nate);
        usdc.approve(address(perpManager), type(uint256).max);
        usdc.approve(address(gtl), type(uint256).max);
        vm.startPrank(julien);
        usdc.approve(address(perpManager), type(uint256).max);
        usdc.approve(address(gtl), type(uint256).max);
        vm.startPrank(moses);
        usdc.approve(address(perpManager), type(uint256).max);
        usdc.approve(address(gtl), type(uint256).max);
        vm.stopPrank();
    }

    function _mintAndApprove(address user, uint256 amount) internal {
        vm.startPrank(user);
        usdc.mint(user, amount);
        usdc.approve(address(perpManager), usdc.allowance(user, address(perpManager)) + amount);
        vm.stopPrank();
    }

    function _mintAndApproveAndDeposit(address user, uint256 amount) internal {
        _mintAndApprove(user, amount);
        vm.prank(user);
        perpManager.deposit(user, amount);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            MISC HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _generateRandomPosition(bytes32 asset) internal returns (Position memory p) {
        uint256 openMarkPrice = _hem(_random(), 1e18, 500_000e18);

        p.amount = _conformLots(asset, _hem(_random(), 1e18, 1000e18));
        p.openNotional = p.amount.fullMulDiv(openMarkPrice, 1e18);
        p.leverage = _hem(_random(), 1e18, 50e18);
        p.isLong = _randomChance(2);
    }

    function _conformTick(bytes32 asset, uint256 price) internal view returns (uint256) {
        uint256 tickSize = perpManager.getTickSize(asset);

        if (price % tickSize == 0) return price;
        if (price < tickSize) return tickSize;

        return price - (price % tickSize);
    }

    function _conformLots(bytes32 asset, uint256 amount) internal view returns (uint256) {
        uint256 lotSize = perpManager.getLotSize(asset);

        if (amount % lotSize == 0) return amount;
        if (amount < lotSize) return lotSize;

        return amount - (amount % lotSize);
    }

    function _conformLotsEth(uint256 amount) internal view returns (uint256) {
        uint256 lotSize = perpManager.getLotSize(ETH);
        return amount / lotSize * lotSize;
    }

    function _conformTickEth(uint256 price) internal view returns (uint256) {
        uint256 tickSize = perpManager.getTickSize(ETH);
        if (price % tickSize == 0) return price;
        return price - (price % tickSize);
    }
}
