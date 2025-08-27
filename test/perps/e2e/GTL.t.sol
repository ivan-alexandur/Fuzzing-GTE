// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "../PerpManagerTestBase.sol";

import {ERC4626, ERC20} from "@solady/tokens/ERC4626.sol";
import {PerpsOperatorRoles} from "../../../contracts/utils/OperatorPanel.sol";

// @todo add valuation

contract GTLTest is PerpManagerTestBase {
    using FixedPointMathLib for uint256;
    using SafeCastLib for uint256;

    function setUp() public override {
        super.setUp();

        vm.prank(jb);
        gtl.deposit(500_000e18, jb);

        vm.startPrank(admin);
        gtl.grantAdminRole(operator);
        gtl.approveOperator(operator);
        vm.stopPrank();
    }

    address operator = makeAddr("GTLOperator");

    uint256 withdrawal1Val;
    uint256 withdrawal2Val;
    uint256 gtlBalBefore;
    uint256 riteBalBefore;
    uint256 jbBalBefore;
    uint256 riteSharesBefore;
    uint256 jbSharesBefore;

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                  LP
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_GTL_Metadata() public view {
        assertEq(gtl.name(), "GTE Liquidity Pool");
        assertEq(gtl.symbol(), "GTL");
        assertEq(gtl.asset(), address(usdc));
    }

    function test_GTL_Deposit(uint256) public {
        uint256 deposit = _hem(_random(), 1e18, 100_000e18);

        uint256 preview = gtl.previewDeposit(deposit);
        uint256 convert = gtl.convertToShares(deposit);

        uint256 shareBal = gtl.balanceOf(rite);
        uint256 assetBal = usdc.balanceOf(rite);
        uint256 gtlBal = usdc.balanceOf(address(gtl));

        vm.prank(rite);
        uint256 shares = gtl.deposit(deposit, rite);

        assertEq(shares, preview, "deposit != previewDeposit");
        assertEq(shares, convert, "deposit != convertToShares");

        assertEq(shareBal + shares, gtl.balanceOf(rite), "account share balance wrong");
        assertEq(assetBal - deposit, usdc.balanceOf(rite), "account asset balance wrong");
        assertEq(gtlBal + deposit, usdc.balanceOf(address(gtl)), "gtl asset balance wrong");
    }

    function test_GTL_Mint(uint256) public {
        uint256 shares = _hem(_random(), 1e18, 100_000e18);

        uint256 preview = gtl.previewMint(shares);
        uint256 convert = gtl.convertToAssets(shares);

        uint256 shareBal = gtl.balanceOf(rite);
        uint256 assetBal = usdc.balanceOf(rite);
        uint256 gtlBal = usdc.balanceOf(address(gtl));

        vm.prank(rite);
        uint256 assets = gtl.mint(shares, rite);

        assertEq(assets, preview, "mint != previewMint");
        assertEq(assets, convert, "mint != convertToAssets");

        assertEq(shareBal + shares, gtl.balanceOf(rite), "account share balance wrong");
        assertEq(assetBal - assets, usdc.balanceOf(rite), "account asset balance wrong");
        assertEq(gtlBal + assets, usdc.balanceOf(address(gtl)), "gtl asset balance wrong");
    }

    function test_GTL_QueueWithdrawal(uint256) public {
        vm.prank(rite);
        gtl.deposit(_hem(_random(), 1e18, 100_000e18), rite);

        uint256 riteWithdrawal = _hem(_random(), 500, gtl.balanceOf(rite));
        uint256 jbWithdrawal = _hem(_random(), 500, gtl.balanceOf(jb));

        vm.prank(rite);
        vm.expectEmit(true, true, false, true);
        emit GTL.WithdrawalQueued(1, rite, riteWithdrawal);
        uint256 riteId = gtl.queueWithdrawal(riteWithdrawal);

        vm.prank(jb);
        vm.expectEmit(true, true, false, true);
        emit GTL.WithdrawalQueued(2, jb, jbWithdrawal);
        uint256 jbId = gtl.queueWithdrawal(jbWithdrawal);

        GTL.Withdrawal memory riteWithdrawalData = gtl.getQueuedWithdrawal(riteId);
        GTL.Withdrawal memory jbWithdrawalData = gtl.getQueuedWithdrawal(jbId);

        uint256[] memory withdrawalQueue = gtl.getWithdrawalQueue();

        assertEq(gtl.getQueuedShares(rite), riteWithdrawal, "rite queued shares wrong");
        assertEq(gtl.getQueuedShares(jb), jbWithdrawal, "jb queued shares wrong");

        assertEq(riteWithdrawalData.account, rite, "rite withdrawal account wrong");
        assertEq(riteWithdrawalData.shares, riteWithdrawal, "rite withdrawal shares wrong");
        assertEq(jbWithdrawalData.account, jb, "jb withdrawal account wrong");
        assertEq(jbWithdrawalData.shares, jbWithdrawal, "jb withdrawal shares wrong");

        assertEq(withdrawalQueue.length, 2, "withdrawal queue length wrong");
        assertEq(withdrawalQueue[0], riteId, "rite withdrawal id wrong");
        assertEq(withdrawalQueue[1], jbId, "jb withdrawal id wrong");
    }

    function test_GTL_Withdrawal_Cancel(uint256) public {
        // deposit
        vm.prank(rite);
        gtl.deposit(_hem(_random(), 1e18, 100_000e18), rite);

        vm.prank(julien);
        gtl.deposit(_hem(_random(), 1e18, 100_000e18), julien);

        uint256 riteWithdrawal = _hem(_random(), 500, gtl.balanceOf(rite));
        uint256 jbWithdrawal = _hem(_random(), 500, gtl.balanceOf(jb));
        uint256 mosesWithdrawal = _hem(_random(), 500, gtl.balanceOf(julien));

        // queue withdrawals
        vm.prank(rite);
        uint256 riteId = gtl.queueWithdrawal(riteWithdrawal);

        vm.prank(jb);
        uint256 jbId = gtl.queueWithdrawal(jbWithdrawal);

        vm.prank(julien);
        uint256 mosesId = gtl.queueWithdrawal(mosesWithdrawal);

        // cancel middle
        vm.prank(jb);
        vm.expectEmit(true, true, false, true);
        emit GTL.WithdrawalCanceled(jbId);
        gtl.cancelWithdrawal(jbId);

        GTL.Withdrawal memory jbWithdrawalData = gtl.getQueuedWithdrawal(jbWithdrawal);
        uint256[] memory withdrawalQueue = gtl.getWithdrawalQueue();

        assertEq(gtl.getQueuedShares(jb), 0, "jb queued shares wrong after cancel");
        assertEq(jbWithdrawalData.account, address(0), "jb withdrawal account wrong after cancel");
        assertEq(jbWithdrawalData.shares, 0, "jb withdrawal shares wrong after cancel");
        assertEq(withdrawalQueue.length, 2, "withdrawal queue length wrong after cancel");

        assertEq(withdrawalQueue[0], riteId, "rite withdrawal id wrong after cancel");
        assertEq(withdrawalQueue[1], mosesId, "julien withdrawal id wrong after cancel");

        // cancel last
        vm.prank(julien);
        vm.expectEmit(true, true, false, true);
        emit GTL.WithdrawalCanceled(mosesId);
        gtl.cancelWithdrawal(mosesId);

        GTL.Withdrawal memory mosesWithdrawalData = gtl.getQueuedWithdrawal(mosesId);
        withdrawalQueue = gtl.getWithdrawalQueue();

        assertEq(gtl.getQueuedShares(julien), 0, "julien queued shares wrong after cancel");
        assertEq(mosesWithdrawalData.account, address(0), "julien withdrawal account wrong after cancel");
        assertEq(mosesWithdrawalData.shares, 0, "julien withdrawal shares wrong after cancel");
        assertEq(withdrawalQueue.length, 1, "withdrawal queue length wrong after cancel");
        assertEq(withdrawalQueue[0], riteId, "rite withdrawal id wrong after cancel");

        // cancel only
        vm.prank(rite);
        vm.expectEmit(true, true, false, true);
        emit GTL.WithdrawalCanceled(riteId);
        gtl.cancelWithdrawal(riteId);

        GTL.Withdrawal memory riteWithdrawalData = gtl.getQueuedWithdrawal(riteId);
        withdrawalQueue = gtl.getWithdrawalQueue();

        assertEq(gtl.getQueuedShares(rite), 0, "rite queued shares wrong after cancel");
        assertEq(riteWithdrawalData.account, address(0), "rite withdrawal account wrong after cancel");
        assertEq(riteWithdrawalData.shares, 0, "rite withdrawal shares wrong after cancel");
        assertEq(withdrawalQueue.length, 0, "withdrawal queue length wrong after cancel");
    }

    /// @dev queue withdrawal when there are shares already queued
    function test_GTL_DoubleQueueWithdrawal(uint256) public {
        vm.startPrank(rite);
        uint256 shares = gtl.deposit(_hem(_random(), 1e18, 100_000e18), rite);

        uint256 queue1 = _hem(_random(), 1, shares - 2);

        gtl.queueWithdrawal(queue1);

        uint256 remainingShares = gtl.balanceOf(rite) - gtl.getQueuedShares(rite);

        uint256 queue2 = _hem(_random(), 1, remainingShares);

        gtl.queueWithdrawal(queue2);

        assertEq(gtl.getQueuedShares(rite), queue1 + queue2, "rite queued shares wrong after second queue");
    }

    function test_GTL_TransferWhileQueued(uint256) public {
        vm.startPrank(rite);
        uint256 shares = gtl.deposit(_hem(_random(), 1e18, 100_000e18), rite);

        uint256 queue = _hem(_random(), 1, shares - 2);

        gtl.queueWithdrawal(queue);

        gtl.transfer(jb, _hem(_random(), 1, shares - queue));
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               OPERATOR
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    error Unauthorized();

    function test_GTL_AdminGrant(uint256) public {
        address randomOperator = _getRandomAddress();

        assertFalse(gtl.hasAdminRole(randomOperator), "operator has admin role pre-grant");

        vm.prank(randomOperator);
        vm.expectRevert(Unauthorized.selector);
        gtl.grantAdminRole(randomOperator);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true, address(gtl));
        emit GTL.AdminRoleGranted(randomOperator);
        gtl.grantAdminRole(randomOperator);

        assertTrue(gtl.hasAdminRole(randomOperator), "operator not granted admin role");
    }

    function test_GTL_AdminRevoke(uint256) public {
        address randomOperator = _getRandomAddress();

        vm.prank(admin);
        gtl.grantAdminRole(randomOperator);

        vm.prank(randomOperator);
        vm.expectRevert(Unauthorized.selector);
        gtl.revokeAdminRole(randomOperator);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true, address(gtl));
        emit GTL.AdminRoleRevoked(randomOperator);
        gtl.revokeAdminRole(randomOperator);

        assertFalse(gtl.hasAdminRole(randomOperator), "operator still has admin role after revoke");
    }

    function test_GTL_OperatorApprove(uint256) public {
        address randomOperator = _getRandomAddress();

        vm.startPrank(admin);
        // note: operator must be GTL admin
        vm.expectRevert(GTL.InvalidOperator.selector);
        gtl.approveOperator(randomOperator);

        gtl.grantAdminRole(randomOperator);

        vm.expectEmit(true, true, true, true);
        emit OperatorPanel.OperatorApproved(2, address(gtl), randomOperator, 1 << uint256(PerpsOperatorRoles.ADMIN));
        gtl.approveOperator(randomOperator);

        assertEq(
            perpManager.getOperatorRoleApprovals(address(gtl), randomOperator), 1 << uint256(PerpsOperatorRoles.ADMIN)
        );
    }

    function test_GTL_OperatorDisapprove(uint256) public {
        address randomOperator = _getRandomAddress();

        vm.startPrank(admin);
        gtl.grantAdminRole(randomOperator);
        gtl.approveOperator(randomOperator);

        vm.expectEmit(true, true, true, true, address(perpManager));
        emit OperatorPanel.OperatorDisapproved(3, address(gtl), randomOperator, 1 << uint256(PerpsOperatorRoles.ADMIN));
        gtl.disapproveOperator(randomOperator);

        assertEq(perpManager.getOperatorRoleApprovals(address(gtl), randomOperator), 0);
    }

    function test_GTL_Operator_Permission(uint256) public {
        vm.startPrank(operator);

        uint256 deposit = _hem(_random(), 1e18, 100_000e18);

        perpManager.deposit(address(gtl), deposit);

        uint256 withdraw = _hem(_random(), 0.5e18, deposit);

        perpManager.withdraw(address(gtl), withdraw);
    }

    function test_GTL_ProcessWithdrawals(uint256) public {
        // deposit
        vm.prank(rite);
        gtl.deposit(_hem(_random(), 1e18, 100_000e18), rite);

        vm.prank(julien);
        gtl.deposit(_hem(_random(), 1e18, 100_000e18), julien);

        uint256 riteWithdrawal = _hem(_random(), 500, gtl.balanceOf(rite));
        uint256 jbWithdrawal = _hem(_random(), 500, gtl.balanceOf(jb));
        uint256 mosesWithdrawal = _hem(_random(), 500, gtl.balanceOf(julien));

        withdrawal1Val = gtl.convertToAssets(riteWithdrawal);
        withdrawal2Val = gtl.convertToAssets(jbWithdrawal);

        // queue withdrawals
        vm.prank(rite);
        gtl.queueWithdrawal(riteWithdrawal);

        vm.prank(jb);
        gtl.queueWithdrawal(jbWithdrawal);

        vm.prank(julien);
        gtl.queueWithdrawal(mosesWithdrawal);

        gtlBalBefore = usdc.balanceOf(address(gtl));
        riteBalBefore = usdc.balanceOf(rite);
        jbBalBefore = usdc.balanceOf(jb);
        riteSharesBefore = gtl.balanceOf(rite);
        jbSharesBefore = gtl.balanceOf(jb);

        // process withdrawals
        vm.prank(operator);
        vm.expectEmit(true, true, false, true);
        emit GTL.WithdrawalProcessed(1, rite, riteWithdrawal, withdrawal1Val);
        vm.expectEmit(true, true, false, true);
        emit GTL.WithdrawalProcessed(2, jb, jbWithdrawal, withdrawal2Val);

        gtl.processWithdrawals(2);

        // assertions
        assertEq(gtl.getQueuedShares(rite), 0, "rite queued shares wrong after process");
        assertEq(gtl.getQueuedShares(jb), 0, "jb queued shares wrong after process");
        assertEq(gtl.getQueuedShares(julien), mosesWithdrawal, "julien queued shares wrong after process");

        assertEq(gtl.getQueuedWithdrawal(1).account, address(0), "rite withdrawal account wrong after process");
        assertEq(gtl.getQueuedWithdrawal(2).account, address(0), "jb withdrawal account wrong after process");
        assertEq(gtl.getQueuedWithdrawal(1).shares, 0, "rite withdrawal shares wrong after process");
        assertEq(gtl.getQueuedWithdrawal(2).shares, 0, "jb withdrawal shares wrong after process");
        assertEq(gtl.getQueuedWithdrawal(3).account, julien, "julien withdrawal account wrong after process");
        assertEq(gtl.getQueuedWithdrawal(3).shares, mosesWithdrawal, "julien withdrawal shares wrong after process");

        assertEq(gtl.getWithdrawalQueue().length, 1, "withdrawal queue length wrong after process");
        assertEq(gtl.getWithdrawalQueue()[0], 3, "julien withdrawal id wrong after process");

        assertEq(gtl.balanceOf(rite), riteSharesBefore - riteWithdrawal, "rite shares wrong after process");
        assertEq(gtl.balanceOf(jb), jbSharesBefore - jbWithdrawal, "jb shares wrong after process");
        assertEq(usdc.balanceOf(rite), riteBalBefore + withdrawal1Val, "rite usdc wrong after process");
        assertEq(usdc.balanceOf(jb), jbBalBefore + withdrawal2Val, "jb usdc wrong after process");
        assertEq(
            usdc.balanceOf(address(gtl)), gtlBalBefore - withdrawal1Val - withdrawal2Val, "gtl usdc wrong after process"
        );

        assertEq(gtl.totalAssets(), usdc.balanceOf(address(gtl)), "gtl total assets wrong after process");
    }

    function test_GTL_ProcessWithdrawals_Unauthorized_ExpectRevert(address caller) public {
        vm.assume(caller != admin);
        vm.assume(caller != operator);
        vm.assume(caller != address(factory));

        vm.startPrank(rite);
        gtl.deposit(_hem(_random(), 1e18, 100_000e18), rite);
        uint256 riteWithdrawal = _hem(_random(), 500, gtl.balanceOf(rite));
        gtl.queueWithdrawal(riteWithdrawal);
        vm.stopPrank();

        vm.prank(caller);
        vm.expectRevert(GTL.NotAdmin.selector);
        gtl.processWithdrawals(1);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                 FAIL
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_GTL_WithdrawalRedeem_Fail(uint256) public {
        vm.startPrank(rite);
        gtl.deposit(_hem(_random(), 1e18, 100_000e18), rite);

        assertTrue(gtl.balanceOf(rite) > 0, "rite has no shares");

        uint256 shares = _hem(_random(), 1, gtl.balanceOf(rite));

        vm.expectRevert(ERC4626.WithdrawMoreThanMax.selector);
        gtl.withdraw(shares, rite, rite);

        vm.expectRevert(ERC4626.RedeemMoreThanMax.selector);
        gtl.redeem(shares, rite, rite);
    }

    function test_GTL_QueueWithdrawal_Fail(uint256) public {
        vm.startPrank(rite);
        uint256 shares = gtl.deposit(_hem(_random(), 1e18, 100_000e18), rite);

        // insufficient withdrawal: more than balance
        vm.expectRevert(ERC20.InsufficientBalance.selector);
        gtl.queueWithdrawal(_hem(_random(), shares + 1, shares + 100e18));

        // insufficient withdrawal: 0 shares
        vm.expectRevert(GTL.InsufficientWithdrawal.selector);
        gtl.queueWithdrawal(0);

        gtl.queueWithdrawal(_hem(_random(), 1, shares));

        uint256 remainingShares = gtl.balanceOf(rite) - gtl.getQueuedShares(rite);

        // insufficient withdrawal: more than balance after queueing
        vm.expectRevert(ERC20.InsufficientBalance.selector);
        gtl.queueWithdrawal(remainingShares + 1);
    }

    function test_GTL_TransferQueuedShares_Fail() public {
        vm.startPrank(rite);
        uint256 shares = gtl.deposit(_hem(_random(), 1e18, 100_000e18), rite);

        gtl.queueWithdrawal(_hem(_random(), 1, shares));

        uint256 remainingShares = gtl.balanceOf(rite) - gtl.getQueuedShares(rite);

        vm.expectRevert(ERC20.InsufficientBalance.selector);
        gtl.transfer(jb, remainingShares + 1);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _getRandomAddress() internal returns (address randomAddress) {
        randomAddress = makeAddr(string(abi.encodePacked(_random())));

        vm.assume(randomAddress != admin);
        vm.assume(randomAddress != operator);
    }
}
