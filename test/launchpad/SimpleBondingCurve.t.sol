// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {TestPlus} from "lib/solady/test/utils/TestPlus.sol";
import {SimpleBondingCurve} from "contracts/launchpad/BondingCurves/SimpleBondingCurve.sol";

contract SimpleBondingCurveTest is Test, TestPlus {
    SimpleBondingCurve curve;
    address public mockToken;
    uint256 public virtualBase;
    uint256 public virtualQuote;
    uint256 public totalSupply;
    uint256 public bondingSupply;

    function setUp() public {
        // the test contract will act as a placeholder launchpad
        curve = new SimpleBondingCurve(address(this));
        mockToken = makeAddr("mockToken");
        virtualBase = 100_000_000 ether;
        virtualQuote = 10 ether;
        totalSupply = 1_000_000_000 ether;
        bondingSupply = 800_000_000 ether;

        _init(virtualBase, virtualQuote);
        _initCurve(mockToken, totalSupply, bondingSupply);
    }

    function testBuy(uint256) public returns (uint256 baseToBuy, uint256 quotePaid) {
        // Record initial state
        uint256 initialBaseSold = curve.baseSoldFromCurve(mockToken);
        (uint256 initialQuoteReserve, uint256 initialBaseReserve) = curve.getReserves(mockToken);

        baseToBuy = _hem(_random(), 0, bondingSupply);
        quotePaid = curve.buy(mockToken, baseToBuy);

        // Verify getters are updated correctly
        assertEq(quotePaid, curve.quoteBoughtByCurve(mockToken));
        assertEq(
            curve.baseSoldFromCurve(mockToken), initialBaseSold + baseToBuy, "Base sold should increase by buy amount"
        );

        (uint256 finalQuoteReserve, uint256 finalBaseReserve) = curve.getReserves(mockToken);
        assertEq(finalQuoteReserve, initialQuoteReserve + quotePaid, "Quote reserve should increase by amount paid");
        assertEq(finalBaseReserve, initialBaseReserve - baseToBuy, "Base reserve should decrease by amount bought");
    }

    function testSell(uint256) public {
        (uint256 baseBought, uint256 quotePaid) = testBuy(_random());

        // Record state before sell
        uint256 baseSoldBeforeSell = curve.baseSoldFromCurve(mockToken);
        (uint256 quoteReserveBefore, uint256 baseReserveBefore) = curve.getReserves(mockToken);

        uint256 amountInBase = _hem(_random(), 0, baseBought);
        uint256 quoteBought = curve.sell(mockToken, amountInBase);

        // Verify getters are updated correctly after sell
        assertEq(quotePaid - quoteBought, curve.quoteBoughtByCurve(mockToken));
        assertEq(
            curve.baseSoldFromCurve(mockToken),
            baseSoldBeforeSell - amountInBase,
            "Base sold should decrease by sell amount"
        );

        (uint256 quoteReserveAfter, uint256 baseReserveAfter) = curve.getReserves(mockToken);
        assertEq(
            quoteReserveAfter, quoteReserveBefore - quoteBought, "Quote reserve should decrease by amount received"
        );
        assertEq(baseReserveAfter, baseReserveBefore + amountInBase, "Base reserve should increase by amount sold");
    }

    function testBuyAnyToken(uint256) public {
        mockToken = address(_randomUniqueAddress());
        _initCurve(mockToken, totalSupply, bondingSupply);
        testBuy(_random());
    }

    function testSellAnyToken(uint256) public {
        mockToken = address(_randomUniqueAddress());
        _initCurve(mockToken, totalSupply, bondingSupply);
        testSell(_random());
    }

    function testBuyAnyVirtualReserves(uint256) public {
        virtualBase = _hem(_random(), 1 ether, uint256(type(uint128).max));
        virtualQuote = _hem(_random(), 1 ether, uint256(type(uint128).max));
        mockToken = address(_randomUniqueAddress());
        _init(virtualBase, virtualQuote);
        _initCurve(mockToken, totalSupply, bondingSupply);
        testBuy(_random());
    }

    function testSellAnyVirtualReserves(uint256) public {
        virtualBase = _hem(_random(), 1 ether, uint256(type(uint128).max));
        virtualQuote = _hem(_random(), 1 ether, uint256(type(uint128).max));
        mockToken = address(_randomUniqueAddress());
        _init(virtualBase, virtualQuote);
        _initCurve(mockToken, totalSupply, bondingSupply);
        testSell(_random());
    }

    function testBuyAnyTotalSupply(uint256) public {
        totalSupply = _hem(_random(), 1 ether, uint256(type(uint128).max));
        mockToken = address(_randomUniqueAddress());
        _initCurve(mockToken, totalSupply, bondingSupply);
        testBuy(_random());
    }

    function testSellAnyTotalSupply(uint256) public {
        totalSupply = _hem(_random(), 1 ether, uint256(type(uint128).max));
        mockToken = address(_randomUniqueAddress());
        _initCurve(mockToken, totalSupply, bondingSupply);
        testSell(_random());
    }

    function testBuyRevertsAmountTooLarge(uint256) public {
        uint256 amount = bondingSupply + virtualBase + 1;
        vm.expectRevert();
        curve.buy(mockToken, amount);
    }

    function testSellRevertsAccessControl(uint256) public {
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert(SimpleBondingCurve.NotLaunchpad.selector);
        curve.sell(mockToken, 1 ether);
    }

    function testBuyRevertsAccessControl(uint256) public {
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert(SimpleBondingCurve.NotLaunchpad.selector);
        curve.buy(mockToken, 1 ether);
    }

    function testInitRevertsAccessControl(uint256) public {
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert(SimpleBondingCurve.NotLaunchpad.selector);
        curve.init(abi.encode(virtualBase, virtualQuote));
    }

    function testInitRevertsInvalidVirtualBase(uint256) public {
        vm.expectRevert(SimpleBondingCurve.InvalidVirtualBase.selector);
        curve.init(abi.encode(0, virtualQuote));
    }

    function testInitRevertsInvalidVirtualQuote(uint256) public {
        vm.expectRevert(SimpleBondingCurve.InvalidVirtualQuote.selector);
        curve.init(abi.encode(virtualBase, 0));
    }

    function testInitializeCurveRevertsAccessControl(uint256) public {
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert(SimpleBondingCurve.NotLaunchpad.selector);
        curve.initializeCurve(mockToken, totalSupply, bondingSupply);
    }

    function _init(uint256 virtualBase_, uint256 virtualQuote_) internal {
        bytes memory initData = abi.encode(virtualBase_, virtualQuote_);
        vm.expectEmit(true, true, true, true);
        emit SimpleBondingCurve.VirtualReservesSet(virtualBase_, virtualQuote_);
        curve.init(initData);
    }

    function _initCurve(address token, uint256 totalSupply_, uint256 bondingSupply_) internal {
        vm.expectEmit();
        emit SimpleBondingCurve.NewTokenLaunched(token, virtualBase, virtualQuote);
        emit SimpleBondingCurve.ReservesSet(token, virtualQuote, bondingSupply_ + virtualBase);
        curve.initializeCurve(token, totalSupply_, bondingSupply_);
    }
}
