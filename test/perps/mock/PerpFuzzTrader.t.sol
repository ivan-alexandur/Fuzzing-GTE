// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "../PerpManagerTestBase.sol";
import {PerpAnvilFuzzTrader} from "./PerpAnvilFuzzTrader.sol";

contract PerpFuzzTrader is PerpManagerTestBase {
    PerpAnvilFuzzTrader fuzzTrader;

    function setUp() public override {
        super.setUp();

        address[] memory accounts = new address[](4);
        accounts[0] = jb;
        accounts[1] = rite;
        accounts[2] = julien;
        accounts[3] = nate;

        fuzzTrader = new PerpAnvilFuzzTrader(address(perpManager), ETH, BTC, accounts);

        vm.label(address(fuzzTrader), "FuzzTrader");

        vm.startPrank(rite);
        perpManager.approveOperator(rite, address(fuzzTrader), 1 << 0);
        perpManager.deposit(rite, usdc.balanceOf(rite));
        vm.startPrank(jb);
        perpManager.approveOperator(jb, address(fuzzTrader), 1 << 0);
        perpManager.deposit(jb, usdc.balanceOf(jb));
        vm.startPrank(julien);
        perpManager.approveOperator(julien, address(fuzzTrader), 1 << 0);
        perpManager.deposit(julien, usdc.balanceOf(julien));
        vm.startPrank(nate);
        perpManager.approveOperator(nate, address(fuzzTrader), 1 << 0);
        perpManager.deposit(nate, usdc.balanceOf(nate));
        vm.stopPrank();

        vm.prank(admin);
        perpManager.setMaxLimitsPerTx(ETH, type(uint8).max);
    }

    function test_Fuzz_Trade(uint256 rand) public {
        fuzzTrader.fuzzTrade(rand, 256 / 4);
    }
}
