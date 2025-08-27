// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {Account as PerpAccount} from "contracts/perps/types/Structs.sol";
import {LiquidatorPanel} from "contracts/perps/modules/LiquidatorPanel.sol";

import "../PerpManagerTestBase.sol";

contract Perp_Deleverage_Test is PerpManagerTestBase {
    using FixedPointMathLib for *;
    using SafeCastLib for *;

    struct DeleverageParams {
        uint256 openPrice;
        Side side;
        uint256 currentPrice;
        int256 cumulativeFunding;
        uint256 amount;
    }

    struct State {
        Position makerPosition;
        Position takerPosition;
        Position makerPositionBTC;
        Position takerPositionBTC;
        bytes32[] takerAssets;
        bytes32[] makerAssets;
        int256 takerMargin;
        int256 makerMargin;
        uint256 takerFreeCollateral;
        uint256 makerFreeCollateral;
        uint256 insuranceFundBalance;
        uint256 openInterestLong;
        uint256 openInterestShort;
    }

    struct ExpectedDeleverageResult {
        uint256 bankruptcyPrice;
        uint256 baseTraded;
        uint256 quoteTraded;
        int256 makerPnl;
        int256 takerPnl;
        int256 fundingPaymentMaker;
        int256 fundingPaymentTaker;
        Position makerPosition;
        Position takerPosition;
        bytes32[] makerAssets;
        bytes32[] takerAssets;
        int256 takerMargin;
        int256 makerMargin;
        uint256 takerFreeCollateral;
        uint256 makerFreeCollateral;
        uint256 badDebt;
    }

    function setUp() public override {
        super.setUp();

        vm.prank(admin);
        perpManager.insuranceFundDeposit(1_000_000_000e18);
    }

    DeleverageParams params;
    State state;
    ExpectedDeleverageResult expected;

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                SUCCESS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @dev fuzzes cross & isolated, with varying taker vs maker sizes, rpnl, etc
    /// forge-config: default.fuzz.runs = 5000
    function test_Perp_Deleverage_Success(uint256) public {
        _fuzzPosition(_randomChance(2));
        _cachePreDeleverageState();
        _predictDeleverage();

        DeleveragePair[] memory pairs = new DeleveragePair[](1);
        pairs[0] = _getPair(rite, jb);

        vm.prank(admin);
        perpManager.deleverage(ETH, pairs);

        _assertPostDeleverageState();
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                 FAIL
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_Perp_Deleverage_Fail_NoPosition_Maker() public {
        _placeTrade({asset: ETH, taker: julien, maker: jb, subaccount: 1, price: 4000e18, amount: 1e18, side: Side.BUY});

        perpManager.mockSetMarkPrice(ETH, 1e18);

        DeleveragePair[] memory pairs = new DeleveragePair[](1);
        pairs[0] = _getPair(rite, jb);

        vm.prank(admin);
        vm.expectRevert(LiquidatorPanel.InvalidDeleveragePair.selector);
        perpManager.deleverage(ETH, pairs);
    }

    function test_Perp_Deleverage_Fail_NoPosition_Taker() public {
        _placeTrade({asset: ETH, taker: rite, maker: jb, subaccount: 1, price: 4000e18, amount: 1e18, side: Side.BUY});

        perpManager.mockSetMarkPrice(ETH, 1e18);

        DeleveragePair[] memory pairs = new DeleveragePair[](1);
        pairs[0] = _getPair(rite, julien);

        vm.prank(admin);
        vm.expectRevert(LiquidatorPanel.InvalidDeleveragePair.selector);
        perpManager.deleverage(ETH, pairs);
    }

    function test_Perp_Deleverage_Fail_MakerHasNoBadDebt() public {
        vm.prank(rite);
        perpManager.setPositionLeverage({asset: ETH, account: rite, subaccount: 1, newLeverage: 1e18});

        _placeTrade({asset: ETH, taker: rite, maker: jb, subaccount: 1, price: 4000e18, amount: 1e18, side: Side.SELL});

        perpManager.mockSetCumulativeFunding(ETH, -3990e18);

        DeleveragePair[] memory pairs = new DeleveragePair[](1);
        pairs[0] = _getPair(rite, jb);

        vm.startPrank(admin);
        vm.expectRevert(LiquidatorPanel.InvalidDeleveragePair.selector);
        perpManager.deleverage(ETH, pairs);

        // gives loss that creates bad debt
        perpManager.mockSetCumulativeFunding(ETH, -4001e18);

        perpManager.deleverage(ETH, pairs);
    }

    function test_Perp_Deleverage_Fail_TakerNotAtOpenMarginRequirement() public {
        vm.prank(jb);
        perpManager.setPositionLeverage({asset: ETH, account: jb, subaccount: 1, newLeverage: 50e18});
        vm.prank(rite);
        perpManager.setPositionLeverage({asset: ETH, account: rite, subaccount: 1, newLeverage: 50e18});

        _placeTrade({
            asset: ETH,
            taker: rite,
            maker: julien,
            subaccount: 1,
            price: 4000e18,
            amount: 1e18,
            side: Side.SELL
        });

        perpManager.mockSetMarkPrice(ETH, 4500e18);

        _placeTrade({asset: ETH, taker: jb, maker: nate, subaccount: 1, price: 4500e18, amount: 1e18, side: Side.BUY});

        // taker is instantly not at open margin requirement due to fee and open at max leverage
        DeleveragePair[] memory pairs = new DeleveragePair[](1);
        pairs[0] = _getPair(rite, jb);

        vm.startPrank(admin);
        vm.expectRevert(LiquidatorPanel.InvalidDeleveragePair.selector);
        perpManager.deleverage(ETH, pairs);
    }

    function test_Perp_Deleverage_Fail_SameSideTakerMaker() public {
        vm.prank(rite);
        perpManager.setPositionLeverage({asset: ETH, account: rite, subaccount: 1, newLeverage: 50e18});

        _placeTrade({
            asset: ETH,
            taker: rite,
            maker: julien,
            subaccount: 1,
            price: 4000e18,
            amount: 1e18,
            side: Side.SELL
        });

        perpManager.mockSetMarkPrice(ETH, 4500e18);

        _placeTrade({asset: ETH, taker: jb, maker: nate, subaccount: 1, price: 4500e18, amount: 1e18, side: Side.SELL});

        // taker is instantly not at open margin requirement due to fee and open at max leverage
        DeleveragePair[] memory pairs = new DeleveragePair[](1);
        pairs[0] = _getPair(rite, jb);

        vm.startPrank(admin);
        vm.expectRevert(LiquidatorPanel.InvalidDeleveragePair.selector);
        perpManager.deleverage(ETH, pairs);

        pairs[0] = _getPair(rite, julien);

        perpManager.deleverage(ETH, pairs);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                             SETUP HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _fuzzPosition(bool cross) internal {
        params.openPrice = _conformTick(ETH, _hem(_random(), 10e18, 200_000e18));
        params.side = _randomChance(2) ? Side.BUY : Side.SELL;

        vm.prank(rite);
        perpManager.setPositionLeverage({
            asset: ETH,
            account: rite,
            subaccount: 1,
            newLeverage: _hem(_random(), 30e18, 50e18)
        });

        perpManager.mockSetMarkPrice(ETH, params.openPrice);

        _placeTrade({
            asset: ETH,
            taker: rite,
            maker: jb,
            subaccount: 1,
            price: params.openPrice,
            amount: _conformLots(ETH, _hem(_random(), 1e18, 100e18)),
            side: params.side
        });

        // which has more size
        if (_randomChance(2)) {
            _placeTrade({
                asset: ETH,
                taker: rite,
                maker: julien,
                subaccount: 1,
                price: params.openPrice,
                amount: _conformLots(ETH, _hem(_random(), 1e18, 100e18)),
                side: params.side
            });
        } else {
            _placeTrade({
                asset: ETH,
                taker: julien,
                maker: jb,
                subaccount: 1,
                price: params.openPrice,
                amount: _conformLots(ETH, _hem(_random(), 1e18, 100e18)),
                side: params.side
            });
        }

        if (cross) _openBTCPosition();

        // note: current price doesn't matter since the deleverage trade is on the bankruptcy price — just need to ensure liquidatability
        params.currentPrice =
            params.side == Side.BUY ? params.openPrice / 10 : params.openPrice + params.openPrice * 9 / 10;

        perpManager.mockSetMarkPrice(ETH, params.currentPrice);

        uint256 margin = perpManager.getMarginBalance(rite, 1).toUint256();

        params.cumulativeFunding = _hem(_random(), margin, margin + margin / 5).toInt256();

        if (params.side == Side.SELL) params.cumulativeFunding = -params.cumulativeFunding;

        perpManager.mockSetCumulativeFunding(ETH, params.cumulativeFunding);
    }

    function _openBTCPosition() internal {
        vm.prank(rite);
        perpManager.setPositionLeverage({
            asset: BTC,
            account: rite,
            subaccount: 1,
            newLeverage: _hem(_random(), 5e18, 50e18)
        });

        Side side = _randomChance(2) ? Side.BUY : Side.SELL;

        _placeTrade({asset: BTC, taker: rite, maker: nate, subaccount: 1, price: 100_000e18, amount: 1e18, side: side});

        side == Side.BUY ? 100_000e18 / 10 : 100_000e18 + 100_000e18 * 9 / 10;

        perpManager.mockSetMarkPrice(BTC, 100_000e18);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                     PREDICTION & ASSERTION HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _cachePreDeleverageState() internal {
        state.makerPosition = perpManager.getPosition(ETH, rite, 1);
        state.takerPosition = perpManager.getPosition(ETH, jb, 1);

        state.makerPositionBTC = perpManager.getPosition(BTC, rite, 1);
        state.takerPositionBTC = perpManager.getPosition(BTC, jb, 1);

        state.makerAssets = perpManager.getAssets(rite, 1);
        state.takerAssets = perpManager.getAssets(jb, 1);

        state.makerMargin = perpManager.getMarginBalance(rite, 1);
        state.takerMargin = perpManager.getMarginBalance(jb, 1);

        state.makerFreeCollateral = perpManager.getFreeCollateralBalance(rite);
        state.takerFreeCollateral = perpManager.getFreeCollateralBalance(jb);

        state.insuranceFundBalance = perpManager.getInsuranceFundBalance();

        (state.openInterestLong, state.openInterestShort) = perpManager.getOpenInterest(ETH);
    }

    function _predictDeleverage() internal {
        expected.fundingPaymentTaker = perpManager.getPendingFundingPayment(jb, 1);
        expected.fundingPaymentMaker = perpManager.getPendingFundingPayment(rite, 1);
        expected.baseTraded = state.takerPosition.amount.min(state.makerPosition.amount);
        expected.bankruptcyPrice = _getBankruptcyPrice();
        expected.quoteTraded = expected.baseTraded.fullMulDiv(expected.bankruptcyPrice, 1e18);

        (Position memory newTakerPosition, int256 takerPnl) =
            _decreasePosition(state.takerPosition, expected.baseTraded, expected.quoteTraded);
        (Position memory newMakerPosition, int256 makerPnl) =
            _decreasePosition(state.makerPosition, expected.baseTraded, expected.quoteTraded);

        expected.takerPosition = newTakerPosition;
        expected.makerPosition = newMakerPosition;

        expected.takerPnl = takerPnl;
        expected.makerPnl = makerPnl;

        expected.takerMargin = state.takerMargin - expected.fundingPaymentTaker + expected.takerPnl;
        expected.makerMargin = state.makerMargin - expected.fundingPaymentMaker + expected.makerPnl;

        if (expected.takerPosition.amount > 0) expected.takerAssets.push(ETH);
        if (expected.makerPosition.amount > 0) expected.makerAssets.push(ETH);
        if (state.makerAssets.length == 2) expected.makerAssets.push(BTC);

        if (expected.takerAssets.length == 0) {
            if (expected.takerMargin < 0) {
                expected.badDebt = uint256(-expected.takerMargin);
                expected.takerFreeCollateral = state.takerFreeCollateral;
            } else {
                expected.takerFreeCollateral = state.takerFreeCollateral + expected.takerMargin.toUint256();
            }
            expected.takerMargin = 0;
        } else {
            expected.takerFreeCollateral = state.takerFreeCollateral;
        }

        if (expected.makerAssets.length == 0) {
            if (expected.makerMargin < 0) {
                expected.badDebt = uint256(-expected.makerMargin);

                // note: reasons for maker bad debt: rounding error on bankruptcy price calc or numerator < 0
                if (expected.badDebt > 1000) {
                    assertEq(expected.bankruptcyPrice, 0, "bankruptcy price should be zero with large bad debt");
                }

                expected.makerFreeCollateral = state.makerFreeCollateral;
            } else {
                expected.makerFreeCollateral = state.makerFreeCollateral + expected.makerMargin.toUint256();
            }
            expected.makerMargin = 0;
        } else {
            expected.makerFreeCollateral = state.makerFreeCollateral;
        }
    }

    function _assertPostDeleverageState() internal {
        (uint256 longOI, uint256 shortOI) = perpManager.getOpenInterest(ETH);

        // positions
        _assertEq(perpManager.getPosition(ETH, rite, 1), expected.makerPosition, "taker");
        _assertEq(perpManager.getPosition(ETH, jb, 1), expected.takerPosition, "maker");
        _assertEq(perpManager.getPosition(BTC, rite, 1), state.makerPositionBTC, "maker BTC");

        // assets
        _assertEq(perpManager.getAssets(rite, 1), expected.makerAssets, "maker");
        _assertEq(perpManager.getAssets(jb, 1), expected.takerAssets, "taker");

        // margin
        assertEq(perpManager.getMarginBalance(rite, 1), expected.makerMargin, "maker margin wrong");
        assertEq(perpManager.getMarginBalance(jb, 1), expected.takerMargin, "taker margin wrong");

        // free collateral
        assertEq(
            perpManager.getFreeCollateralBalance(rite), expected.makerFreeCollateral, "maker free collateral wrong"
        );
        assertEq(perpManager.getFreeCollateralBalance(jb), expected.takerFreeCollateral, "taker free collateral wrong");

        // protocol
        assertEq(longOI, state.openInterestLong - expected.baseTraded, "long open interest wrong");
        assertEq(shortOI, state.openInterestShort - expected.baseTraded, "short open interest wrong");

        _assertProtocolBalance();
    }

    function _assertProtocolBalance() internal {
        _closeExtraPosition();

        (uint256 longOI, uint256 shortOI) = perpManager.getOpenInterest(BTC);
        (uint256 baseOI, uint256 quoteOI) = perpManager.getOpenInterestBook(BTC);

        assertEq(shortOI, 0, "short btc oi should be 0");
        assertEq(longOI, 0, "long btc oi should be 0");
        assertEq(baseOI, 0, "base btc oi should be 0");
        assertEq(quoteOI, 0, "quote btc oi should be 0");

        (longOI, shortOI) = perpManager.getOpenInterest(BTC);
        (baseOI, quoteOI) = perpManager.getOpenInterestBook(BTC);

        assertEq(shortOI, 0, "short eth oi should be 0");
        assertEq(longOI, 0, "long eth oi should be 0");
        assertEq(baseOI, 0, "base eth oi should be 0");
        assertEq(quoteOI, 0, "quote eth oi should be 0");

        assertEq(perpManager.getMarginBalance(rite, 1), 0, "rite margin should be cleared");
        assertEq(perpManager.getMarginBalance(jb, 1), 0, "jb margin should be cleared");
        assertEq(perpManager.getMarginBalance(nate, 1), 0, "jb margin should be cleared");
        assertEq(perpManager.getMarginBalance(julien, 1), 0, "julien margin should be cleared");

        uint256 balance = perpManager.getInsuranceFundBalance() + perpManager.getFreeCollateralBalance(rite)
            + perpManager.getFreeCollateralBalance(jb) + perpManager.getFreeCollateralBalance(nate)
            + perpManager.getFreeCollateralBalance(julien);

        assertApproxEqAbs(usdc.balanceOf(address(perpManager)), balance, 1, "protocol balance wrong");
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                              MISC HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @dev closes any remaining position so that counterparty pnl is realized & protocol balance can be asserted
    function _closeExtraPosition() internal {
        // set mark back to initial
        perpManager.mockSetMarkPrice(ETH, params.openPrice);
        perpManager.mockSetMarkPrice(BTC, 100_000e18);

        // close remaining ETH positions either via liquidation or market
        if (expected.takerPosition.amount > 0) {
            if (perpManager.isLiquidatable(julien, 1)) {
                _createLimitOrder({
                    asset: ETH,
                    maker: jb,
                    subaccount: 1,
                    price: params.openPrice,
                    amount: expected.takerPosition.amount,
                    side: expected.takerPosition.isLong ? Side.SELL : Side.BUY
                });
                vm.prank(admin);
                perpManager.liquidate(ETH, julien, 1);
            } else {
                _placeTrade({
                    asset: ETH,
                    taker: julien,
                    maker: jb,
                    subaccount: 1,
                    price: params.openPrice,
                    amount: expected.takerPosition.amount,
                    side: expected.takerPosition.isLong ? Side.BUY : Side.SELL
                });
            }
        } else {
            if (perpManager.isLiquidatable(rite, 1)) {
                _createLimitOrder({
                    asset: ETH,
                    maker: julien,
                    subaccount: 1,
                    price: params.openPrice,
                    amount: expected.makerPosition.amount,
                    side: expected.makerPosition.isLong ? Side.BUY : Side.SELL
                });
                vm.prank(admin);
                perpManager.liquidate(ETH, rite, 1);
            } else {
                _placeTrade({
                    asset: ETH,
                    taker: julien,
                    maker: rite,
                    subaccount: 1,
                    price: params.openPrice,
                    amount: expected.makerPosition.amount,
                    side: expected.makerPosition.isLong ? Side.BUY : Side.SELL
                });
            }
        }

        if (state.makerPositionBTC.amount > 0) _closeBTC();
    }

    function _closeBTC() internal {
        if (perpManager.isLiquidatable(rite, 1)) {
            _createLimitOrder({
                asset: BTC,
                maker: nate,
                subaccount: 1,
                price: 100_000e18,
                amount: state.makerPositionBTC.amount,
                side: state.makerPositionBTC.isLong ? Side.BUY : Side.SELL
            });
            vm.prank(admin);
            perpManager.liquidate(BTC, rite, 1);
        } else {
            _placeTrade({
                asset: BTC,
                taker: nate,
                maker: rite,
                subaccount: 1,
                price: 100_000e18,
                amount: state.makerPositionBTC.amount,
                side: state.makerPositionBTC.isLong ? Side.BUY : Side.SELL
            });
        }
    }

    function _assertEq(Position memory a, Position memory b, string memory trader) internal pure {
        assertEq(a.amount, b.amount, string(abi.encodePacked(trader, " ", "position wrong: amount")));
        assertEq(a.openNotional, b.openNotional, string(abi.encodePacked(trader, " ", "position wrong: openNotional")));
        assertEq(a.isLong, b.isLong, string(abi.encodePacked(trader, " ", "position wrong: isLong")));
        assertEq(a.leverage, b.leverage, string(abi.encodePacked(trader, " ", "position wrong: leverage")));
        assertEq(
            a.lastCumulativeFunding,
            b.lastCumulativeFunding,
            string(abi.encodePacked(trader, " ", "position wrong: cumulativeFunding"))
        );
    }

    function _assertEq(bytes32[] memory a, bytes32[] memory b, string memory trader) internal pure {
        assertEq(a.length, b.length, string(abi.encodePacked(trader, " ", "assets length wrong")));
        for (uint256 i; i < a.length; i++) {
            assertEq(a[i], b[i], string(abi.encodePacked(trader, " ", "assets index ", vm.toString(i), " wrong")));
        }
    }

    function _getBankruptcyPrice() internal view returns (uint256 bankruptcyPrice) {
        uint256 notionalETH = state.makerPosition.amount.fullMulDiv(perpManager.getMarkPrice(ETH), 1e18);
        uint256 notionalBTC = state.makerPositionBTC.amount.fullMulDiv(perpManager.getMarkPrice(BTC), 1e18);
        uint256 totalNotional = notionalETH + notionalBTC;

        int256 margin = state.makerMargin - expected.fundingPaymentMaker;

        int256 proratedMargin = margin.abs().fullMulDiv(notionalETH, totalNotional).toInt256();

        // prorated margin again, based on amount closed
        proratedMargin = proratedMargin.abs().fullMulDiv(expected.baseTraded, state.makerPosition.amount).toInt256();

        if (margin < 0) proratedMargin = -proratedMargin;

        uint256 openNotional =
            state.makerPosition.openNotional.fullMulDiv(expected.baseTraded, state.makerPosition.amount);

        int256 numerator = state.makerPosition.isLong
            ? openNotional.toInt256() - proratedMargin
            : openNotional.toInt256() + proratedMargin;

        if (numerator <= 0) return 0;

        return numerator.abs().fullMulDiv(1e18, expected.baseTraded);
    }

    function _getPair(address maker, address taker) internal pure returns (DeleveragePair memory pair) {
        pair.maker = PerpAccount(maker, 1);
        pair.taker = PerpAccount(taker, 1);
    }

    function _decreasePosition(Position memory position, uint256 baseAmount, uint256 quoteAmount)
        internal
        view
        returns (Position memory, int256 rpnl)
    {
        Side side = position.isLong ? Side.SELL : Side.BUY;

        PositionUpdateResult memory result = position.processTrade(side, quoteAmount, baseAmount);

        if (position.amount > 0) position.lastCumulativeFunding = params.cumulativeFunding;

        return (position, result.rpnl);
    }
}
