// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoCTestBase} from "./PoCTestBase.t.sol";

contract PoC is PoCTestBase {
    /**
     * PoC can utilize the following variables to access the relevant contracts:
     * ================LAUNCHPAD================
     * - launchpad: Launchpad.sol
     * - distributor: Distributor.sol
     * - curve: SimpleBondingCurve.sol
     * - launchpadLPVault: LaunchpadLPVault.sol
     * - quoteToken: Quote token used in Launchpad system
     * - uniV2Router: Uniswap V2 Router used in Launchpad system
     * ================PERPETUAL================
     * - factory: ERC1967Factory.sol 
     * - perpManager: MockPerpManager.sol (extends PerpManager.sol)
     * - gtl: GTL.sol 
     * - usdc: Test USDC within perpetual system
     * - ETH, GTE, BTC: Tickers for markets created
     */
    function test_submissionValidity() external {
    }
}
