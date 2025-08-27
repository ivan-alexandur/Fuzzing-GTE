// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import {TestPlus} from "lib/solady/test/utils/TestPlus.sol";

import {MockPriceHistory} from "../mock/MockPriceHistory.sol";

// @todo vwap

/// @notice tests PriceHistory's twap function
contract PriceHistoryTest is Test, TestPlus {
    MockPriceHistory priceHistory;

    function setUp() public {
        priceHistory = new MockPriceHistory();
        vm.warp(5 days);
    }

    function test_Perp_Twap(uint256) public {
        uint256 iterations = _hem(_randomUnique(), 1, 100);

        uint256 price;
        uint256 weightedPrice;
        uint256 timePeriod;
        uint256 elapsedTime;
        for (uint256 i; i < iterations; ++i) {
            price = _hem(_randomUnique(), 5 ether, 200_000 ether);

            priceHistory.snapshot(price);

            elapsedTime += timePeriod = _hem(_randomUnique(), 30, 10 minutes);

            vm.warp(vm.getBlockTimestamp() + timePeriod);

            weightedPrice += price * timePeriod;
        }

        uint256 twap = weightedPrice / elapsedTime;

        assertEq(priceHistory.twap(elapsedTime), twap);
    }
}
