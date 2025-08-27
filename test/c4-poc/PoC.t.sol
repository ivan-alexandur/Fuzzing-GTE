// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TestPlus} from "lib/solady/test/utils/TestPlus.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

import {PoCTestBase} from "./PoCTestBase.t.sol";
import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {OrderIdLib} from "contracts/clob/types/Order.sol";
import {ICLOB} from "contracts/clob/ICLOB.sol";
import {CLOB} from "contracts/clob/CLOB.sol";
import {Side, Order, OrderId} from "contracts/clob/types/Order.sol";
import {Limit} from "contracts/clob/types/Book.sol";
import {SpotOperatorRoles as OperatorRoles} from "contracts/utils/OperatorPanel.sol";

import {MIN_MIN_LIMIT_ORDER_AMOUNT_BASE} from "contracts/clob/types/Book.sol";

import {console} from "forge-std/console.sol";

contract MockUSDT is ERC20 {
    constructor() ERC20("MOCKUSDT", "USDT") {}

    function decimals() public view override returns (uint8) {
        return 18;
    }
}

contract PoC is PoCTestBase, TestPlus {
    using SafeTransferLib for address;
    using FixedPointMathLib for uint256;

    MockUSDT USDT;

    address buyer1 = makeAddr("buyer1");
    address buyer2 = makeAddr("buyer2");
    address seller = makeAddr("seller");

    uint256 constant tickSize = TICK_SIZE;
    uint256 constant lotSizeInBase = 0.001e18;

    function setUp() public override {
        super.setUp();
        USDT = new MockUSDT();
        wethCLOB = _deployClob(address(USDT), address(weth));
        vm.startPrank(address(clobManager));
        ICLOB(wethCLOB).setLotSizeInBase(lotSizeInBase); // set lot size greater than 1
        ICLOB(wethCLOB).setTickSize(tickSize); // price tick size is 0.01$
        vm.stopPrank();
    }

    modifier whenUserDeposited(address user, address token, uint256 amount) {
        _userDeposit(user, token, amount);
        _;
    }

    /// @dev Test demonstrates
    function test_LinkedListBroken() public {
        uint256 userLength = MAX_NUM_LIMITS_PER_SIDE + 1; // 11 users to trigger bump
        users = new address[](userLength);
        bool[] memory toggles = new bool[](userLength);

        ICLOB market = ICLOB(wethCLOB);

        /**
         * Create 11 orders with different prices to exceed MAX_NUM_LIMITS_PER_SIDE (10).
         * The 11th order will trigger removal of the least competitive order.
         *
         * For sell orders:
         * - Orders at prices: 3000, 3000, 2999, 2998, ..., 2990
         * - When 11th price level is created, order at price 3000 gets bumped
         */
        for (uint256 i = 0; i < userLength; i++) {
            address user = address(uint160(uint256(keccak256(abi.encode(i)))));
            users[i] = user;
            _userDeposit(user, address(weth), type(uint256).max);
            toggles[i] = true;
        }

        vm.prank(clobManager.owner());
        clobManager.setMaxLimitsExempt(users, toggles);

        for (uint256 i = 0; i < userLength; i++) {
            address user = users[i];

            vm.prank(user);
            market.placeOrder(
                user,
                ICLOB.PlaceOrderArgs({
                    side: Side.SELL,
                    clientOrderId: 0,
                    tif: ICLOB.TiF.MOC,
                    expiryTime: uint32(vm.getBlockTimestamp() + 1 hours),
                    limitPrice: (3000 - (i / 2)) * TICK_SIZE, // Each order at different price
                    amount: 1e18,
                    baseDenominated: true
                })
            );
        }

        // Check that tailOrder is broken after the bump
        Limit memory limit3000 = market.getLimit(3000 * TICK_SIZE, Side.SELL);
        uint256 tailOrderId = OrderIdLib.unwrap(limit3000.tailOrder);

        assertTrue(limit3000.numOrders > 0, "test setup failed");
        assertNotEq(tailOrderId, 0, "tailOrder should not be 0 when limit has orders");
    }

    /// @dev S-103 finding, using max limits instead of max orders is unenforcible without introducing a dos around clearing out the entirety of the worst limit

    function test_audit_bypass_max_limit() external {
        // forge test -vvvv --mt test_audit_bypass_max_limit

        // create user and give funds
        address userA = makeAddr("userA");
        tokenA.mint(userA, 100_000_000e18);

        // put user on whitelist for ease of testing
        address[] memory accounts = new address[](1);
        accounts[0] = userA;
        bool[] memory toggles = new bool[](1);
        toggles[0] = true;
        clobManager.setMaxLimitsExempt(accounts, toggles);

        // prank user and deposit funds
        vm.startPrank(userA);
        tokenA.approve(address(accountManager), 100_000_000e18);
        accountManager.deposit(userA, address(tokenA), 100_000_000e18);

        uint256 startingPrice = 1000e18;
        // make a bunch of limit orders
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: Side.BUY,
            clientOrderId: 0,
            tif: ICLOB.TiF.MOC,
            expiryTime: 0,
            limitPrice: startingPrice,
            amount: 0.01e18,
            baseDenominated: true
        });

        console.log("=== FIRST 1000 ===");

        // post 1000 orders at different limits - this should reach the limit maximum
        for (uint256 i; i < 1000; i++) {
            ICLOB(abCLOB).placeOrder(userA, args);
            args.limitPrice -= TICK_SIZE;
            args.clientOrderId += 1;
        }

        // args.limitPrice now contains the lowest price in the book (least competitive for buy orders)
        uint256 lowestPriceInBook = args.limitPrice + TICK_SIZE; // Add back one tick since we subtracted after the last order

        console.log("=== INTERMEDIATE CHECKS ===");
        console.log("HERE");

        // try to place a new one at a lower price (less competitive) - shouldn't be allowed
        // args.limitPrice is currently below lowestPriceInBook, so this should revert
        vm.expectRevert();
        ICLOB(abCLOB).placeOrder(userA, args);

        // try to place a new one at a higher price (more competitive) - will correctly boot the lowest order off of the tree
        args.limitPrice = startingPrice + TICK_SIZE; // one tick higher than the highest bid
        args.clientOrderId += 1;
        ICLOB(abCLOB).placeOrder(userA, args);

        assertEq(ICLOB(abCLOB).getNumBids(), ICLOB(abCLOB).maxNumOrdersPerSide());

        // Test that placing a less competitive order reverts
        args.limitPrice = lowestPriceInBook - TICK_SIZE; // Lower than the lowest price in the book
        args.clientOrderId += 1;
        vm.expectRevert(CLOB.MaxOrdersInBookPostNotCompetitive.selector);
        ICLOB(abCLOB).placeOrder(userA, args);
    }

    /// @notice S-285 finding. Demonstrates that amending only the timestamp (same price/amount) always reverts ZeroOrder()
    function test_onlyTimestampChange_revertsZeroOrder() external {
        // 1) Post a GTC BUY order
        uint32 ttl = uint32(block.timestamp + 1 days);
        uint256 price = 0.01 ether;
        uint256 baseAmt = 1 ether;

        ICLOB testClob = ICLOB(abCLOB);

        // mint & deposit quote for BUY order
        uint256 quoteNeeded = testClob.getQuoteTokenAmount(price, baseAmt);
        tokenA.mint(jb, quoteNeeded);
        vm.startPrank(jb);
        tokenA.approve(address(accountManager), type(uint256).max);
        accountManager.deposit(jb, address(tokenA), quoteNeeded);
        vm.stopPrank();

        // place BUY order
        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: Side.BUY,
            clientOrderId: 0,
            tif: ICLOB.TiF.GTC,
            expiryTime: ttl,
            limitPrice: price,
            amount: baseAmt,
            baseDenominated: true
        });

        vm.prank(jb);
        ICLOB.PlaceOrderResult memory res = testClob.placeOrder(jb, args);
        uint256 orderId = res.orderId;

        // no fills, so remaining == baseAmt
        uint256 remaining = baseAmt;

        // 2) Try to amend with the SAME price & amount but NEW timestamp
        ICLOB.AmendArgs memory a;
        a.orderId = orderId;
        a.side = Side.BUY;
        a.price = price;
        a.amountInBase = remaining;
        a.cancelTimestamp = ttl + 1; // bump by 1 second

        vm.prank(jb);
        // this should not revert
        // vm.expectRevert(abi.encodeWithSignature("ZeroOrder()"));
        testClob.amend(jb, a);

        Order memory order = testClob.getOrder(orderId);
        assertEq(order.cancelTimestamp, ttl + 1);
    }

    /// @notice S-286 finding. While that particular finding was trying to demonstrate something else (unsuccessfully),
    /// it did show a shortcoming of how limit order placed counter was erroneously incremented if the limit order was
    /// fully consumed. We fix this as shown here, by moving the increment logic in `executeBid/Ask` line 599 / 642
    function test_MaxLimitPlaced_For_FullyConsumed_LimitOrders() public {
        // 2. Ensure the attacker and victim are subject to the transaction limits
        _setMaxLimitWhitelist(buyer1, false);
        _setMaxLimitWhitelist(seller, false);

        // 3. Set a low transaction limit for the test
        vm.prank(address(clobManager));
        clob.setMaxLimitsPerTx(2);

        uint256 amount = 1 ether;
        uint256 price = 0.01 ether;

        setupOrder(Side.SELL, seller, amount, price);

        setupTokens(Side.BUY, buyer1, amount, price, true);

        vm.startPrank(buyer1);
        for (uint256 i; i < 100; i++) {
            // fully consumed limit orders do not count towards the max limit placed limit
            clob.placeOrder(
                buyer1,
                ICLOB.PlaceOrderArgs({
                    side: Side.BUY,
                    clientOrderId: 0,
                    tif: ICLOB.TiF.GTC,
                    expiryTime: uint32(vm.getBlockTimestamp() + 1),
                    limitPrice: price + TICK_SIZE,
                    amount: amount / 100,
                    baseDenominated: true
                })
            );
        }
        vm.stopPrank();
    }

    function _userDeposit(address user, address token, uint256 amount) internal {
        vm.startPrank(user);
        deal(token, user, amount);
        token.safeApprove(address(accountManager), amount);
        accountManager.deposit(user, token, amount);
        vm.stopPrank();
    }
}
