// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {TestPlus} from "lib/solady/test/utils/TestPlus.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {ERC1967Factory} from "@solady/utils/ERC1967Factory.sol";
import {console} from "forge-std/console.sol";

import {MockBackstopLiquidationSettlement} from "../mock/MockBackstopLiquidationSettlement.sol";
import {AdminPanel} from "../../../contracts/perps/modules/AdminPanel.sol";

contract Perp_BackstopLiquidationSettlement_Test is Test, TestPlus {
    using FixedPointMathLib for *;

    bytes32 internal constant ETH = bytes32("ETH");

    MockBackstopLiquidationSettlement public mockBLS;

    uint16 internal constant MAKER_BASE_FEE_RATE = 1000;
    uint16 internal constant TAKER_BASE_FEE_RATE = 2000;

    ERC1967Factory internal factory;
    address[] internal makers;
    address[] internal takers;
    address internal admin = makeAddr("admin");
    uint16[] internal takerFees;
    uint16[] internal makerFees;

    function setUp() public {
        factory = new ERC1967Factory();

        takerFees.push(TAKER_BASE_FEE_RATE);
        makerFees.push(MAKER_BASE_FEE_RATE);

        address mockBLSLogic = address(new MockBackstopLiquidationSettlement());

        mockBLS = MockBackstopLiquidationSettlement(
            factory.deployAndCall({
                admin: admin,
                implementation: mockBLSLogic,
                data: abi.encodeCall(AdminPanel.initialize, (admin, takerFees, makerFees))
            })
        );

        for (uint256 i; i < 4; ++i) {
            makers.push(makeAddr(string(abi.encodePacked("maker", i))));
            takers.push(makeAddr(string(abi.encodePacked("taker", i))));
        }
    }

    function testFuzz_settleBackstopLiquidation(uint256) public {
        uint256 margin = _hem(_random(), 1, 100_000e18);
        uint256[] memory volumes = new uint256[](4);
        uint256[] memory points = new uint256[](4);
        uint256 totalVolume;
        uint256 totalPoints;

        vm.startPrank(admin);
        for (uint256 i; i < 4; ++i) {
            volumes[i] = _hem(_random(), 1, 1_000_000e18);
            points[i] = _hem(_random(), 1, 1000e18);
            totalVolume += volumes[i];
            totalPoints += points[i];

            mockBLS.addLiquidatorVolume(makers[i], volumes[i]);
            mockBLS.setLiquidatorPoints(makers[i], points[i]);
        }

        uint256[] memory weights = new uint256[](4);
        for (uint256 i; i < 4; ++i) {
            weights[i] = (volumes[i].fullMulDiv(1e18, totalVolume) + points[i].fullMulDiv(1e18, totalPoints)) / 2;
        }

        vm.stopPrank();

        uint256 liquidationFee = mockBLS.settleBackstopLiquidation(ETH, margin);
        uint256 totalCredits;
        for (uint256 i; i < 4; ++i) {
            uint256 credit = mockBLS.getFreeCollateralBalance(makers[i]);
            assertEq(credit, (margin - liquidationFee).fullMulDiv(weights[i], 1e18));
            totalCredits += credit;
        }

        assertApproxEqAbs(totalCredits + liquidationFee, margin, 0.0001 ether, "total credits wrong");
        assertGt(margin, totalCredits + liquidationFee, "insolvent");
    }

    function test_settleBackstopLiquidation() public {
        uint256 margin = 50_000e18;
        uint256[] memory volumes = new uint256[](4);
        uint256[] memory points = new uint256[](4);
        uint256[] memory credits = new uint256[](4);

        // total Points : 6_710e18
        points[0] = 300e18;
        points[1] = 2560e18;
        points[2] = 1350e18;
        points[3] = 2500e18;
        // total Volume : 5_465_000e18
        volumes[0] = 135_000e18;
        volumes[1] = 1_100_000e18;
        volumes[2] = 670_000e18;
        volumes[3] = 3_560_000e18;
        // blended average rates == ( points/totalPoints + volumes/totalVolumes ) / 2
        // credits == (margin - liquidationFees) * rates
        credits[0] = 1_735_301_055_490_637_450_000;
        credits[1] = 14_570_024_938_539_929_550_000;
        credits[2] = 8_094_765_088_225_709_450_000;
        credits[3] = 25_599_908_917_743_723_400_000;
        // dust artifacts from fixed point math
        uint256 totalCredits = 49_999_999_999_999_999_850_000;

        vm.startPrank(admin);
        for (uint256 i; i < 4; ++i) {
            mockBLS.addLiquidatorVolume(makers[i], volumes[i]);
            mockBLS.setLiquidatorPoints(makers[i], points[i]);
        }
        vm.stopPrank();

        uint256 liquidationFee = mockBLS.settleBackstopLiquidation(ETH, margin);

        for (uint256 i; i < 4; ++i) {
            assertEq(mockBLS.getFreeCollateralBalance(makers[i]), credits[i]);
        }
        assertApproxEqAbs(totalCredits + liquidationFee, margin, 0.0001 ether, "total credits wrong");
        assertGt(margin, totalCredits + liquidationFee, "insolvent");
    }
}
