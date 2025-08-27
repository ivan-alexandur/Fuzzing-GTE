// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "../PerpManagerTestBase.sol";

contract GTL_SubaccountHook_Test is PerpManagerTestBase {
    using FixedPointMathLib for *;

    function setUp() public override {
        super.setUp();

        vm.prank(rite);
        gtl.deposit(1_000_000_000e18, rite);
    }

    address gtlAdmin = makeAddr("gtlAdmin");

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                         STANDARD OPEN / CLOSE
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_GTL_SubaccountHook_TakerOpen(uint256) public {
        uint256 subaccount1 = _randomUnique();
        uint256 subaccount2 = _randomUnique();
        uint256 subaccount3 = _randomUnique();
        Side side = _randomChance(2) ? Side.BUY : Side.SELL;

        // open
        _placeTrade({
            asset: ETH,
            taker: address(gtl),
            maker: jb,
            price: 4000e18,
            amount: 1e18,
            side: side,
            subaccount: subaccount1
        });

        _placeTrade({
            asset: ETH,
            taker: address(gtl),
            maker: jb,
            price: 4000e18,
            amount: 1e18,
            side: side,
            subaccount: subaccount2
        });

        _placeTrade({
            asset: ETH,
            taker: address(gtl),
            maker: jb,
            price: 4000e18,
            amount: 1e18,
            side: side,
            subaccount: subaccount3
        });

        uint256[] memory subaccounts = gtl.getSubaccounts();

        assertEq(subaccounts.length, 3);
        assertEq(subaccounts[0], subaccount1, "subaccount1 incorrect after open");
        assertEq(subaccounts[1], subaccount2, "subaccount2 incorrect after open");
        assertEq(subaccounts[2], subaccount3, "subaccount3 incorrect after open");

        // update increase
        _placeTrade({
            asset: ETH,
            taker: address(gtl),
            maker: jb,
            price: 4000e18,
            amount: 1e18,
            side: side,
            subaccount: subaccount1
        });

        subaccounts = gtl.getSubaccounts();

        assertEq(subaccounts.length, 3);
        assertEq(subaccounts[0], subaccount1, "subaccount1 incorrect after update");
        assertEq(subaccounts[1], subaccount2, "subaccount2 incorrect after update");
        assertEq(subaccounts[2], subaccount3, "subaccount3 incorrect after update");

        // update decrease
        _placeTrade({
            asset: ETH,
            taker: address(gtl),
            maker: jb,
            price: 4000e18,
            amount: 1e18,
            side: side == Side.BUY ? Side.SELL : Side.BUY,
            subaccount: subaccount1
        });

        subaccounts = gtl.getSubaccounts();

        assertEq(subaccounts.length, 3);
        assertEq(subaccounts[0], subaccount1, "subaccount1 incorrect after update");
        assertEq(subaccounts[1], subaccount2, "subaccount2 incorrect after update");
        assertEq(subaccounts[2], subaccount3, "subaccount3 incorrect after update");
    }

    function test_GTL_SubaccountHook_MakerOpen(uint256) public {
        uint256 subaccount1 = _randomUnique();
        uint256 subaccount2 = _randomUnique();
        uint256 subaccount3 = _randomUnique();
        Side side = _randomChance(2) ? Side.BUY : Side.SELL;

        // open
        _placeTrade({
            asset: ETH,
            maker: address(gtl),
            taker: jb,
            price: 4000e18,
            amount: 1e18,
            side: side,
            subaccount: subaccount1
        });

        _placeTrade({
            asset: ETH,
            maker: address(gtl),
            taker: jb,
            price: 4000e18,
            amount: 1e18,
            side: side,
            subaccount: subaccount2
        });

        _placeTrade({
            asset: ETH,
            maker: address(gtl),
            taker: jb,
            price: 4000e18,
            amount: 1e18,
            side: side,
            subaccount: subaccount3
        });

        uint256[] memory subaccounts = gtl.getSubaccounts();

        assertEq(subaccounts.length, 3, "subaccounts length incorrect after open");
        assertEq(subaccounts[0], subaccount1, "subaccount1 incorrect after open");
        assertEq(subaccounts[1], subaccount2, "subaccount2 incorrect after open");
        assertEq(subaccounts[2], subaccount3, "subaccount3 incorrect after open");

        // update increase
        _placeTrade({
            asset: ETH,
            maker: address(gtl),
            taker: jb,
            price: 4000e18,
            amount: 1e18,
            side: side,
            subaccount: subaccount1
        });

        subaccounts = gtl.getSubaccounts();

        assertEq(subaccounts.length, 3, "subaccounts length incorrect after update increase");
        assertEq(subaccounts[0], subaccount1, "subaccount1 incorrect after update");
        assertEq(subaccounts[1], subaccount2, "subaccount2 incorrect after update");
        assertEq(subaccounts[2], subaccount3, "subaccount3 incorrect after update");

        // update decrease
        _placeTrade({
            asset: ETH,
            maker: address(gtl),
            taker: jb,
            price: 4000e18,
            amount: 1e18,
            side: side == Side.BUY ? Side.SELL : Side.BUY,
            subaccount: subaccount1
        });

        subaccounts = gtl.getSubaccounts();

        assertEq(subaccounts.length, 3, "subaccounts length incorrect after update decrease");
        assertEq(subaccounts[0], subaccount1, "subaccount1 incorrect after update");
        assertEq(subaccounts[1], subaccount2, "subaccount2 incorrect after update");
        assertEq(subaccounts[2], subaccount3, "subaccount3 incorrect after update");
    }

    function test_GTL_SubaccountHook_takerClose(uint256) public {
        uint256 subaccount1 = _randomUnique();
        uint256 subaccount2 = _randomUnique();
        uint256 subaccount3 = _randomUnique();
        Side openSide = _randomChance(2) ? Side.BUY : Side.SELL;
        Side closeSide = openSide == Side.BUY ? Side.SELL : Side.BUY;

        // open
        _placeTrade({
            asset: ETH,
            taker: address(gtl),
            maker: jb,
            price: 4000e18,
            amount: 1e18,
            side: openSide,
            subaccount: subaccount1
        });

        _placeTrade({
            asset: ETH,
            taker: address(gtl),
            maker: jb,
            price: 4000e18,
            amount: 1e18,
            side: openSide,
            subaccount: subaccount2
        });

        _placeTrade({
            asset: ETH,
            taker: address(gtl),
            maker: jb,
            price: 4000e18,
            amount: 1e18,
            side: openSide,
            subaccount: subaccount3
        });

        // close
        _placeTrade({
            asset: ETH,
            taker: address(gtl),
            maker: jb,
            price: 4000e18,
            amount: 1e18,
            side: closeSide,
            subaccount: subaccount1
        });

        uint256[] memory subaccounts = gtl.getSubaccounts();

        assertEq(subaccounts.length, 2, "subaccounts length incorrect after close 1");
        assertEq(subaccounts[0], subaccount2, "subaccount2 incorrect after close 1");
        assertEq(subaccounts[1], subaccount3, "subaccount3 incorrect after close 1");

        _placeTrade({
            asset: ETH,
            taker: address(gtl),
            maker: jb,
            price: 4000e18,
            amount: 1e18,
            side: closeSide,
            subaccount: subaccount2
        });

        subaccounts = gtl.getSubaccounts();

        assertEq(subaccounts.length, 1, "subaccounts length incorrect after close 2");
        assertEq(subaccounts[0], subaccount3, "subaccount3 incorrect after close 2");

        _placeTrade({
            asset: ETH,
            taker: address(gtl),
            maker: jb,
            price: 4000e18,
            amount: 1e18,
            side: closeSide,
            subaccount: subaccount3
        });

        subaccounts = gtl.getSubaccounts();

        assertEq(subaccounts.length, 0, "subaccounts not empty after closing all");
    }

    function test_GTL_SubaccountHook_makerClose(uint256) public {
        uint256 subaccount1 = _randomUnique();
        uint256 subaccount2 = _randomUnique();
        uint256 subaccount3 = _randomUnique();
        Side openSide = _randomChance(2) ? Side.BUY : Side.SELL;
        Side closeSide = openSide == Side.BUY ? Side.SELL : Side.BUY;

        // open
        _placeTrade({
            asset: ETH,
            maker: address(gtl),
            taker: jb,
            price: 4000e18,
            amount: 1e18,
            side: openSide,
            subaccount: subaccount1
        });

        _placeTrade({
            asset: ETH,
            maker: address(gtl),
            taker: jb,
            price: 4000e18,
            amount: 1e18,
            side: openSide,
            subaccount: subaccount2
        });

        _placeTrade({
            asset: ETH,
            maker: address(gtl),
            taker: jb,
            price: 4000e18,
            amount: 1e18,
            side: openSide,
            subaccount: subaccount3
        });

        // close
        _placeTrade({
            asset: ETH,
            maker: address(gtl),
            taker: jb,
            price: 4000e18,
            amount: 1e18,
            side: closeSide,
            subaccount: subaccount1
        });

        uint256[] memory subaccounts = gtl.getSubaccounts();

        assertEq(subaccounts.length, 2);
        assertEq(subaccounts[0], subaccount2, "subaccount2 incorrect after close");
        assertEq(subaccounts[1], subaccount3, "subaccount3 incorrect after close");

        _placeTrade({
            asset: ETH,
            maker: address(gtl),
            taker: jb,
            price: 4000e18,
            amount: 1e18,
            side: closeSide,
            subaccount: subaccount2
        });

        subaccounts = gtl.getSubaccounts();

        assertEq(subaccounts.length, 1);
        assertEq(subaccounts[0], subaccount3, "subaccount3 incorrect after close");

        _placeTrade({
            asset: ETH,
            maker: address(gtl),
            taker: jb,
            price: 4000e18,
            amount: 1e18,
            side: closeSide,
            subaccount: subaccount3
        });

        subaccounts = gtl.getSubaccounts();

        assertEq(subaccounts.length, 0, "subaccounts should be empty after closing all");
    }
}
