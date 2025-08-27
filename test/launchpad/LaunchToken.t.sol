// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {LaunchToken} from "contracts/launchpad/LaunchToken.sol";

contract LaunchTokenTest is Test {
    address launcher = makeAddr("launcher");
    address gte_router = makeAddr("router");
    LaunchToken token;

    function setUp() public {
        vm.prank(launcher);
        token = new LaunchToken("LaunchToken", "LTN", "lemonparty.net", gte_router);

        vm.mockCall(launcher, abi.encodeWithSignature("increaseStake(address,uint96)"), abi.encode(true));
    }

    function testOnlyLauncher_ExpectRevert(address caller) public {
        vm.assume(caller != launcher);

        vm.startPrank(caller);

        vm.expectRevert(abi.encodeWithSignature("BadAuth()"));
        token.mint(0);

        vm.expectRevert(abi.encodeWithSignature("BadAuth()"));
        token.unlock();
    }

    function testBeforeTransferHook(address from, address to, uint256 amount) public {
        vm.assume(from != launcher && to != launcher);
        vm.assume(from != address(0) && to != address(0));
        vm.assume(from != gte_router && to != gte_router);
        vm.assume(amount <= type(uint96).max);

        vm.startPrank(launcher);
        token.mint(amount);
        token.transfer(from, amount); // direct buy simulation
        vm.stopPrank();

        vm.prank(from);
        token.transfer(launcher, amount); // direct sell simulation

        vm.prank(launcher);
        token.transfer(from, amount); // back to user

        vm.prank(from);
        token.transfer(gte_router, amount); // router sell simulation step 1

        vm.prank(gte_router);
        token.transfer(launcher, amount); // router sell simulation step 2

        vm.prank(launcher);
        token.transfer(from, amount); // back to user

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSignature("TransfersDisabledWhileBonding()"));
        token.transfer(to, amount);

        vm.prank(to);
        vm.expectRevert(abi.encodeWithSignature("TransfersDisabledWhileBonding()"));
        token.transferFrom(from, to, amount);

        // Even the launcher should only be able to transfer either to or from itself only
        // during bonding
        vm.prank(launcher);
        vm.expectRevert(abi.encodeWithSignature("TransfersDisabledWhileBonding()"));
        token.transferFrom(from, to, amount);
    }
}
