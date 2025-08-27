// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {BackstopLiquidatorDataHarness, LiquidatorData} from "../../mock/BackstopLiquidatorDataHarness.sol";
import {BackstopLiquidatorDataLib} from "contracts/perps/types/BackstopLiquidatorDataLib.sol";

import {Test} from "forge-std/Test.sol";
import {TestPlus} from "lib/solady/test/utils/TestPlus.sol";

contract BackstopLiquidatorDataLibTest is Test, TestPlus {
    address[] liquidatorsAddr;

    BackstopLiquidatorDataHarness backstopLiquidatorData;

    function setUp() public {
        backstopLiquidatorData = new BackstopLiquidatorDataHarness();

        liquidatorsAddr.push(makeAddr("liquidator1"));
        liquidatorsAddr.push(makeAddr("liquidator2"));
        liquidatorsAddr.push(makeAddr("liquidator3"));
    }

    function test_EmptyState() public {
        LiquidatorData[] memory liquidatorData = backstopLiquidatorData.getLiquidatorData();
        assertEq(liquidatorData.length, 0, "empty state should return no data");

        address[] memory liquidators = backstopLiquidatorData.getLiquidators();
        assertEq(liquidators.length, 0, "empty state should return no liquidators");
    }

    function test_ZeroVolumeAddition() public {
        backstopLiquidatorData.addVolume(liquidatorsAddr[0], 0);

        LiquidatorData[] memory liquidatorData = backstopLiquidatorData.getLiquidatorData();

        assertEq(liquidatorData.length, 1, "zero volume should still create entry");
        assertEq(liquidatorData[0].liquidator, liquidatorsAddr[0], "liquidator address wrong");
        assertEq(liquidatorData[0].volume, 0, "zero volume should be preserved");
    }

    function test_NoDuplicateLiquidators_MultipleAdds(uint256) public {
        address liquidator = _randomUniqueAddress();

        backstopLiquidatorData.addVolume(liquidator, 500);
        backstopLiquidatorData.addVolume(liquidator, 1000);
        backstopLiquidatorData.addVolume(liquidator, 2000);

        address[] memory liquidators = backstopLiquidatorData.getLiquidators();

        assertEq(liquidators.length, 1, "duplicate liquidator");
        assertEq(liquidators[0], liquidator, "liquidator address wrong");
    }

    function test_IdempotentClearing() public {
        uint256 volume = 1000;

        backstopLiquidatorData.addVolume(liquidatorsAddr[0], volume);

        LiquidatorData[] memory liquidatorData1 = backstopLiquidatorData.getLiquidatorData();
        assertEq(liquidatorData1.length, 1, "first call length wrong");
        assertEq(liquidatorData1[0].liquidator, liquidatorsAddr[0], "first call liquidator wrong");
        assertEq(liquidatorData1[0].volume, volume, "first call volume wrong");

        LiquidatorData[] memory liquidatorData2 = backstopLiquidatorData.getLiquidatorData();
        assertEq(liquidatorData2.length, 0, "second call should be empty");
    }

    function testFuzz_SingleLiquidator(uint256) public {
        address liquidator = _randomUniqueAddress();
        uint256 volume1 = _hem(_random(), 0, type(uint128).max);
        uint256 volume2 = _hem(_random(), 0, type(uint128).max);

        backstopLiquidatorData.addVolume(liquidator, volume1);
        backstopLiquidatorData.addVolume(liquidator, volume2);

        LiquidatorData[] memory liquidatorData = backstopLiquidatorData.getLiquidatorData();

        assertEq(liquidatorData.length, 1, "should have exactly one liquidator");
        assertEq(liquidatorData[0].liquidator, liquidator, "liquidator address wrong");
        assertEq(liquidatorData[0].volume, volume1 + volume2, "volume aggregation wrong");

        assertEq(backstopLiquidatorData.getLiquidators().length, 0, "liquidators not cleared");
        assertEq(backstopLiquidatorData.getVolume(liquidator), 0, "volume not cleared");
    }

    function testFuzz_VariableLiquidatorCount(uint256) public {
        uint256 numLiquidators = _hem(_random(), 0, 10);

        if (numLiquidators == 0) {
            // Test empty case
            LiquidatorData[] memory emptyData = backstopLiquidatorData.getLiquidatorData();
            assertEq(emptyData.length, 0, "empty case should return no data");
            return;
        }

        address[] memory testLiquidators = new address[](numLiquidators);
        uint256[] memory expectedVolumes = new uint256[](numLiquidators);

        for (uint256 i = 0; i < numLiquidators; i++) {
            testLiquidators[i] = _randomUniqueAddress();
            expectedVolumes[i] = 0;
        }

        uint256 maxVolume = type(uint64).max;

        for (uint256 i = 0; i < numLiquidators; i++) {
            uint256 numAdds = _hem(_random(), 1, 5);

            for (uint256 j = 0; j < numAdds; j++) {
                uint256 volume = _hem(_random(), 1, maxVolume);
                backstopLiquidatorData.addVolume(testLiquidators[i], volume);
                expectedVolumes[i] += volume;
            }
        }

        LiquidatorData[] memory liquidatorData = backstopLiquidatorData.getLiquidatorData();

        assertEq(liquidatorData.length, numLiquidators, "length wrong");

        bool[] memory found = new bool[](numLiquidators);

        for (uint256 i = 0; i < liquidatorData.length; i++) {
            bool matchFound = false;
            for (uint256 j = 0; j < numLiquidators; j++) {
                if (liquidatorData[i].liquidator == testLiquidators[j]) {
                    assertEq(
                        liquidatorData[i].volume,
                        expectedVolumes[j],
                        string(abi.encodePacked("liquidator", j, " volume wrong"))
                    );
                    assertFalse(found[j], string(abi.encodePacked("duplicate liquidator", j)));
                    found[j] = true;
                    matchFound = true;
                    break;
                }
            }
            assertTrue(matchFound, "unknown liquidator found");
        }

        for (uint256 i = 0; i < numLiquidators; i++) {
            assertTrue(found[i], string(abi.encodePacked("liquidator", i, " not found")));
        }

        assertEq(backstopLiquidatorData.getLiquidators().length, 0, "liquidators not cleared");
        for (uint256 i = 0; i < numLiquidators; i++) {
            assertEq(
                backstopLiquidatorData.getVolume(testLiquidators[i]),
                0,
                string(abi.encodePacked("liquidator", i, " volume not cleared"))
            );
        }
    }
}
