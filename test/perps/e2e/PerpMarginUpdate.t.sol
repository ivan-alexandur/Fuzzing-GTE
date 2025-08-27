// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "../PerpManagerTestBase.sol";

contract PerpMarginUpdateTest is PerpManagerTestBase {
    using FixedPointMathLib for *;
    using SafeCastLib for *;

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               SUCCESS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    uint256 mark;
    uint256 subaccount;
    uint256 leverage;
    uint256 amount;
    uint256 freeCollateralBefore;
    int256 marginBefore;
    int256 funding;
    uint256 freeCollateralAfter;
    int256 marginAfter;

    /// forge-config: default.fuzz.runs = 1000
    function test_Perp_MarginUpdate_Deposit_Success(uint256) public {
        subaccount = _random();
        mark = _conformTick(ETH, _hem(_random(), 1e18, 100_000e18));
        leverage = _hem(_random(), 1e18, 50e18);

        vm.prank(rite);
        perpManager.setPositionLeverage(ETH, rite, 1, leverage);

        perpManager.mockSetMarkPrice(ETH, mark);

        _placeTrade({
            subaccount: subaccount,
            asset: ETH,
            taker: rite,
            maker: jb,
            price: mark,
            amount: _conformLots(ETH, _hem(_random(), 1e18, 10e18)),
            side: _randomChance(2) ? Side.BUY : Side.SELL
        });

        freeCollateralBefore = perpManager.getFreeCollateralBalance(rite);
        marginBefore = perpManager.getMarginBalance(rite, subaccount);
        amount = _hem(_random(), 1e18, 50_000e18);

        vm.prank(rite);
        // vm.expectEmit(true, true, true, true);
        // emit PerpManager.MarginAdded({account: rite, subaccount: subaccount, amount: amount, nonce: 18});
        perpManager.addMargin({account: rite, subaccount: subaccount, amount: amount});

        freeCollateralAfter = perpManager.getFreeCollateralBalance(rite);
        marginAfter = perpManager.getMarginBalance(rite, subaccount);

        assertEq(freeCollateralBefore, freeCollateralAfter + amount, "free collateral wrong");
        assertEq(marginAfter, marginBefore + int256(amount), "margin wrong");
    }

    /// forge-config: default.fuzz.runs = 1000
    function test_Perp_MarginUpdate_Withdraw_Success_FundingWithdraw(uint256) public {
        subaccount = _random();
        mark = _conformTick(ETH, _hem(_random(), 1e18, 100_000e18));
        leverage = _hem(_random(), 11e18, 50e18);

        perpManager.mockSetMarkPrice(ETH, mark);

        _placeTrade({
            subaccount: subaccount,
            asset: ETH,
            taker: rite,
            maker: jb,
            price: mark,
            amount: _conformLots(ETH, _hem(_random(), 1e18, 10e18)),
            side: _randomChance(2) ? Side.BUY : Side.SELL
        });

        Position memory position = perpManager.getPosition(ETH, rite, subaccount);

        uint256 fee = position.openNotional * TAKER_BASE_FEE_RATE / 10_000_000;

        funding = _hem(_random(), 100e18, 5000e18).toInt256();
        if (position.isLong) funding = -funding;

        amount = funding.abs().fullMulDiv(position.amount, 1e18);

        perpManager.mockSetCumulativeFunding(ETH, funding);

        int256 pendingFundingPayment = perpManager.getPendingFundingPayment(rite, subaccount);

        // assertEq(pendingFundingPayment, -amount.toInt256(), "funding payment wrong");

        amount = pendingFundingPayment.abs() - 100;

        freeCollateralBefore = perpManager.getFreeCollateralBalance(rite);
        marginBefore = perpManager.getMarginBalance(rite, subaccount);

        // note: keep original fee in so that withdraw meets margin requirements
        amount -= fee;

        vm.prank(rite);
        // vm.expectEmit(true, true, true, true);
        // emit PerpManager.MarginRemoved({account: rite, subaccount: subaccount, amount: amount, nonce: 18});
        perpManager.removeMargin({account: rite, subaccount: subaccount, amount: amount});

        freeCollateralAfter = perpManager.getFreeCollateralBalance(rite);
        marginAfter = perpManager.getMarginBalance(rite, subaccount);

        assertEq(freeCollateralBefore, freeCollateralAfter - amount, "free collateral wrong");
        assertEq(marginAfter, marginBefore - int256(amount) - pendingFundingPayment, "margin wrong");
    }

    function test_Perp_MarginUpdate_Withdraw_Success_UpnlWithdraw(uint256) public {
        subaccount = _random();
        leverage = _hem(_random(), 10e18, 50e18);
        mark = _conformTick(ETH, _hem(_random(), 10e18, 100_000e18));

        vm.prank(rite);
        perpManager.setPositionLeverage(ETH, rite, subaccount, leverage);

        perpManager.mockSetMarkPrice(ETH, mark);

        _placeTrade({
            subaccount: subaccount,
            asset: ETH,
            taker: rite,
            maker: jb,
            price: mark,
            amount: _conformLots(ETH, _hem(_random(), 1e18, 10e18)),
            side: _randomChance(2) ? Side.BUY : Side.SELL
        });

        Position memory position = perpManager.getPosition(ETH, rite, subaccount);

        if (position.isLong) mark = _hem(_random(), mark + mark * 1 / 10, mark + mark * 9 / 10); // increase 10% to 90%

        else mark = _hem(_random(), mark / 10, mark - mark / 10); // decrease 10% to 90%

        perpManager.mockSetMarkPrice(ETH, mark);

        uint256 notional = position.amount.fullMulDiv(mark, 1e18);

        uint256 required = notional.fullMulDiv(1e18, leverage).max(notional / 10);

        int256 pnl = _getPnl({currentNotional: notional, openNotional: position.openNotional, isLong: position.isLong});

        freeCollateralBefore = perpManager.getFreeCollateralBalance(rite);
        marginBefore = perpManager.getMarginBalance(rite, subaccount);

        uint256 equity = (marginBefore + pnl).toUint256();

        if (required >= equity) return; // cannot withdraw

        uint256 maxWithdrawal = equity > required ? equity - required : 0;

        if (maxWithdrawal > marginBefore.toUint256()) maxWithdrawal = marginBefore.toUint256() - 10;

        amount = _hem(_random(), 1, maxWithdrawal);

        vm.prank(rite);
        perpManager.removeMargin(rite, subaccount, amount);

        freeCollateralAfter = perpManager.getFreeCollateralBalance(rite);
        marginAfter = perpManager.getMarginBalance(rite, subaccount);

        assertEq(freeCollateralAfter, freeCollateralBefore + amount, "free collateral wrong");
        assertEq(marginAfter, marginBefore - int256(amount), "margin wrong");
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                 FAIL
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_MarginUpdate_Fail_Deposit_NoPosition(uint256) public {
        amount = _hem(_random(), 1e18, 50_000e18);
        subaccount = _random();

        vm.prank(rite);
        vm.expectRevert(abi.encodeWithSelector(PerpManager.InvalidDeposit.selector));
        perpManager.addMargin(rite, subaccount, amount);
    }

    function test_MarginUpdate_Fail_Withdraw_NoPosition(uint256) public {
        amount = _hem(_random(), 1e18, 50_000e18);
        subaccount = _random();

        vm.prank(rite);
        vm.expectRevert(abi.encodeWithSelector(PerpManager.InvalidWithdraw.selector));
        perpManager.removeMargin(rite, subaccount, amount);
    }

    function test_MarginUpdate_Fail_Deposit_ZeroAmount(uint256) public {
        subaccount = _random();

        vm.prank(rite);
        vm.expectRevert(abi.encodeWithSelector(PerpManager.InvalidDeposit.selector));
        perpManager.addMargin(rite, subaccount, 0);
    }

    function test_MarginUpdate_Fail_Withdraw_ZeroAmount(uint256) public {
        subaccount = _random();

        vm.prank(rite);
        vm.expectRevert(abi.encodeWithSelector(PerpManager.InvalidWithdraw.selector));
        perpManager.removeMargin(rite, subaccount, 0);
    }

    function test_MarginUpdate_Fail_Deposit_Liquidatable(uint256) public {
        subaccount = _random();
        leverage = _hem(_random(), 10e18, 50e18);
        mark = _conformTick(ETH, _hem(_random(), 10e18, 100_000e18));

        vm.prank(rite);
        perpManager.setPositionLeverage(ETH, rite, subaccount, leverage);

        perpManager.mockSetMarkPrice(ETH, mark);

        _placeTrade({
            subaccount: subaccount,
            asset: ETH,
            taker: rite,
            maker: jb,
            price: mark,
            amount: _conformLots(ETH, _hem(_random(), 1e18, 10e18)),
            side: _randomChance(2) ? Side.BUY : Side.SELL
        });

        Position memory position = perpManager.getPosition(ETH, rite, subaccount);

        if (position.isLong) mark = mark / 10; // drop 90%

        else mark = mark * 10; // increase 10x

        perpManager.mockSetMarkPrice(ETH, mark);

        assertTrue(perpManager.isLiquidatable(rite, subaccount), "position not liquidatable");

        int256 pnl = _getPnl({
            currentNotional: position.amount.fullMulDiv(mark, 1e18),
            openNotional: position.openNotional,
            isLong: position.isLong
        });

        uint256 nonLiquidatableMargin = position.amount.fullMulDiv(mark, 1e18).fullMulDiv(1e18, 100e18);

        marginBefore = perpManager.getMarginBalance(rite, subaccount);

        uint256 amountNeeded = (nonLiquidatableMargin.toInt256() - (marginBefore + pnl)).toUint256();

        vm.startPrank(rite);
        vm.expectRevert(abi.encodeWithSelector(ClearingHouseLib.Liquidatable.selector));
        perpManager.addMargin(rite, subaccount, amountNeeded - 10);

        perpManager.addMargin(rite, subaccount, amountNeeded);
    }

    function test_MarginUpdate_Fail_Withdraw_MarginRequirementUnmet(uint256) public {
        subaccount = _random();
        leverage = _hem(_random(), 1e18, 50e18);
        mark = _conformTick(ETH, _hem(_random(), 10e18, 100_000e18));

        vm.prank(rite);
        perpManager.setPositionLeverage(ETH, rite, subaccount, leverage);

        perpManager.mockSetMarkPrice(ETH, mark);

        _placeTrade({
            subaccount: subaccount,
            asset: ETH,
            taker: rite,
            maker: jb,
            price: mark,
            amount: _conformLots(ETH, _hem(_random(), 1e18, 10e18)),
            side: _randomChance(2) ? Side.BUY : Side.SELL
        });

        Position memory position = perpManager.getPosition(ETH, rite, subaccount);

        if (position.isLong) mark = _hem(_random(), mark + mark * 1 / 10, mark + mark * 9 / 10); // increase 10% to 90%

        else mark = _hem(_random(), mark / 10, mark - mark / 10); // decrease 10% to 90%

        perpManager.mockSetMarkPrice(ETH, mark);

        uint256 notional = position.amount.fullMulDiv(mark, 1e18);

        uint256 required = notional.fullMulDiv(1e18, leverage).max(notional / 10);

        int256 pnl = _getPnl({currentNotional: notional, openNotional: position.openNotional, isLong: position.isLong});

        marginBefore = perpManager.getMarginBalance(rite, subaccount);

        uint256 equity = (marginBefore + pnl).toUint256();

        uint256 maxWithdrawal = equity > required ? equity - required : 0;

        vm.prank(rite);
        vm.expectRevert(ClearingHouseLib.MarginRequirementUnmet.selector);
        perpManager.removeMargin(rite, subaccount, maxWithdrawal + 1);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                 HELPER
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _getPnl(uint256 currentNotional, uint256 openNotional, bool isLong) internal pure returns (int256 pnl) {
        if (isLong) return currentNotional.toInt256() - openNotional.toInt256();
        else return openNotional.toInt256() - currentNotional.toInt256();
    }
}
