// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "../PerpManagerTestBase.sol";

import {TestPlus} from "lib/solady/test/utils/TestPlus.sol";

import {Constants} from "../../../contracts/perps/types/Constants.sol";
// `Account` clashes with `stdCheat.Account` struct declaration
import {Account as PerpAccount} from "../../../contracts/perps/types/Structs.sol";
import {ClearingHouseLib} from "../../../contracts/perps/types/ClearingHouse.sol";
import {OwnableRoles} from "../../../lib/solady/src/auth/OwnableRoles.sol";
import {LiquidatorPanel} from "../../../contracts/perps/modules/LiquidatorPanel.sol";

contract Perp_DelistClose_Test is PerpManagerTestBase {
    using FixedPointMathLib for *;
    using SafeCastLib for uint256;

    struct UserPosition {
        // Perp's `Account` clashes with `stdCheat.Account` struct declaration
        PerpAccount user;
        bytes32 asset;
        uint256 openPrice;
        uint256 amount;
        uint256 leverage;
        Side side;
    }

    struct Params {
        uint256 minMarkPrice;
        uint256 maxMarkPrice;
        uint256 originalPrice;
        uint256 price;
        UserPosition[] positions;
    }

    struct UserDelistData {
        PerpAccount user;
        uint256 fee;
        uint256 badDebt;
        int256 marginBalance;
        int256 rpnl;
        int256 fundingPayment;
        uint256 quoteTraded;
        uint256 baseTraded;
        Position initialPosition;
        uint256 initialFreeCollateral;
        uint256 expectedFreeCollateral;
    }

    struct State {
        uint256 insuranceFundBalance;
        uint256 markPrice;
        UserDelistData[] users;
    }

    struct ExpectedResult {
        uint256 totalFees;
        uint256 totalBadDebt;
        UserDelistData[] users;
    }

    address liquidator = makeAddr("liquidator");
    address nonLiquidator = makeAddr("nonLiquidator");

    Params params;
    State state;
    ExpectedResult expected;

    error Unauthorized();

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        perpManager.grantRoles(liquidator, Constants.LIQUIDATOR_ROLE);
        perpManager.insuranceFundDeposit(1_000_000_000e18);
        vm.stopPrank();

        usdc.mint(julien, 1_000_000_000e18);
        vm.prank(julien);
        perpManager.deposit(julien, 1_000_000_000e18);

        params.originalPrice = params.price = 4000e18;
        params.minMarkPrice = params.originalPrice / 10;
        params.maxMarkPrice = params.originalPrice * 10;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                        ACCESS CONTROL TESTS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_Perp_DelistClose_Revert_OnlyLiquidator() public {
        _delistMarket(ETH);

        PerpAccount[] memory accounts = new PerpAccount[](1);
        accounts[0] = PerpAccount(julien, 0);

        vm.prank(nonLiquidator);
        vm.expectRevert(Unauthorized.selector);
        perpManager.delistClose(ETH, accounts);

        vm.prank(liquidator);
        perpManager.delistClose(ETH, accounts);
    }

    function test_Perp_DelistClose_AdminCanCall() public {
        _delistMarket(ETH);

        PerpAccount[] memory accounts = new PerpAccount[](1);
        accounts[0] = PerpAccount(julien, 0);

        vm.prank(admin);
        perpManager.delistClose(ETH, accounts);
    }

    function test_Perp_DelistClose_MarketNotDelisted() public {
        PerpAccount[] memory accounts = new PerpAccount[](1);
        accounts[0] = PerpAccount(julien, 0);

        vm.prank(liquidator);
        vm.expectRevert(abi.encodeWithSelector(LiquidatorPanel.MarketNotDelisted.selector));
        perpManager.delistClose(ETH, accounts);
    }

    function test_Perp_DelistClose_EmptyAccountsArray() public {
        _delistMarket(ETH);

        PerpAccount[] memory accounts = new PerpAccount[](0);

        vm.prank(liquidator);
        perpManager.delistClose(ETH, accounts);
    }

    function test_Perp_DelistClose_AccountWithoutPosition() public {
        _delistMarket(ETH);

        PerpAccount[] memory accounts = new PerpAccount[](1);
        accounts[0] = PerpAccount(julien, 0);

        uint256 initialBalance = perpManager.getFreeCollateralBalance(rite);

        vm.prank(liquidator);
        perpManager.delistClose(ETH, accounts);

        assertEq(perpManager.getFreeCollateralBalance(rite), initialBalance);
    }

    function test_Perp_DelistClose_SingleAccount(uint256) public {
        params.price = _conformTick(ETH, _hem(_random(), params.minMarkPrice, params.maxMarkPrice));

        _openPosition(
            _createRandomUserPosition({asset: ETH, user: _newAddress(_random()), subaccount: 1, random: _random()})
        );

        _delistMarket(ETH);

        PerpAccount[] memory accounts = new PerpAccount[](1);
        accounts[0] = params.positions[0].user;

        _cachePreDelistState(accounts, ETH);
        _predictDelistClose(accounts, ETH);

        vm.prank(liquidator);
        perpManager.delistClose(ETH, accounts);

        _assertPostDelistState(ETH);
    }

    function test_Perp_DelistClose_MultipleAccounts(uint256) public {
        params.price = _conformTick(ETH, _hem(_random(), params.minMarkPrice, params.maxMarkPrice));

        uint256 positionAmount = _hem(_random(), 2, 10);

        for (uint256 i; i < positionAmount; i++) {
            _openPosition(
                _createRandomUserPosition({
                    asset: ETH,
                    user: _newAddress(_random()),
                    subaccount: i + 1,
                    random: _random()
                })
            );
        }

        _delistMarket(ETH);

        PerpAccount[] memory accounts = new PerpAccount[](positionAmount);
        for (uint256 i; i < positionAmount; i++) {
            accounts[i] = params.positions[i].user;
        }

        _cachePreDelistState(accounts, ETH);
        _predictDelistClose(accounts, ETH);

        vm.prank(liquidator);
        perpManager.delistClose(ETH, accounts);

        _assertPostDelistState(ETH);
    }

    function test_Perp_DelistClose_DuplicateAccounts(uint256) public {
        params.price = _conformTick(ETH, _hem(_random(), params.minMarkPrice, params.maxMarkPrice));

        _openPosition(
            _createRandomUserPosition({asset: ETH, user: _newAddress(_random()), subaccount: 1, random: _random()})
        );

        _delistMarket(ETH);

        PerpAccount[] memory dupAccounts = new PerpAccount[](5);
        for (uint256 i; i < 5; i++) {
            dupAccounts[i] = params.positions[0].user;
        }

        PerpAccount[] memory accounts = new PerpAccount[](1);
        accounts[0] = params.positions[0].user;

        _cachePreDelistState(accounts, ETH);
        _predictDelistClose(accounts, ETH);

        vm.prank(liquidator);
        perpManager.delistClose(ETH, dupAccounts);

        _assertPostDelistState(ETH);
    }

    function test_Perp_DelistClose_AccountWithMultiplePositions(uint256) public {
        address user = _newAddress(_random());

        // Ensure sufficient free collateral for margin rebalancing
        uint256 earlyDeposit = 1_000_000e18;
        usdc.mint(user, earlyDeposit);
        vm.startPrank(user);
        usdc.approve(address(perpManager), earlyDeposit);
        perpManager.deposit(user, earlyDeposit);
        vm.stopPrank();

        _openPosition(_createRandomUserPosition({asset: ETH, user: user, subaccount: 1, random: _random()}));
        _openPosition(_createRandomUserPosition({asset: BTC, user: user, subaccount: 1, random: _random()}));

        _delistMarket(ETH);

        PerpAccount[] memory accounts = new PerpAccount[](1);
        accounts[0] = params.positions[0].user;

        _cachePreDelistState(accounts, ETH);
        _predictDelistClose(accounts, ETH);

        vm.prank(liquidator);
        perpManager.delistClose(ETH, accounts);

        _assertPostDelistState(ETH);
        assertGt(perpManager.getPosition(BTC, user, 2).amount, 0, "BTC position should remain");
    }

    function test_Perp_DelistClose_WithFundingPayments(uint256) public {
        _openPosition(
            _createRandomUserPosition({asset: ETH, user: _newAddress(_random()), subaccount: 1, random: _random()})
        );

        vm.warp(block.timestamp + 1 days);
        int256 fundingPayment = int256(_hem(_random(), 0.01e18, 10e18));
        fundingPayment = _random() % 2 == 0 ? fundingPayment : -fundingPayment;
        perpManager.mockSetCumulativeFunding(ETH, fundingPayment);

        _delistMarket(ETH);

        PerpAccount[] memory accounts = new PerpAccount[](1);
        accounts[0] = params.positions[0].user;

        _cachePreDelistState(accounts, ETH);
        _predictDelistClose(accounts, ETH);

        vm.prank(liquidator);
        perpManager.delistClose(ETH, accounts);

        _assertPostDelistState(ETH);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                         DELIST CLOSE HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _cachePreDelistState(PerpAccount[] memory accounts, bytes32 asset) internal {
        state.insuranceFundBalance = perpManager.getInsuranceFundBalance();
        state.markPrice = perpManager.getMarkPrice(asset);

        // Cache user data
        delete state.users;
        for (uint256 i = 0; i < accounts.length; i++) {
            UserDelistData memory userData;
            userData.user = accounts[i];
            userData.initialPosition = perpManager.getPosition(asset, accounts[i].account, accounts[i].subaccount);
            userData.initialFreeCollateral = perpManager.getFreeCollateralBalance(accounts[i].account);
            state.users.push(userData);
        }
    }

    function _predictDelistClose(PerpAccount[] memory accounts, bytes32 asset) internal {
        delete expected.users;
        expected.totalFees = 0;
        expected.totalBadDebt = 0;

        // Get current cumulative funding for the asset
        int256 currentCumulativeFunding = perpManager.getCumulativeFunding(asset);

        for (uint256 i = 0; i < accounts.length; i++) {
            UserDelistData memory userData = state.users[i];

            if (userData.initialPosition.amount == 0) {
                expected.users.push(userData);
                continue;
            }

            _predictUserDelistClose(userData, asset, currentCumulativeFunding);
            expected.users.push(userData);
        }
    }

    function _predictUserDelistClose(UserDelistData memory userData, bytes32 asset, int256 currentCumulativeFunding)
        internal
    {
        _calculateUserTradeAmounts(userData, asset);
        _calculateUserPnl(userData);
        _calculateUserFundingPayment(userData, currentCumulativeFunding);
        _calculateUserMarginBalance(userData);
        _handleUserRebalancing(userData);
        _handleUserBadDebt(userData);
        _accumulateUserTotals(userData);
    }

    function _calculateUserTradeAmounts(UserDelistData memory userData, bytes32 /* asset */ ) internal view {
        userData.baseTraded = userData.initialPosition.amount;
        userData.quoteTraded = userData.baseTraded.fullMulDiv(state.markPrice, 1e18);
        userData.fee = userData.quoteTraded * TAKER_BASE_FEE_RATE / 10_000_000;
    }

    function _calculateUserPnl(UserDelistData memory userData) internal pure {
        if (userData.initialPosition.isLong) {
            userData.rpnl = int256(userData.quoteTraded) - int256(userData.initialPosition.openNotional);
        } else {
            userData.rpnl = int256(userData.initialPosition.openNotional) - int256(userData.quoteTraded);
        }
    }

    function _calculateUserFundingPayment(UserDelistData memory userData, int256 currentCumulativeFunding)
        internal
        pure
    {
        userData.fundingPayment = userData.initialPosition.realizeFundingPayment(currentCumulativeFunding);
    }

    function _calculateUserMarginBalance(UserDelistData memory userData) internal view {
        int256 currentMargin = perpManager.getMarginBalance(userData.user.account, userData.user.subaccount);
        userData.marginBalance = currentMargin + userData.rpnl - userData.fundingPayment - int256(userData.fee);
    }

    function _handleUserRebalancing(UserDelistData memory userData) internal pure {
        // mimic rebalanceClose logic
        if (userData.marginBalance > 0) {
            userData.expectedFreeCollateral = userData.initialFreeCollateral + uint256(userData.marginBalance);
            userData.marginBalance = 0;
        } else {
            userData.expectedFreeCollateral = userData.initialFreeCollateral;
        }
    }

    function _handleUserBadDebt(UserDelistData memory userData) internal pure {
        if (userData.marginBalance < 0) {
            userData.marginBalance += int256(userData.fee);

            if (userData.marginBalance > 0) {
                userData.fee = uint256(userData.marginBalance);
                userData.marginBalance = 0;
                userData.badDebt = 0;
            } else {
                userData.badDebt = uint256(-userData.marginBalance);
                userData.fee = 0;
                userData.marginBalance = 0;
            }
        } else {
            userData.badDebt = 0;
        }
    }

    function _accumulateUserTotals(UserDelistData memory userData) internal {
        expected.totalFees += userData.fee;
        expected.totalBadDebt += userData.badDebt;
    }

    function _assertPostDelistState(bytes32 asset) internal view {
        for (uint256 i = 0; i < expected.users.length; i++) {
            UserDelistData memory expectedUser = expected.users[i];

            Position memory finalPosition =
                perpManager.getPosition(asset, expectedUser.user.account, expectedUser.user.subaccount);
            assertEq(finalPosition.amount, 0, "Position should be closed");
            assertEq(finalPosition.openNotional, 0, "Open notional should be zero");

            int256 finalMargin = perpManager.getMarginBalance(expectedUser.user.account, expectedUser.user.subaccount);
            assertEq(finalMargin, expectedUser.marginBalance, "Margin balance mismatch");

            uint256 finalFreeCollateral = perpManager.getFreeCollateralBalance(expectedUser.user.account);
            assertEq(finalFreeCollateral, expectedUser.expectedFreeCollateral, "Free collateral balance mismatch");
        }

        uint256 finalInsuranceBalance = perpManager.getInsuranceFundBalance();
        uint256 expectedInsuranceBalance = state.insuranceFundBalance + expected.totalFees - expected.totalBadDebt;
        assertEq(finalInsuranceBalance, expectedInsuranceBalance, "Insurance fund balance mismatch");
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _openPosition(UserPosition memory position) internal {
        usdc.mint(position.user.account, position.amount.fullMulDiv(position.openPrice, 1e18));

        vm.startPrank(position.user.account);
        usdc.approve(address(perpManager), position.amount.fullMulDiv(position.openPrice, 1e18));
        perpManager.setPositionLeverage(
            position.asset, position.user.account, position.user.subaccount, position.leverage
        );
        vm.stopPrank();

        vm.prank(admin);
        perpManager.mockSetMarkPrice(position.asset, position.openPrice);

        // Use different subaccounts to isolate margin requirements and prevent liquidatable positions on the maker side
        uint256 julienSubaccount = params.positions.length;
        _placeTrade(
            position.asset,
            position.user.account,
            julien,
            position.openPrice,
            position.amount,
            position.side,
            julienSubaccount
        );
    }

    function _createRandomUserPosition(bytes32 asset, address user, uint256 subaccount, uint256 random)
        internal
        returns (UserPosition memory position)
    {
        position = UserPosition({
            asset: asset,
            user: PerpAccount(user, subaccount),
            openPrice: _conformTick(asset, _hem(random, params.minMarkPrice, params.maxMarkPrice)),
            amount: _conformLots(asset, _hem(random, 1e18, 100e18)),
            leverage: _hem(random, 1e18, 20e18),
            side: _hem(random, 0, 1) == 0 ? Side.BUY : Side.SELL
        });

        params.positions.push(position);
    }

    function _newAddress(uint256 random) internal returns (address) {
        address addr = _randomUniqueAddress(random);
        vm.assume(
            addr != julien && addr != rite && addr != jb && addr != nate && addr != admin && addr != liquidator
                && addr != nonLiquidator
        );
        for (uint256 i = 0; i < params.positions.length; i++) {
            vm.assume(addr != params.positions[i].user.account);
        }
        return addr;
    }

    function _delistMarket(bytes32 asset) internal {
        vm.startPrank(admin);
        perpManager.mockSetMarkPrice(asset, params.price);
        perpManager.deactivateMarket(asset);
        perpManager.delistMarket(asset);
        vm.stopPrank();
    }
}
