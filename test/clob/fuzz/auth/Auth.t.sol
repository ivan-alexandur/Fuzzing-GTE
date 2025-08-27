// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CLOBTestBase, ERC20Harness} from "test/clob/utils/CLOBTestBase.sol";
import {ICLOB} from "contracts/clob/ICLOB.sol";
import {CLOBManager} from "contracts/clob/CLOBManager.sol";
import {ICLOBManager, SettingsParams} from "contracts/clob/ICLOBManager.sol";
import {AccountManager} from "contracts/account-manager/AccountManager.sol";
import {FeeDataLib, PackedFeeRatesLib} from "contracts/clob/types/FeeData.sol";
import {BookLib, CLOBStorageLib, MarketSettings} from "contracts/clob/types/Book.sol";
import {Side} from "contracts/clob/types/Order.sol";
import {CLOB} from "contracts/clob/CLOB.sol";
import {OwnableRoles, Ownable} from "@solady/auth/OwnableRoles.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {FeeTiers} from "contracts/clob/types/FeeData.sol";
import "forge-std/console.sol";
/// @notice This contract tests the functionality that is auth gated, like max limits per tx, min order size, etc
import "forge-std/console.sol";

contract AuthTest is CLOBTestBase {
    using FixedPointMathLib for uint256;

    function test_CollectFees() public {
        address taker = users[0];
        address maker = users[1];
        uint256 amountInBase = 10 ether;
        uint256 price = TICK_SIZE * 10_000;
        uint256 amountInQuote = quoteTokenAmount(amountInBase, price);

        setupOrder(Side.BUY, maker, amountInQuote, price);
        setupTokens(Side.SELL, taker, amountInBase, price, true);

        ICLOB.PlaceOrderArgs memory args = ICLOB.PlaceOrderArgs({
            side: Side.SELL,
            clientOrderId: 0,
            tif: ICLOB.TiF.FOK,
            expiryTime: 0,
            limitPrice: price,
            amount: amountInBase,
            baseDenominated: true
        });

        vm.prank(taker);
        clob.placeOrder(taker, args);

        uint256 takerFee = getTakerFee(taker, amountInQuote);
        uint256 feesClaimed = accountManager.collectFees(address(quoteToken), address(this));

        assertEq(feesClaimed, takerFee);
        assertEq(quoteToken.balanceOf(address(this)), feesClaimed);
    }

    function test_DeployClob_MakretExists_ExpectRevert() public {
        vm.expectRevert(CLOBManager.MarketExists.selector);
        clobManager.createMarket(address(quoteToken), address(baseToken), settings);

        vm.expectRevert(CLOBManager.MarketExists.selector);
        clobManager.createMarket(address(baseToken), address(quoteToken), settings);
    }

    function testFuzz_OnlyMarket_ExpectRevert(address sender) public {
        _assumeEOA(sender);
        vm.startPrank(sender);

        vm.expectRevert(AccountManager.MarketUnauthorized.selector);
        accountManager.creditAccount(sender, sender, 0);

        ICLOB.SettleParams memory p;
        vm.expectRevert(AccountManager.MarketUnauthorized.selector);
        accountManager.settleIncomingOrder(p);
    }

    function test_get_market_address() public view {
        address marketAddress = clobManager.getMarketAddress(address(quoteToken), address(baseToken));
        assertEq(address(clob), marketAddress);
    }

    function testFuzz_createMarket_badOwner_expectRevert(address caller) public {
        _assumeEOA(caller);
        vm.prank(caller);

        vm.expectRevert(Ownable.Unauthorized.selector);
        clobManager.createMarket(address(quoteToken), address(baseToken), settings);
    }

    function test_SetAccountFeeTiers_ExpectRevert() public {
        address[] memory accounts = new address[](2);
        FeeTiers[] memory tiers = new FeeTiers[](1);

        vm.expectRevert(AccountManager.UnmatchingArrayLengths.selector);
        clobManager.setAccountFeeTiers(accounts, tiers);
        accounts = new address[](1);
        /// @dev Unfortunately, we cant test the 3-27 3.7 audit fix to check the FeeTier enum size
        /// because that would require changing the enum. Even if we packed the below value using yul
        /// it would panic during the function call
        // tiers[0] = FeeTiers(uint8(16));
        // vm.expectRevert(abi.encodeWithSelector(CLOBManager.InvalidTierLength_ReduceFeeTierEnumSize.selector));
        // clobManager.setAccountFeeTiers(accounts, feeTiers);
    }

    // @todo not a fuzz test, move to factroy tests
    function test_createMarket_invalid_token_params_expectRevert() public {
        address quote = address(11);
        address base = address(22);

        vm.expectRevert(CLOBManager.InvalidPair.selector);
        clobManager.createMarket(quote, quote, settings);

        vm.expectRevert(CLOBManager.InvalidPair.selector);
        clobManager.createMarket(base, base, settings);

        vm.expectRevert(CLOBManager.InvalidTokenAddress.selector);
        clobManager.createMarket(quote, address(0), settings);

        vm.expectRevert(CLOBManager.InvalidTokenAddress.selector);
        clobManager.createMarket(address(0), base, settings);
    }

    // @todo not a fuzz test, move to clobManager tests
    function test_deployCLOBManager_invalid_params_expect_revert() public {
        uint16[] memory makerFees;
        uint16[] memory takerFees;

        // This check isnt necessary now that the beacon is getting called, but it does make the problem explciit
        vm.expectRevert(CLOBManager.InvalidBeaconAddress.selector);
        CLOBManager f = new CLOBManager(address(0), address(accountManager));

        // Fee rates validation is now handled in AccountManager constructor
        // This test is no longer relevant since CLOBManager doesn't take fee parameters

        // Fee rates validation is now handled in AccountManager constructor
        // This test is no longer relevant since CLOBManager doesn't take fee parameters

        f = new CLOBManager(clobBeacon, address(accountManager));
    }

    // @todo not a fuzz test
    function test_deployMarket_market_already_exists_expect_revert() public {
        vm.expectRevert(CLOBManager.MarketExists.selector);
        deployClob();
    }

    function test_SetAccountFeeTiers() public {
        address account = users[0];
        FeeTiers feeTier = FeeTiers.ONE;

        address[] memory accounts = new address[](1);
        FeeTiers[] memory feeTiers = new FeeTiers[](1);
        accounts[0] = account;
        feeTiers[0] = feeTier;

        vm.expectEmit();
        emit FeeDataLib.AccountFeeTierUpdated(accountManager.getEventNonce() + 1, account, feeTier);
        clobManager.setAccountFeeTiers(accounts, feeTiers);

        feeTier = accountManager.getFeeTier(account);
        assertEq(uint256(feeTier), 1);
    }

    function testFuzz_editMaxLimitsPerTx(uint8 newMaxLimits) public {
        vm.assume(newMaxLimits > 0);

        vm.expectEmit();
        emit CLOBStorageLib.MaxLimitOrdersPerTxUpdated(clob.getEventNonce() + 1, newMaxLimits);

        vm.prank(address(clobManager));
        clob.setMaxLimitsPerTx(newMaxLimits);

        MarketSettings memory s = clob.getMarketSettings();
        assertEq(s.maxLimitsPerTx, newMaxLimits);
    }

    function test_editMaxLimitsPerTx_expect_revert_invalid() public {
        // Test 1: maxLimits value is 0 (invalid)
        vm.expectRevert(abi.encodeWithSelector(CLOBStorageLib.NewMaxLimitsPerTxInvalid.selector));
        clobManager.setMaxLimitsPerTx(clob, 0);
    }

    function testFuzz_editMaxLimitsPerTx_expect_revert_bad_auth(address caller) public {
        vm.assume(caller != address(this) && caller != address(clobManager) && caller != clobManager.owner());
        _assumeEOA(caller);

        // Caller is not clob manager owner
        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        clobManager.setMaxLimitsPerTx(clob, 1);

        // Caller is not factory
        vm.expectRevert(abi.encodeWithSelector(CLOB.ManagerUnauthorized.selector));
        clob.setMaxLimitsPerTx(0);
    }

    function testFuzz_setMaxLimitsExempt(address account, bool toggle) public {
        address[] memory accounts = new address[](1);
        bool[] memory toggles = new bool[](1);

        accounts[0] = account;
        toggles[0] = toggle;

        bool status = clobManager.getMaxLimitExempt(account);

        // skip if noop event
        if (status == toggle) return;

        _assumeEOA(account);

        clobManager.setMaxLimitsExempt(accounts, toggles);

        assertEq(toggle, clobManager.getMaxLimitExempt(account));
    }

    function testFuzz_setMaxLimitsExempt_expect_revert(address caller, address account, bool toggle) public {
        _assumeEOA(caller);

        address[] memory accounts = new address[](1);
        bool[] memory toggles = new bool[](1);
        accounts[0] = account;

        _setMaxLimitWhitelist(account, toggle);

        vm.prank(caller);
        console.logBytes4(Ownable.Unauthorized.selector);
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));

        clobManager.setMaxLimitsExempt(accounts, toggles);
    }

    /// @dev it's more about making sure that `account` is not one of the contracts used in the test suite,
    ///      than it actually being an EOA
    function _assumeEOA(address account) internal view {
        vm.assume(account != address(0) && account.code.length == 0);
    }

    function test_setTickSize_BelowMinimum_ExpectRevert(uint256 tickSize) public {
        uint256 lotSize = clob.getMarketSettings().lotSizeInBase;

        vm.assume(lotSize.fullMulDiv(tickSize, 1e18) == 0);

        vm.expectRevert(CLOBStorageLib.NewTickSizeInvalid.selector);
        clobManager.setTickSize(clob, tickSize);
    }

    function test_setLotSize_BelowMinimum_ExpectRevert(uint256 lotSize) public {
        uint256 tickSize = clob.getMarketSettings().tickSize;

        vm.assume(tickSize.fullMulDiv(lotSize, 1e18) == 0);

        vm.expectRevert(CLOBStorageLib.NewLotSizeInvalid.selector);
        clobManager.setLotSizeInBase(clob, lotSize);
    }

    function test_setLotSize_AboveMinOrderAmount_ExpectRevert(uint256 lotSize) public {
        uint256 minOrderAmount = clob.getMarketSettings().minLimitOrderAmountInBase;

        vm.assume(lotSize > minOrderAmount);

        vm.expectRevert(CLOBStorageLib.NewLotSizeInvalid.selector);
        clobManager.setLotSizeInBase(clob, lotSize);
    }

    function testFuzz_setMinLimitOrderAmount_BelowMinimum_ExpectRevert(uint256 invalidAmount) public {
        vm.assume(invalidAmount < clob.getMarketSettings().lotSizeInBase);

        vm.expectRevert(CLOBStorageLib.NewMinLimitOrderAmountInvalid.selector);
        clobManager.setMinLimitOrderAmountInBase(clob, invalidAmount);
    }

    function testFuzz_setMinLimitOrderAmount_Success(uint256 validMinAmount) public {
        vm.assume(validMinAmount > clob.getMarketSettings().lotSizeInBase);

        vm.expectEmit();
        emit CLOBStorageLib.MinLimitOrderAmountInBaseUpdated(clob.getEventNonce() + 1, validMinAmount);

        clobManager.setMinLimitOrderAmountInBase(clob, validMinAmount);

        MarketSettings memory _settings = clob.getMarketSettings();

        assertEq(_settings.minLimitOrderAmountInBase, validMinAmount);
    }

    function testFuzz_setTickSizeAndLotSize_Success(uint256 validTickSize, uint256 validLotSize) public {
        vm.assume(validLotSize < 10 ether);
        vm.assume(validTickSize < 10 ether);
        vm.assume(validTickSize.fullMulDiv(validLotSize, 1e18) > 0);

        // min limit order amount must be greater than lot size
        clobManager.setMinLimitOrderAmountInBase(clob, type(uint256).max);

        // if we're increasing tick, set tick first else set lot size first
        if (validTickSize > clob.getMarketSettings().tickSize) {
            vm.expectEmit();
            emit CLOBStorageLib.TickSizeUpdated(clob.getEventNonce() + 1, validTickSize);
            clobManager.setTickSize(clob, validTickSize);

            vm.expectEmit();
            emit CLOBStorageLib.LotSizeInBaseUpdated(clob.getEventNonce() + 1, validLotSize);
            clobManager.setLotSizeInBase(clob, validLotSize);
        } else {
            vm.expectEmit();
            emit CLOBStorageLib.LotSizeInBaseUpdated(clob.getEventNonce() + 1, validLotSize);
            clobManager.setLotSizeInBase(clob, validLotSize);

            vm.expectEmit();
            emit CLOBStorageLib.TickSizeUpdated(clob.getEventNonce() + 1, validTickSize);
            clobManager.setTickSize(clob, validTickSize);
        }

        MarketSettings memory _settings = clob.getMarketSettings();
        assertEq(_settings.tickSize, validTickSize);
        assertEq(_settings.lotSizeInBase, validLotSize);
    }

    function test_createMarket_InvalidSettings_ExpectRevert() public {
        address newQuoteToken = address(new ERC20Harness("New Quote Token", "NQT"));
        address newBaseToken = address(new ERC20Harness("New Base Token", "NBT"));

        // Test 1: tickSize.fullMulDiv(minLimitOrderAmountInBase, baseSize) == 0
        // This happens when tickSize is very small relative to baseSize (1e18)
        SettingsParams memory settings1 = SettingsParams({
            owner: address(this),
            maxLimitsPerTx: 10,
            minLimitOrderAmountInBase: 100,
            tickSize: 1, // Very small tick size will cause the product to round to 0
            lotSizeInBase: 1
        });

        vm.expectRevert(CLOBManager.InvalidSettings.selector);
        clobManager.createMarket(newQuoteToken, newBaseToken, settings1);

        // Test 2: minLimitOrderAmountInBase < MIN_MIN_LIMIT_ORDER_AMOUNT_BASE (100)
        SettingsParams memory settings2 = SettingsParams({
            owner: address(this),
            maxLimitsPerTx: 10,
            minLimitOrderAmountInBase: 99, // Below minimum of 100
            tickSize: 1 ether,
            lotSizeInBase: 1
        });

        vm.expectRevert(CLOBManager.InvalidSettings.selector);
        clobManager.createMarket(newQuoteToken, newBaseToken, settings2);

        // Test 3: maxLimitsPerTx == 0
        SettingsParams memory settings3 = SettingsParams({
            owner: address(this),
            maxLimitsPerTx: 0, // Zero max limits
            minLimitOrderAmountInBase: 100,
            tickSize: 1 ether,
            lotSizeInBase: 1
        });

        vm.expectRevert(CLOBManager.InvalidSettings.selector);
        clobManager.createMarket(newQuoteToken, newBaseToken, settings3);

        // Test 4: tickSize == 0
        SettingsParams memory settings4 = SettingsParams({
            owner: address(this),
            maxLimitsPerTx: 10,
            minLimitOrderAmountInBase: 100,
            tickSize: 0, // Zero tick size
            lotSizeInBase: 1
        });

        vm.expectRevert(CLOBManager.InvalidSettings.selector);
        clobManager.createMarket(newQuoteToken, newBaseToken, settings4);

        // Test 5: lotSizeInBase == 0
        SettingsParams memory settings5 = SettingsParams({
            owner: address(this),
            maxLimitsPerTx: 10,
            minLimitOrderAmountInBase: 100,
            tickSize: 1 ether,
            lotSizeInBase: 0 // Zero lot size
        });

        vm.expectRevert(CLOBManager.InvalidSettings.selector);
        clobManager.createMarket(newQuoteToken, newBaseToken, settings5);
    }
}
