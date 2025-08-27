// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {PriceHistory} from "../../../contracts/perps/types/PriceHistory.sol";

contract MockPriceHistory {
    PriceHistory priceHistory;

    function snapshot(uint256 price) external {
        priceHistory.snapshot(price);
    }

    function twap(uint256 twapInterval) external view returns (uint256) {
        return priceHistory.twap(twapInterval);
    }
}
