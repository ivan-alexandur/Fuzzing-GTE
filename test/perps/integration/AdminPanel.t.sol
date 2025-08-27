// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";

import {AdminPanel} from "contracts/perps/modules/AdminPanel.sol";
import {PerpManagerTestBase} from "../PerpManagerTestBase.sol";
import {MarketParams, SignData, Side, Condition} from "contracts/perps/types/Structs.sol";
import {MarketSettings} from "contracts/perps/types/Market.sol";
import {BookSettings} from "contracts/perps/types/Book.sol";
import {FundingRateSettings} from "contracts/perps/types/FundingRateEngine.sol";
import {Status, FeeTier} from "contracts/perps/types/Enums.sol";
import {PackedFeeRates, PackedFeeRatesLib} from "contracts/perps/types/PackedFeeRatesLib.sol";
import {Constants} from "contracts/perps/types/Constants.sol";
import {StorageLib} from "contracts/perps/types/StorageLib.sol";
import {MarketLib} from "contracts/perps/types/Market.sol";
import {FundingLib} from "contracts/perps/types/FundingRateEngine.sol";
import {ClearingHouseLib} from "contracts/perps/types/ClearingHouse.sol";
import {ViewPort} from "contracts/perps/modules/ViewPort.sol";
import {MockAdminPanel} from "../mock/MockAdminPanel.t.sol";

import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";
import {TestPlus} from "lib/solady/test/utils/TestPlus.sol";
import {ERC1967Factory} from "@solady/utils/ERC1967Factory.sol";
import {OwnableRoles} from "@solady/auth/OwnableRoles.sol";
import {Ownable} from "@solady/auth/Ownable.sol";

contract AdminPanelTest is PerpManagerTestBase {
    using FixedPointMathLib for *;
    using SafeCastLib for *;

    MockAdminPanel internal adminPanel;

    function setUp() public virtual override {
        super.setUp();

        address adminPanelLogic = address(new MockAdminPanel());

        adminPanel = MockAdminPanel(
            factory.deployAndCall({
                admin: admin,
                implementation: adminPanelLogic,
                data: abi.encodeCall(AdminPanel.initialize, (admin, takerFees, makerFees))
            })
        );
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            SETTERS TESTS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_CreateMarket_revert_OnlyAdmin(uint256) public {
        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        MarketParams memory marketParams = _createMarketParams(4000e18, true);
        vm.expectRevert(Ownable.Unauthorized.selector);
        _createMarketAdminPanel(caller, ETH, marketParams);
    }

    // @todo
    // function test_createMarket(uint256) public returns (MarketParams memory marketParams) {
    //     marketParams = _createMarketParams(_hem(_random(), 1e18, 10_000e18), _random() % 2 == 0);

    //     MarketSettings memory marketSettings = MarketSettings({
    //         status: Status.INACTIVE,
    //         maxOpenLeverage: marketParams.maxOpenLeverage,
    //         maintenanceMarginRatio: marketParams.maintenanceMarginRatio,
    //         liquidationFeeRate: marketParams.liquidationFeeRate,
    //         divergenceCap: marketParams.divergenceCap,
    //         reduceOnlyCap: marketParams.reduceOnlyCap,
    //         partialLiquidationThreshold: marketParams.partialLiquidationThreshold,
    //         partialLiquidationRate: marketParams.partialLiquidationRate,
    //         crossMarginEnabled: marketParams.crossMarginEnabled
    //     });

    //     BookSettings memory bookSettings = BookSettings({
    //         maxNumOrders: marketParams.maxNumOrders,
    //         maxLimitsPerTx: marketParams.maxLimitsPerTx,
    //         minLimitOrderAmountInBase: marketParams.minLimitOrderAmountInBase,
    //         tickSize: marketParams.tickSize
    //     });

    //     vm.expectEmit(true, true, true, true);
    //     emit AdminPanel.MarketCreated({
    //         asset: ETH,
    //         marketSettings: marketSettings,
    //         bookSettings: bookSettings,
    //         fundingInterval: marketParams.fundingInterval,
    //         maxFundingRate: marketParams.maxFundingRate,
    //         initialPrice: marketParams.initialPrice,
    //         nonce: adminPanel.getNonce() + 1
    //     });

    //     _createMarketAdminPanel(admin, ETH, marketParams);
    // }

    // @todo
    // function test_CreateMarket_revert_MarketAlreadyInitialized(uint256) public {
    //     MarketParams memory marketParams = test_createMarket(_random());
    //     vm.expectRevert(abi.encodeWithSelector(AdminPanel.MarketAlreadyInitialized.selector));
    //     _createMarketAdminPanel(admin, ETH, marketParams);
    // }

    function test_setMarketSettings(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        MarketSettings memory settings = MarketSettings({
            status: Status.INACTIVE,
            maxOpenLeverage: _hem(_random(), 1e18, 100e18),
            maintenanceMarginRatio: _hem(_random(), 5000, 0.001 ether),
            liquidationFeeRate: _hem(_random(), 1, 1e18),
            divergenceCap: _hem(_random(), 1, 1e18),
            reduceOnlyCap: _hem(_random(), 0, 100),
            partialLiquidationThreshold: _hem(_random(), 1, 1_000_000e18),
            partialLiquidationRate: _hem(_random(), 1, 1e18),
            crossMarginEnabled: true
        });

        vm.expectEmit(true, true, true, true);
        if (settings.crossMarginEnabled) emit AdminPanel.CrossMarginEnabled(ETH, adminPanel.getNonce() + 1);
        else emit AdminPanel.CrossMarginDisabled(ETH, adminPanel.getNonce() + 1);
        vm.expectEmit(true, true, true, true);
        emit AdminPanel.MaxLeverageUpdated(ETH, settings.maxOpenLeverage, adminPanel.getNonce() + 2);
        vm.expectEmit(true, true, true, true);
        emit AdminPanel.MaintenanceMarginRatioUpdated(ETH, settings.maintenanceMarginRatio, adminPanel.getNonce() + 3);
        vm.expectEmit(true, true, true, true);
        emit AdminPanel.LiquidationFeeRateUpdated(ETH, settings.liquidationFeeRate, adminPanel.getNonce() + 4);
        vm.expectEmit(true, true, true, true);
        emit AdminPanel.DivergenceCapUpdated(ETH, settings.divergenceCap, adminPanel.getNonce() + 5);
        vm.expectEmit(true, true, true, true);
        emit AdminPanel.ReduceOnlyCapUpdated(ETH, settings.reduceOnlyCap, adminPanel.getNonce() + 6);
        vm.expectEmit(true, true, true, true);
        emit AdminPanel.PartialLiquidationThresholdUpdated(
            ETH, settings.partialLiquidationThreshold, adminPanel.getNonce() + 7
        );
        vm.expectEmit(true, true, true, true);
        emit AdminPanel.PartialLiquidationRateUpdated(ETH, settings.partialLiquidationRate, adminPanel.getNonce() + 8);

        vm.prank(admin);
        adminPanel.setMarketSettings(ETH, settings);

        assertEq(uint8(adminPanel.getMarketStatus(ETH)), uint8(settings.status), "Market status not updated correctly");
        assertEq(adminPanel.getMaxLeverage(ETH), settings.maxOpenLeverage, "Max leverage not updated correctly");
        assertEq(
            adminPanel.getLiquidationFeeRate(ETH),
            settings.liquidationFeeRate,
            "Liquidation fee rate not updated correctly"
        );
        assertEq(adminPanel.getDivergenceCap(ETH), settings.divergenceCap, "Divergence cap not updated correctly");
        assertEq(adminPanel.getReduceOnlyCap(ETH), settings.reduceOnlyCap, "Reduce only cap not updated correctly");
        assertEq(
            adminPanel.getPartialLiquidationThreshold(ETH),
            settings.partialLiquidationThreshold,
            "Partial liquidation threshold not updated correctly"
        );
        assertEq(
            adminPanel.getPartialLiquidationRate(ETH),
            settings.partialLiquidationRate,
            "Partial liquidation rate not updated correctly"
        );
        assertEq(
            adminPanel.isCrossMarginEnabled(ETH), settings.crossMarginEnabled, "Cross margin not updated correctly"
        );
    }

    function test_setMarketSettings_revert_OnlyAdmin(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        MarketSettings memory settings = MarketSettings({
            status: Status.INACTIVE,
            maxOpenLeverage: 10e18,
            maintenanceMarginRatio: 0.05e18,
            liquidationFeeRate: 0.01e18,
            divergenceCap: 0.5e18,
            reduceOnlyCap: 5,
            partialLiquidationThreshold: 1000e18,
            partialLiquidationRate: 0.2e18,
            crossMarginEnabled: true
        });

        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.setMarketSettings(ETH, settings);
    }

    function test_setMarkPrice(uint256) public {
        _createMarketAdminPanel(admin, ETH, _createMarketParams(4000e18, true));

        uint256 markPrice = _hem(_random(), 1e18, 10_000e18);

        vm.expectEmit(true, false, false, false);
        emit MarketLib.MarkPriceUpdated({
            asset: ETH,
            markPrice: 0, // ignored
            p1: 0, // ignored
            p2: 0, // ignored
            p3: 0, // ignored
            nonce: 0 // ignored
        });

        vm.prank(admin);
        adminPanel.setMarkPrice(ETH, markPrice);

        assertEq(adminPanel.getMarkPrice(ETH), markPrice, "Mark price not updated");
    }

    function test_setMarkPrice_revert_OnlyAdmin(uint256) public {
        _createMarketAdminPanel(admin, ETH, _createMarketParams(4000e18, true));

        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.setMarkPrice(ETH, _hem(_random(), 1e18, 10_000e18));
    }

    function test_setMarkPrice_revert_MarketNotFound(uint256) public {
        vm.expectRevert(abi.encodeWithSelector(AdminPanel.MarketNotFound.selector));
        vm.prank(admin);
        adminPanel.setMarkPrice(ETH, _hem(_random(), 1e18, 10_000e18));
    }

    function test_setFeeTiers(uint256) public {
        uint256 numAccounts = _hem(_random(), 1, 10);
        address[] memory accounts = new address[](numAccounts);
        FeeTier[] memory feeTiers = new FeeTier[](numAccounts);

        // Ensure unique addresses to avoid conflicts
        for (uint256 i; i < numAccounts; ++i) {
            accounts[i] = _randomUniqueNonZeroAddress();
            feeTiers[i] = FeeTier(_random() % 3);

            vm.expectEmit(true, true, true, true);
            emit AdminPanel.FeeTierUpdated(accounts[i], feeTiers[i], adminPanel.getNonce() + 1 + i);
        }

        vm.prank(admin);
        adminPanel.setFeeTiers(accounts, feeTiers);

        for (uint256 i; i < numAccounts; ++i) {
            assertEq(
                uint256(adminPanel.getAccountFeeTier(accounts[i])),
                uint256(feeTiers[i]),
                "Fee tier not updated correctly"
            );
        }
    }

    function test_setFeeTiers_revert_OnlyAdmin(uint256) public {
        address[] memory accounts = new address[](1);
        FeeTier[] memory feeTiers = new FeeTier[](1);

        accounts[0] = _randomAddress();
        feeTiers[0] = FeeTier.ZERO;

        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.setFeeTiers(accounts, feeTiers);
    }

    function test_setFeeTiers_revert_InvalidSettings(uint256) public {
        uint256 accountsLen = _hem(_random(), 2, 5);
        uint256 tierLen = _hem(_random(), 1, accountsLen - 1);

        address[] memory accounts = new address[](accountsLen);
        FeeTier[] memory feeTiers = new FeeTier[](tierLen);

        for (uint256 i; i < accountsLen; ++i) {
            accounts[i] = _randomAddress();
        }
        for (uint256 i; i < tierLen; ++i) {
            feeTiers[i] = FeeTier(_random() % 3);
        }

        vm.expectRevert(abi.encodeWithSelector(AdminPanel.InvalidSettings.selector));
        vm.prank(admin);
        adminPanel.setFeeTiers(accounts, feeTiers);
    }

    function test_setLiquidatorPoints(uint256) public {
        address account = _randomUniqueNonZeroAddress();
        uint256 points = _hem(_random(), 0, 1_000_000);

        vm.prank(admin);
        adminPanel.setLiquidatorPoints(account, points);

        assertEq(adminPanel.getLiquidatorPoints(account), points, "Liquidator points not updated correctly");
    }

    function test_setLiquidatorPoints_revert_OnlyAdmin(uint256) public {
        address account = _randomAddress();
        uint256 points = _hem(_random(), 0, 1_000_000);

        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.setLiquidatorPoints(account, points);
    }

    function test_grantAdmin(uint256) public {
        address account = _randomAddress();

        vm.prank(admin);
        adminPanel.grantAdmin(account);

        assertTrue(OwnableRoles(adminPanel).rolesOf(account) & Constants.ADMIN_ROLE != 0);
    }

    function test_grantAdmin_revert_OnlyOwner(uint256) public {
        address account = _randomAddress();
        address caller = _randomAddress();
        vm.assume(caller != admin);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.grantAdmin(account);
    }

    function test_revokeAdmin(uint256) public {
        address account = _randomAddress();

        vm.prank(admin);
        adminPanel.grantAdmin(account);
        assertTrue(OwnableRoles(adminPanel).rolesOf(account) & Constants.ADMIN_ROLE != 0);

        vm.prank(admin);
        adminPanel.revokeAdmin(account);
        assertTrue(OwnableRoles(adminPanel).rolesOf(account) & Constants.ADMIN_ROLE == 0);
    }

    function test_revokeAdmin_revert_OnlyOwner(uint256) public {
        address account = _randomAddress();
        address caller = _randomAddress();
        vm.assume(caller != admin);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.revokeAdmin(account);
    }

    function test_insuranceFundDeposit(uint256) public {
        uint256 amount = _hem(_random(), 1e18, 1000e18);
        usdc.mint(admin, amount);

        uint256 adminBalanceBefore = usdc.balanceOf(admin);

        vm.startPrank(admin);
        usdc.approve(address(adminPanel), amount);
        adminPanel.insuranceFundDeposit(amount);
        vm.stopPrank();

        assertEq(adminPanel.getInsuranceFundBalance(), amount, "Insurance fund balance not updated correctly");
        assertEq(usdc.balanceOf(admin), adminBalanceBefore - amount, "USDC balance not updated correctly");
    }

    function test_insuranceFundDeposit_revert_OnlyOwner(uint256) public {
        uint256 amount = _hem(_random(), 1e18, 1000e18);
        address caller = _randomAddress();
        vm.assume(caller != admin);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.insuranceFundDeposit(amount);
    }

    function test_insuranceFundWithdraw(uint256) public {
        uint256 depositAmount = _hem(_random(), 1e18, 1000e18);
        uint256 withdrawAmount = _hem(_random(), 1e17, depositAmount);
        usdc.mint(admin, depositAmount);

        uint256 adminBalanceBefore = usdc.balanceOf(admin);

        vm.startPrank(admin);
        usdc.approve(address(adminPanel), depositAmount);
        adminPanel.insuranceFundDeposit(depositAmount);
        adminPanel.insuranceFundWithdraw(withdrawAmount);
        vm.stopPrank();

        assertEq(
            adminPanel.getInsuranceFundBalance(),
            depositAmount - withdrawAmount,
            "Insurance fund balance not updated correctly"
        );
        assertEq(
            usdc.balanceOf(admin),
            adminBalanceBefore - depositAmount + withdrawAmount,
            "USDC balance not updated correctly"
        );
    }

    function test_insuranceFundWithdraw_revert_OnlyOwner(uint256) public {
        uint256 amount = _hem(_random(), 1e18, 1000e18);
        address caller = _randomAddress();
        vm.assume(caller != admin);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.insuranceFundWithdraw(amount);
    }

    function test_setTakerFeeRates(uint256) public {
        uint256 numTiers = _hem(_random(), 1, 15);
        uint16[] memory takerFeeRates = new uint16[](numTiers);

        for (uint256 i; i < numTiers; ++i) {
            takerFeeRates[i] = uint16(_hem(_random(), 1, 1000));
        }

        vm.expectEmit(true, true, true, true);
        emit AdminPanel.TakerFeeRatesUpdated(takerFeeRates, adminPanel.getNonce() + 1);

        vm.prank(admin);
        adminPanel.setTakerFeeRates(takerFeeRates);

        for (uint256 i; i < numTiers; ++i) {
            assertEq(
                PackedFeeRatesLib.getFeeAt(adminPanel.getTakerFeeRates(), i),
                takerFeeRates[i],
                "Taker fee rates not updated correctly"
            );
        }
    }

    function test_setTakerFeeRates_revert_OnlyAdmin(uint256) public {
        uint16[] memory takerFeeRates = new uint16[](1);
        takerFeeRates[0] = uint16(_hem(_random(), 1, 1000));

        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.setTakerFeeRates(takerFeeRates);
    }

    function test_setMakerFeeRates(uint256) public {
        uint256 numTiers = _hem(_random(), 1, 5);
        uint16[] memory makerFeeRates = new uint16[](numTiers);

        for (uint256 i; i < numTiers; ++i) {
            makerFeeRates[i] = uint16(_hem(_random(), 1, 1000));
        }

        vm.expectEmit(true, true, true, true);
        emit AdminPanel.MakerFeeRatesUpdated(makerFeeRates, adminPanel.getNonce() + 1);

        vm.prank(admin);
        adminPanel.setMakerFeeRates(makerFeeRates);

        for (uint256 i; i < numTiers; ++i) {
            assertEq(
                PackedFeeRatesLib.getFeeAt(adminPanel.getMakerFeeRates(), i),
                makerFeeRates[i],
                "Maker fee rates not updated correctly"
            );
        }
    }

    function test_setMakerFeeRates_revert_OnlyAdmin(uint256) public {
        uint16[] memory makerFeeRates = new uint16[](1);
        makerFeeRates[0] = uint16(_hem(_random(), 1, 1000));

        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.setMakerFeeRates(makerFeeRates);
    }

    function test_activateProtocol(uint256) public {
        vm.expectEmit(true, true, true, true);
        emit AdminPanel.ProtocolActivated(adminPanel.getNonce() + 1);

        vm.prank(admin);
        adminPanel.activateProtocol();
    }

    function test_activateProtocol_revert_OnlyAdmin(uint256) public {
        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.activateProtocol();
    }

    function test_activateProtocol_revert_ProtocolAlreadyActive(uint256) public {
        vm.prank(admin);
        adminPanel.activateProtocol();

        vm.expectRevert(abi.encodeWithSelector(AdminPanel.ProtocolAlreadyActive.selector));
        vm.prank(admin);
        adminPanel.activateProtocol();
    }

    function test_deactivateProtocol(uint256) public {
        vm.prank(admin);
        adminPanel.activateProtocol();

        vm.expectEmit(true, true, true, true);
        emit AdminPanel.ProtocolDeactivated(adminPanel.getNonce() + 1);

        vm.prank(admin);
        adminPanel.deactivateProtocol();
    }

    function test_deactivateProtocol_revert_OnlyAdmin(uint256) public {
        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.deactivateProtocol();
    }

    function test_deactivateProtocol_revert_ProtocolAlreadyInactive(uint256) public {
        vm.expectRevert(abi.encodeWithSelector(AdminPanel.ProtocolAlreadyInactive.selector));
        vm.prank(admin);
        adminPanel.deactivateProtocol();
    }

    function test_activateMarket(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        vm.expectEmit(true, true, true, true);
        emit AdminPanel.MarketStatusUpdated(ETH, Status.ACTIVE, adminPanel.getNonce() + 1);

        vm.prank(admin);
        adminPanel.activateMarket(ETH);

        assertEq(uint8(adminPanel.getMarketStatus(ETH)), uint8(Status.ACTIVE), "Market status not updated correctly");
    }

    function test_activateMarket_revert_OnlyAdmin(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.activateMarket(ETH);
    }

    function test_activateMarket_revert_CannotActivateMarket(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        vm.prank(admin);
        adminPanel.activateMarket(ETH);

        vm.expectRevert(abi.encodeWithSelector(AdminPanel.CannotActivateMarket.selector));
        vm.prank(admin);
        adminPanel.activateMarket(ETH);

        bytes32 noMarket = bytes32(_random());
        vm.assume(noMarket != ETH);
        vm.expectRevert(abi.encodeWithSelector(AdminPanel.MarketNotFound.selector));
        vm.prank(admin);
        adminPanel.activateMarket(noMarket);
    }

    function test_deactivateMarket(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        vm.prank(admin);
        adminPanel.activateMarket(ETH);

        vm.expectEmit(true, true, true, true);
        emit AdminPanel.MarketStatusUpdated(ETH, Status.INACTIVE, adminPanel.getNonce() + 1);

        vm.prank(admin);
        adminPanel.deactivateMarket(ETH);

        assertEq(uint8(adminPanel.getMarketStatus(ETH)), uint8(Status.INACTIVE), "Market status not updated correctly");
    }

    function test_deactivateMarket_revert_OnlyAdmin(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        vm.prank(admin);
        adminPanel.activateMarket(ETH);

        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.deactivateMarket(ETH);
    }

    function test_deactivateMarket_revert_CannotDeactivateMarket(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        vm.expectRevert(abi.encodeWithSelector(AdminPanel.CannotDeactivateMarket.selector));
        vm.prank(admin);
        adminPanel.deactivateMarket(ETH);
    }

    function test_delistMarket(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        vm.expectEmit(true, true, true, true);
        emit AdminPanel.MarketStatusUpdated(ETH, Status.DELISTED, adminPanel.getNonce() + 1);

        vm.prank(admin);
        adminPanel.delistMarket(ETH);

        assertEq(uint8(adminPanel.getMarketStatus(ETH)), uint8(Status.DELISTED), "Market status not updated correctly");
    }

    function test_delistMarket_revert_OnlyAdmin(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.delistMarket(ETH);
    }

    function test_delistMarket_revert_CannotDelistMarket(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        vm.prank(admin);
        adminPanel.activateMarket(ETH);

        vm.expectRevert(abi.encodeWithSelector(AdminPanel.CannotDelistMarket.selector));
        vm.prank(admin);
        adminPanel.delistMarket(ETH);
    }

    function test_relistMarket(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        vm.prank(admin);
        adminPanel.delistMarket(ETH);

        vm.expectEmit(true, true, true, true);
        emit AdminPanel.MarketStatusUpdated(ETH, Status.INACTIVE, adminPanel.getNonce() + 1);

        vm.prank(admin);
        adminPanel.relistMarket(ETH);

        assertEq(uint8(adminPanel.getMarketStatus(ETH)), uint8(Status.INACTIVE), "Market status not updated correctly");
    }

    function test_relistMarket_revert_OnlyAdmin(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        vm.prank(admin);
        adminPanel.delistMarket(ETH);

        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.relistMarket(ETH);
    }

    function test_relistMarket_revert_CannotRelistMarket_MarketAlreadyActive(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        vm.expectRevert(abi.encodeWithSelector(AdminPanel.CannotRelistMarket.selector));
        vm.prank(admin);
        adminPanel.relistMarket(ETH);
    }

    function test_enableCrossMargin(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, false);
        _createMarketAdminPanel(admin, ETH, params);

        vm.expectEmit(true, true, true, true);
        emit AdminPanel.CrossMarginEnabled(ETH, adminPanel.getNonce() + 1);

        vm.prank(admin);
        adminPanel.enableCrossMargin(ETH);

        assertEq(adminPanel.isCrossMarginEnabled(ETH), true, "Cross margin not enabled correctly");
    }

    function test_enableCrossMargin_revert_OnlyAdmin(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, false);
        _createMarketAdminPanel(admin, ETH, params);

        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.enableCrossMargin(ETH);
    }

    function test_enableCrossMargin_revert_CrossMarginAlreadyEnabled(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        vm.expectRevert(abi.encodeWithSelector(AdminPanel.CrossMarginAlreadyEnabled.selector));
        vm.prank(admin);
        adminPanel.enableCrossMargin(ETH);
    }

    function test_disableCrossMargin(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        vm.expectEmit(true, true, true, true);
        emit AdminPanel.CrossMarginDisabled(ETH, adminPanel.getNonce() + 1);

        vm.prank(admin);
        adminPanel.disableCrossMargin(ETH);

        assertEq(adminPanel.isCrossMarginEnabled(ETH), false, "Cross margin not disabled correctly");
    }

    function test_disableCrossMargin_revert_OnlyAdmin(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.disableCrossMargin(ETH);
    }

    function test_disableCrossMargin_revert_CrossMarginAlreadyDisabled(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, false);
        _createMarketAdminPanel(admin, ETH, params);

        vm.expectRevert(abi.encodeWithSelector(AdminPanel.CrossMarginAlreadyDisabled.selector));
        vm.prank(admin);
        adminPanel.disableCrossMargin(ETH);
    }

    function test_setMaxLeverage(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        uint256 maxLeverage = _hem(_random(), 1e18, 100e18);

        vm.expectEmit(true, true, true, true);
        emit AdminPanel.MaxLeverageUpdated(ETH, maxLeverage, adminPanel.getNonce() + 1);

        vm.prank(admin);
        adminPanel.setMaxLeverage(ETH, maxLeverage);

        assertEq(adminPanel.getMaxLeverage(ETH), maxLeverage, "Max leverage not updated correctly");
    }

    function test_setMaxLeverage_revert_OnlyAdmin(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        uint256 maxLeverage = _hem(_random(), 1e18, 100e18);

        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.setMaxLeverage(ETH, maxLeverage);
    }

    function test_setMaxLeverage_revert_InvalidSettings(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        uint256 invalidLeverage = true ? 0 : 101e18;

        vm.expectRevert(abi.encodeWithSelector(AdminPanel.InvalidSettings.selector));
        vm.prank(admin);
        adminPanel.setMaxLeverage(ETH, invalidLeverage);
    }

    function test_setLiquidationFeeRate(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        uint256 feeRate = _hem(_random(), 1, 1e18);

        vm.expectEmit(true, true, true, true);
        emit AdminPanel.LiquidationFeeRateUpdated(ETH, feeRate, adminPanel.getNonce() + 1);

        vm.prank(admin);
        adminPanel.setLiquidationFeeRate(ETH, feeRate);

        assertEq(adminPanel.getLiquidationFeeRate(ETH), feeRate, "Liquidation fee rate not updated correctly");
    }

    function test_setLiquidationFeeRate_revert_OnlyAdmin(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        uint256 feeRate = _hem(_random(), 1, 1e18);

        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.setLiquidationFeeRate(ETH, feeRate);
    }

    function test_setLiquidationFeeRate_revert_InvalidSettings(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        uint256 invalidFeeRate = true ? 0 : 2e18;

        vm.expectRevert(abi.encodeWithSelector(AdminPanel.InvalidSettings.selector));
        vm.prank(admin);
        adminPanel.setLiquidationFeeRate(ETH, invalidFeeRate);
    }

    function test_setDivergenceCap(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        uint256 divergenceCap = _hem(_random(), 1, 1e18);

        vm.expectEmit(true, true, true, true);
        emit AdminPanel.DivergenceCapUpdated(ETH, divergenceCap, adminPanel.getNonce() + 1);

        vm.prank(admin);
        adminPanel.setDivergenceCap(ETH, divergenceCap);

        assertEq(adminPanel.getDivergenceCap(ETH), divergenceCap, "Divergence cap not updated correctly");
    }

    function test_setDivergenceCap_revert_OnlyAdmin(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        uint256 divergenceCap = _hem(_random(), 1, 1e18);

        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.setDivergenceCap(ETH, divergenceCap);
    }

    function test_setDivergenceCap_revert_InvalidSettings(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        uint256 invalidDivergenceCap = true ? 0 : 2e18;

        vm.expectRevert(abi.encodeWithSelector(AdminPanel.InvalidSettings.selector));
        vm.prank(admin);
        adminPanel.setDivergenceCap(ETH, invalidDivergenceCap);
    }

    function test_setReduceOnlyCap(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        uint256 reduceOnlyCap = _hem(_random(), 0, 100);

        vm.expectEmit(true, true, true, true);
        emit AdminPanel.ReduceOnlyCapUpdated(ETH, reduceOnlyCap, adminPanel.getNonce() + 1);

        vm.prank(admin);
        adminPanel.setReduceOnlyCap(ETH, reduceOnlyCap);

        assertEq(adminPanel.getReduceOnlyCap(ETH), reduceOnlyCap, "Reduce only cap not updated correctly");
    }

    function test_setReduceOnlyCap_revert_OnlyAdmin(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        uint256 reduceOnlyCap = _hem(_random(), 0, 100);

        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.setReduceOnlyCap(ETH, reduceOnlyCap);
    }

    function test_setPartialLiquidationThreshold(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        uint256 threshold = _hem(_random(), 1, 1_000_000e18);

        vm.expectEmit(true, true, true, true);
        emit AdminPanel.PartialLiquidationThresholdUpdated(ETH, threshold, adminPanel.getNonce() + 1);

        vm.prank(admin);
        adminPanel.setPartialLiquidationThreshold(ETH, threshold);

        assertEq(
            adminPanel.getPartialLiquidationThreshold(ETH),
            threshold,
            "Partial liquidation threshold not updated correctly"
        );
    }

    function test_setPartialLiquidationThreshold_revert_OnlyAdmin(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        uint256 threshold = _hem(_random(), 1, 1_000_000e18);

        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.setPartialLiquidationThreshold(ETH, threshold);
    }

    function test_setPartialLiquidationThreshold_revert_InvalidSettings(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        vm.expectRevert(abi.encodeWithSelector(AdminPanel.InvalidSettings.selector));
        vm.prank(admin);
        adminPanel.setPartialLiquidationThreshold(ETH, 0);
    }

    function test_setPartialLiquidationRate(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        uint256 rate = _hem(_random(), 1, 1e18);

        vm.expectEmit(true, true, true, true);
        emit AdminPanel.PartialLiquidationRateUpdated(ETH, rate, adminPanel.getNonce() + 1);

        vm.prank(admin);
        adminPanel.setPartialLiquidationRate(ETH, rate);

        assertEq(adminPanel.getPartialLiquidationRate(ETH), rate, "Partial liquidation rate not updated correctly");
    }

    function test_setPartialLiquidationRate_revert_OnlyAdmin(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        uint256 rate = _hem(_random(), 1, 1e18);

        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.setPartialLiquidationRate(ETH, rate);
    }

    function test_setPartialLiquidationRate_revert_InvalidSettings(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        uint256 invalidRate = true ? 0 : 2e18;

        vm.expectRevert(abi.encodeWithSelector(AdminPanel.InvalidSettings.selector));
        vm.prank(admin);
        adminPanel.setPartialLiquidationRate(ETH, invalidRate);
    }

    // @todo
    // function test_setFundingInterval(uint256) public {
    //     MarketParams memory params = _createMarketParams(4000e18, true);
    //     _createMarketAdminPanel(admin, ETH, params);

    //     uint256 interval = _hem(_random(), 1 hours, 24 hours);

    //     vm.expectEmit(true, true, true, true);
    //     emit AdminPanel.FundingIntervalUpdated(ETH, interval, adminPanel.getNonce() + 1);

    //     vm.prank(admin);
    //     adminPanel.setFundingInterval(ETH, interval);

    //     assertEq(adminPanel.getFundingInterval(ETH), interval, "Funding interval not updated correctly");
    // }

    // @todo
    // function test_setFundingInterval_revert_OnlyAdmin(uint256) public {
    //     MarketParams memory params = _createMarketParams(4000e18, true);
    //     _createMarketAdminPanel(admin, ETH, params);

    //     uint256 interval = _hem(_random(), 1 hours, 24 hours);

    //     address caller = _randomAddress();
    //     _assumeNotRole(caller, Constants.ADMIN_ROLE);

    //     vm.expectRevert(Ownable.Unauthorized.selector);
    //     vm.prank(caller);
    //     adminPanel.setFundingInterval(ETH, interval);
    // }

    // @todo
    // function test_setFundingInterval_revert_InvalidSettings(uint256) public {
    //     MarketParams memory params = _createMarketParams(4000e18, true);
    //     _createMarketAdminPanel(admin, ETH, params);

    //     vm.expectRevert(abi.encodeWithSelector(AdminPanel.InvalidSettings.selector));
    //     vm.prank(admin);
    //     adminPanel.setFundingInterval(ETH, 0);
    // }

    // @todo
    // function test_setMaxFundingRate(uint256) public {
    //     MarketParams memory params = _createMarketParams(4000e18, true);
    //     _createMarketAdminPanel(admin, ETH, params);

    //     uint256 maxRate = _hem(_random(), 1, 1e18);

    //     vm.expectEmit(true, true, true, true);
    //     emit AdminPanel.MaxFundingRateUpdated(ETH, maxRate, adminPanel.getNonce() + 1);

    //     vm.prank(admin);
    //     adminPanel.setMaxFundingRate(ETH, maxRate);

    //     assertEq(adminPanel.getMaxFundingRate(ETH), maxRate, "Max funding rate not updated correctly");
    // }

    // @todo
    // function test_setMaxFundingRate_revert_OnlyAdmin(uint256) public {
    //     MarketParams memory params = _createMarketParams(4000e18, true);
    //     _createMarketAdminPanel(admin, ETH, params);

    //     uint256 maxRate = _hem(_random(), 1, 1e18);

    //     address caller = _randomAddress();
    //     _assumeNotRole(caller, Constants.ADMIN_ROLE);

    //     vm.expectRevert(Ownable.Unauthorized.selector);
    //     vm.prank(caller);
    //     adminPanel.setMaxFundingRate(ETH, maxRate);
    // }

    // @todo
    // function test_setMaxFundingRate_revert_InvalidSettings(uint256) public {
    //     MarketParams memory params = _createMarketParams(4000e18, true);
    //     _createMarketAdminPanel(admin, ETH, params);

    //     uint256 invalidRate = true ? 0 : 2e18;

    //     vm.expectRevert(abi.encodeWithSelector(AdminPanel.InvalidSettings.selector));
    //     vm.prank(admin);
    //     adminPanel.setMaxFundingRate(ETH, invalidRate);
    // }

    function test_setInterestRate(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        int256 interestRate = int256(_hem(_random(), 1, 1e18));
        if (_random() % 2 == 0) interestRate = -interestRate;

        vm.expectEmit(true, true, true, true);
        emit AdminPanel.InterestRateUpdated(ETH, interestRate, adminPanel.getNonce() + 1);

        vm.prank(admin);
        adminPanel.setInterestRate(ETH, interestRate);

        assertEq(adminPanel.getInterestRate(ETH), interestRate, "Interest rate not updated correctly");
    }

    function test_setInterestRate_revert_OnlyAdmin(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        int256 interestRate = int256(_hem(_random(), 1, 1e18));

        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.setInterestRate(ETH, interestRate);
    }

    function test_setInterestRate_revert_InvalidSettings(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        int256 invalidRate = int256(2e18);
        if (true) invalidRate = -invalidRate;

        vm.expectRevert(abi.encodeWithSelector(AdminPanel.InvalidSettings.selector));
        vm.prank(admin);
        adminPanel.setInterestRate(ETH, invalidRate);
    }

    function test_setMaxNumOrders(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        uint256 maxOrders = _hem(_random(), 1000, 10_000_000);

        vm.expectEmit(true, true, true, true);
        emit AdminPanel.MaxNumOrdersUpdated(ETH, maxOrders, adminPanel.getNonce() + 1);

        vm.prank(admin);
        adminPanel.setMaxNumOrders(ETH, maxOrders);

        assertEq(adminPanel.getMaxNumOrders(ETH), maxOrders, "Max num orders not updated correctly");
    }

    function test_setMaxNumOrders_revert_OnlyAdmin(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        uint256 maxOrders = _hem(_random(), 1000, 10_000_000);

        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.setMaxNumOrders(ETH, maxOrders);
    }

    function test_setMaxNumOrders_revert_InvalidSettings(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        vm.expectRevert(abi.encodeWithSelector(AdminPanel.InvalidSettings.selector));
        vm.prank(admin);
        adminPanel.setMaxNumOrders(ETH, 0);
    }

    function test_setMaxLimitsPerTx(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        uint8 maxLimits = uint8(_hem(_random(), 1, 255));

        vm.expectEmit(true, true, true, true);
        emit AdminPanel.MaxLimitsPerTxUpdated(ETH, maxLimits, adminPanel.getNonce() + 1);

        vm.prank(admin);
        adminPanel.setMaxLimitsPerTx(ETH, maxLimits);

        assertEq(adminPanel.getMaxLimitsPerTx(ETH), maxLimits, "Max limits per tx not updated correctly");
    }

    function test_setMaxLimitsPerTx_revert_OnlyAdmin(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        uint8 maxLimits = uint8(_hem(_random(), 1, 255));

        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.setMaxLimitsPerTx(ETH, maxLimits);
    }

    function test_setMaxLimitsPerTx_revert_InvalidSettings(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        vm.expectRevert(abi.encodeWithSelector(AdminPanel.InvalidSettings.selector));
        vm.prank(admin);
        adminPanel.setMaxLimitsPerTx(ETH, 0);
    }

    function test_setMinLimitOrderAmountInBase(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        uint256 minAmount = _hem(_random(), 0.001 ether, 10 ether);
        minAmount -= minAmount % adminPanel.getLotSize(ETH);
        vm.assume(minAmount.fullMulDiv(adminPanel.getTickSize(ETH), 1e18) > 0);

        vm.expectEmit(true, true, true, true);
        emit AdminPanel.MinLimitOrderAmountInBaseUpdated(ETH, minAmount, adminPanel.getNonce() + 1);

        vm.prank(admin);
        adminPanel.setMinLimitOrderAmountInBase(ETH, minAmount);

        assertEq(
            adminPanel.getMinLimitOrderAmountInBase(ETH),
            minAmount,
            "Min limit order amount in base not updated correctly"
        );
    }

    function test_setMinLimitOrderAmountInBase_revert_OnlyAdmin(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        uint256 minAmount = _hem(_random(), 0.001 ether, 10 ether);

        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.setMinLimitOrderAmountInBase(ETH, minAmount);
    }

    function test_setTickSize(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        uint256 tickSize = _hem(_random(), 0.001 ether, 1 ether);

        vm.expectEmit(true, true, true, true);
        emit AdminPanel.TickSizeUpdated(ETH, tickSize, adminPanel.getNonce() + 1);

        vm.prank(admin);
        adminPanel.setTickSize(ETH, tickSize);

        assertEq(adminPanel.getTickSize(ETH), tickSize, "Tick size not updated correctly");
    }

    function test_setTickSize_revert_OnlyAdmin(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        uint256 tickSize = _hem(_random(), 0.001 ether, 1 ether);

        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.setTickSize(ETH, tickSize);
    }

    // @todo
    // function test_setFundingRateSettings(uint256) public {
    //     MarketParams memory params = _createMarketParams(4000e18, true);
    //     _createMarketAdminPanel(admin, ETH, params);

    //     FundingRateSettings memory settings = FundingRateSettings({
    //         fundingInterval: _hem(_random(), 1 hours, 24 hours),
    //         maxFundingRate: _hem(_random(), 1, 1e18),
    //         interestRate: int256(_hem(_random(), 1, 1e18))
    //     });

    //     if (_random() % 2 == 0) settings.interestRate = -settings.interestRate;

    //     vm.expectEmit(true, true, true, true);
    //     emit AdminPanel.FundingIntervalUpdated(ETH, settings.fundingInterval, adminPanel.getNonce() + 1);

    //     vm.prank(admin);
    //     adminPanel.setFundingRateSettings(ETH, settings);

    //     assertEq(adminPanel.getFundingInterval(ETH), settings.fundingInterval, "Funding interval not updated correctly");
    //     assertEq(adminPanel.getMaxFundingRate(ETH), settings.maxFundingRate, "Max funding rate not updated correctly");
    //     assertEq(adminPanel.getInterestRate(ETH), settings.interestRate, "Interest rate not updated correctly");
    // }

    // @todo
    // function test_setFundingRateSettings_revert_OnlyAdmin(uint256) public {
    //     MarketParams memory params = _createMarketParams(4000e18, true);
    //     _createMarketAdminPanel(admin, ETH, params);

    //     FundingRateSettings memory settings =
    //         FundingRateSettings({fundingInterval: 1 hours, maxFundingRate: 0.02e18, interestRate: 0.005e18});

    //     address caller = _randomAddress();
    //     _assumeNotRole(caller, Constants.ADMIN_ROLE);

    //     vm.expectRevert(Ownable.Unauthorized.selector);
    //     vm.prank(caller);
    //     adminPanel.setFundingRateSettings(ETH, settings);
    // }

    function test_setBookSettings(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        BookSettings memory settings = BookSettings({
            maxNumOrders: _hem(_random(), 1000, 10_000_000),
            maxLimitsPerTx: uint8(_hem(_random(), 1, 255)),
            minLimitOrderAmountInBase: _hem(_random(), 0.001 ether, 10 ether),
            tickSize: _hem(_random(), 0.001 ether, 1 ether)
        });

        vm.expectEmit(true, true, true, true);
        emit AdminPanel.MaxNumOrdersUpdated(ETH, settings.maxNumOrders, adminPanel.getNonce() + 1);

        vm.prank(admin);
        adminPanel.setBookSettings(ETH, settings);

        assertEq(adminPanel.getMaxNumOrders(ETH), settings.maxNumOrders, "Max num orders not updated correctly");
        assertEq(adminPanel.getMaxLimitsPerTx(ETH), settings.maxLimitsPerTx, "Max limits per tx not updated correctly");
        assertEq(
            adminPanel.getMinLimitOrderAmountInBase(ETH),
            settings.minLimitOrderAmountInBase,
            "Min limit order amount in base not updated correctly"
        );
        assertEq(adminPanel.getTickSize(ETH), settings.tickSize, "Tick size not updated correctly");
    }

    function test_setBookSettings_revert_OnlyAdmin(uint256) public {
        MarketParams memory params = _createMarketParams(4000e18, true);
        _createMarketAdminPanel(admin, ETH, params);

        BookSettings memory settings = BookSettings({
            maxNumOrders: 1_000_000,
            maxLimitsPerTx: 40,
            minLimitOrderAmountInBase: 0.001 ether,
            tickSize: 0.001 ether
        });

        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.setBookSettings(ETH, settings);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            MARKET TESTS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    // @todo
    // function test_settleFunding(uint256) public {
    //     uint256 initialPrice = 4000e18;
    //     _createMarketAdminPanel(admin, ETH, _createMarketParams(initialPrice, true));

    //     vm.roll(block.number + 1);
    //     vm.warp(block.timestamp + 1 days);

    //     uint256 newPrice = _hem(_random(), 1e18, 5000e18);
    //     vm.prank(admin);
    //     adminPanel.setMarkPrice(ETH, newPrice);

    //     //TODO: check if settle funding and `interestRate` should have a `currency/hour` dimension
    //     int256 fundingRate = adminPanel.getInterestRate(ETH);

    //     vm.expectEmit(true, true, true, true);
    //     emit MarketLib.FundingSettled({
    //         asset: ETH,
    //         funding: fundingRate,
    //         cumulativeFunding: fundingRate,
    //         nonce: adminPanel.getNonce() + 1
    //     });

    //     vm.prank(admin);
    //     adminPanel.settleFunding(ETH);

    //     assertEq(adminPanel.getCumulativeFunding(ETH), fundingRate, "Cumulative funding not updated correctly");
    // }

    function test_settleFunding_revert_FundingIntervalNotElapsed(uint256) public {
        _createMarketAdminPanel(admin, ETH, _createMarketParams(4000e18, true));

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(FundingLib.FundingIntervalNotElapsed.selector));
        adminPanel.settleFunding(ETH);
    }

    function test_settleFunding_revert_OnlyAdmin(uint256) public {
        _createMarketAdminPanel(admin, ETH, _createMarketParams(4000e18, true));

        address caller = _randomAddress();
        _assumeNotRole(caller, Constants.ADMIN_ROLE);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        adminPanel.settleFunding(ETH);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                          INTERNAL HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _createMarketAdminPanel(address caller, bytes32 asset, MarketParams memory marketParams) internal {
        vm.prank(caller);
        adminPanel.createMarket({asset: asset, params: marketParams});
    }

    function _createMarketParams(uint256 price, bool crossMarginEnabled) internal pure returns (MarketParams memory) {
        return MarketParams({
            maxOpenLeverage: 50 ether, // 50x
            maintenanceMarginRatio: 0.01 ether,
            liquidationFeeRate: 0.01 ether, // 1%
            divergenceCap: 1 ether, // 100%
            reduceOnlyCap: 4,
            partialLiquidationThreshold: type(uint256).max, // max = no partial liquidation
            partialLiquidationRate: 0.2 ether, // 20% of position
            fundingInterval: 1 hours,
            resetInterval: 30 minutes,
            resetIterations: 5,
            innerClamp: 0.01 ether,
            outerClamp: 0.02 ether,
            interestRate: 0.005 ether,
            maxNumOrders: 1_000_000,
            maxLimitsPerTx: 40,
            minLimitOrderAmountInBase: 0.001 ether,
            lotSize: 0.001 ether,
            tickSize: 0.001 ether,
            initialPrice: price,
            crossMarginEnabled: crossMarginEnabled
        });
    }

    function _assumeNotRole(address caller, uint256 role) internal view {
        vm.assume(OwnableRoles(adminPanel).rolesOf(caller) & role == 0);
    }
}
