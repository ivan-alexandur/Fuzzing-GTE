// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {OwnableRoles} from "@solady/auth/OwnableRoles.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";
import {Initializable} from "@solady/utils/Initializable.sol";
import {SignatureCheckerLib} from "@solady/utils/SignatureCheckerLib.sol";

import {Status, Side, TradeType, FeeTier, BookType} from "../types/Enums.sol";
import {
    MarketParams,
    PlaceOrderArgs,
    PlaceOrderResult,
    PositionUpdateResult,
    LiquidateData,
    BackstopLiquidateData,
    TradeExecutedData,
    DeleveragePair,
    LiquidatorData,
    Condition,
    SignData,
    FundingPaymentResult,
    LiquidateeSettleData,
    Account
} from "../types/Structs.sol";
import {Constants} from "../types/Constants.sol";

import {BackstopLiquidatorDataLib} from "../types/BackstopLiquidatorDataLib.sol";
import {StorageLib} from "../types/StorageLib.sol";
import {CLOBLib} from "../types/CLOBLib.sol";
import {ClearingHouse, StorageLib} from "../types/ClearingHouse.sol";
import {FeeManager} from "../types/FeeManager.sol";
import {Market, MarketSettings, MarketMetadata} from "../types/Market.sol";
import {FundingRateSettings} from "../types/FundingRateEngine.sol";
import {Position} from "../types/Position.sol";
import {Book, BookSettings} from "../types/Book.sol";

abstract contract AdminPanel is OwnableRoles, Initializable {
    using FixedPointMathLib for *;
    using SafeCastLib for *;
    using SignatureCheckerLib for address;

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                EVENTS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    event MarketCreated(
        bytes32 indexed asset,
        MarketSettings marketSettings,
        FundingRateSettings fundingSettings,
        BookSettings bookSettings,
        uint256 lotSize,
        uint256 initialPrice,
        uint256 nonce
    );

    event FeeTierUpdated(address indexed account, FeeTier indexed feeTier, uint256 nonce);

    event ProtocolActivated(uint256 nonce);
    event ProtocolDeactivated(uint256 nonce);
    event TakerFeeRatesUpdated(uint16[] takerFeeRates, uint256 nonce);
    event MakerFeeRatesUpdated(uint16[] makerFeeRates, uint256 nonce);

    event MarketStatusUpdated(bytes32 indexed asset, Status status, uint256 nonce);
    event CrossMarginEnabled(bytes32 indexed asset, uint256 nonce);
    event CrossMarginDisabled(bytes32 indexed asset, uint256 nonce);
    event MaxLeverageUpdated(bytes32 indexed asset, uint256 maxOpenLeverage, uint256 nonce);
    event MaintenanceMarginRatioUpdated(bytes32 indexed asset, uint256 maintenanceMarginRatio, uint256 nonce);
    event LiquidationFeeRateUpdated(bytes32 indexed asset, uint256 liquidationFeeRate, uint256 nonce);
    event FundingIntervalUpdated(bytes32 indexed asset, uint256 fundingInterval, uint256 resetInterval, uint256 nonce);
    event ResetIterationsUpdated(bytes32 indexed asset, uint256 resetIterations, uint256 nonce);
    event FundingClampsUpdated(bytes32 indexed asset, uint256 innerClamp, uint256 outerClamp, uint256 nonce);
    event InterestRateUpdated(bytes32 indexed asset, int256 interestRate, uint256 nonce);
    event DivergenceCapUpdated(bytes32 indexed asset, uint256 divergenceCap, uint256 nonce);
    event ReduceOnlyCapUpdated(bytes32 indexed asset, uint256 reduceOnlyCap, uint256 nonce);
    event PartialLiquidationThresholdUpdated(bytes32 indexed asset, uint256 partialLiquidationThreshold, uint256 nonce);
    event PartialLiquidationRateUpdated(bytes32 indexed asset, uint256 partialLiquidationRate, uint256 nonce);
    event MaxNumOrdersUpdated(bytes32 indexed asset, uint256 maxNumOrders, uint256 nonce);
    event MaxLimitsPerTxUpdated(bytes32 indexed asset, uint8 maxLimitsPerTx, uint256 nonce);
    event MinLimitOrderAmountInBaseUpdated(bytes32 indexed asset, uint256 minLimitOrderAmountInBase, uint256 nonce);
    event TickSizeUpdated(bytes32 indexed asset, uint256 tickSize, uint256 nonce);

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                ERRORS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    error MarketNotFound();
    error BookNotFound();
    error InvalidNonce();
    error ConditionNotMet();
    error OrderExpired();
    error InvalidSignature();
    error MarketAlreadyInitialized();
    error ProtocolNotActive();
    error ProtocolAlreadyActive();
    error ProtocolAlreadyInactive();
    error CannotActivateMarket();
    error CannotDeactivateMarket();
    error CannotDelistMarket();
    error CannotRelistMarket();
    error CrossMarginAlreadyEnabled();
    error CrossMarginAlreadyDisabled();
    error InvalidSettings();

    modifier onlyAdmin() {
        _checkRolesOrOwner(Constants.ADMIN_ROLE);
        _;
    }

    modifier onlyActiveProtocol() virtual {
        if (!StorageLib.loadClearingHouse().active) revert ProtocolNotActive();
        _;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                             INITIALIZATION
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function initialize(address owner_, uint16[] calldata takerFees, uint16[] calldata makerFees)
        external
        initializer
    {
        FeeManager storage feeManager = StorageLib.loadFeeManager();

        _assertNonZero(uint160(owner_));
        _assertNonZero(takerFees.length);
        _assertNonZero(makerFees.length);
        _assertNonZero(takerFees[0]);
        _assertNonZero(makerFees[0]);

        _initializeOwner(owner_);

        feeManager.setTakerFeeRates(takerFees);
        feeManager.setMakerFeeRates(makerFees);

        emit TakerFeeRatesUpdated(takerFees, StorageLib.incNonce());
        emit MakerFeeRatesUpdated(makerFees, StorageLib.incNonce());
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            MARKET CREATION
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function createMarket(bytes32 asset, MarketParams calldata params) external onlyAdmin {
        Market storage market = StorageLib.loadMarket(asset);

        if (market.exists()) revert MarketAlreadyInitialized();

        _validateLeverage(params.maxOpenLeverage);
        _validateMaintenanceMarginRatio(params.maintenanceMarginRatio, params.maxOpenLeverage);
        _assertDecimal(params.liquidationFeeRate);
        _validateFundingInterval(params.fundingInterval, params.resetInterval);
        _assertNonZero(params.resetIterations);
        _assertDecimal(params.interestRate.abs());
        _assertDecimal(params.divergenceCap);
        _assertDecimal(params.partialLiquidationRate);
        _assertNonZero(params.partialLiquidationThreshold);
        _validateMinBookValue(params.lotSize, params.tickSize);
        _validateConform(params.minLimitOrderAmountInBase, params.lotSize);
        _assertNonZero(params.maxLimitsPerTx);

        MarketSettings memory marketSettings = MarketSettings({
            status: Status.INACTIVE,
            maxOpenLeverage: params.maxOpenLeverage,
            maintenanceMarginRatio: params.maintenanceMarginRatio,
            liquidationFeeRate: params.liquidationFeeRate,
            divergenceCap: params.divergenceCap,
            reduceOnlyCap: params.reduceOnlyCap,
            partialLiquidationThreshold: params.partialLiquidationThreshold,
            partialLiquidationRate: params.partialLiquidationRate,
            crossMarginEnabled: params.crossMarginEnabled
        });

        FundingRateSettings memory fundingSettings = FundingRateSettings({
            fundingInterval: params.fundingInterval,
            resetInterval: params.resetInterval,
            resetIterations: params.resetIterations,
            innerClamp: params.innerClamp,
            outerClamp: params.outerClamp,
            interestRate: params.interestRate
        });

        BookSettings memory bookSettings = BookSettings({
            maxNumOrders: params.maxNumOrders,
            maxLimitsPerTx: params.maxLimitsPerTx,
            minLimitOrderAmountInBase: params.minLimitOrderAmountInBase,
            tickSize: params.tickSize
        });

        market.init({
            asset: asset,
            marketSettings: marketSettings,
            fundingSettings: fundingSettings,
            initialPrice: params.initialPrice
        });

        CLOBLib.init(asset, bookSettings, params.lotSize);

        emit MarketCreated(
            asset, marketSettings, fundingSettings, bookSettings, params.initialPrice, params.lotSize, StorageLib.incNonce()
        );
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                              MAINTENANCE
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function setMarkPrice(bytes32 asset, uint256 indexPrice) external onlyAdmin {
        Market storage market = StorageLib.loadMarket(asset);

        if (!market.exists()) revert MarketNotFound();

        market.setMarkPrice(indexPrice);
    }

    function settleFunding(bytes32 asset) external onlyAdmin {
        Market storage market = StorageLib.loadMarket(asset);

        if (!market.exists()) revert MarketNotFound();

        market.settleFunding();
    }

    function setFeeTiers(address[] calldata accounts, FeeTier[] calldata feeTiers) external onlyAdmin {
        if (accounts.length != feeTiers.length) revert InvalidSettings();

        address account;
        FeeTier feeTier;
        for (uint256 i; i < accounts.length; ++i) {
            account = accounts[i];
            feeTier = feeTiers[i];

            StorageLib.loadFeeManager().setAccountFeeTier(account, feeTier);

            emit FeeTierUpdated(account, feeTier, StorageLib.incNonce());
        }
    }

    function setLiquidatorPoints(address account, uint256 points) external onlyAdmin {
        StorageLib.loadClearingHouse().liquidatorPoints[account] = points;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                 AUTH
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function grantAdmin(address account) external onlyOwner {
        _grantRoles(account, Constants.ADMIN_ROLE);
    }

    function revokeAdmin(address account) external onlyOwner {
        _removeRoles(account, Constants.ADMIN_ROLE);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                             INSURANCE FUND
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function insuranceFundDeposit(uint256 amount) external onlyOwner {
        StorageLib.loadInsuranceFund().deposit(amount);
    }

    function insuranceFundWithdraw(uint256 amount) external onlyOwner {
        StorageLib.loadInsuranceFund().withdraw(amount);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                           CONDITIONAL ORDERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function placeTwapOrder(address account, PlaceOrderArgs calldata args, SignData calldata signData)
        external
        onlyAdmin
        onlyActiveProtocol
    {
        ClearingHouse storage clearingHouse = StorageLib.loadClearingHouse();

        _validateSig(clearingHouse, account, abi.encode(args), signData);

        clearingHouse.nonceUsed[account][signData.nonce] = true;

        clearingHouse.placeOrder(account, args, BookType.STANDARD);
    }

    function placeTPSLOrder(
        address account,
        PlaceOrderArgs calldata args,
        Condition calldata condition,
        SignData calldata signData
    ) external onlyAdmin onlyActiveProtocol {
        ClearingHouse storage clearingHouse = StorageLib.loadClearingHouse();

        _validateSig(clearingHouse, account, abi.encode(args, condition), signData);

        clearingHouse.nonceUsed[account][signData.nonce] = true;

        if (!clearingHouse.market[args.asset].isTPSLConditionMet(args.side, condition)) revert ConditionNotMet();

        clearingHouse.placeOrder(account, args, BookType.STANDARD);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                           PROTOCOL SETTINGS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function setTakerFeeRates(uint16[] calldata takerFeeRates) external onlyAdmin {
        StorageLib.loadFeeManager().setTakerFeeRates(takerFeeRates);

        emit TakerFeeRatesUpdated(takerFeeRates, StorageLib.incNonce());
    }

    function setMakerFeeRates(uint16[] calldata makerFeeRates) external onlyAdmin {
        StorageLib.loadFeeManager().setMakerFeeRates(makerFeeRates);

        emit MakerFeeRatesUpdated(makerFeeRates, StorageLib.incNonce());
    }

    function activateProtocol() external onlyAdmin {
        ClearingHouse storage clearingHouse = StorageLib.loadClearingHouse();

        if (clearingHouse.active) revert ProtocolAlreadyActive();

        clearingHouse.active = true;

        emit ProtocolActivated(StorageLib.incNonce());
    }

    function deactivateProtocol() external onlyAdmin {
        ClearingHouse storage clearingHouse = StorageLib.loadClearingHouse();

        if (!clearingHouse.active) revert ProtocolAlreadyInactive();

        clearingHouse.active = false;

        emit ProtocolDeactivated(StorageLib.incNonce());
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            MARKET SETTINGS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @notice actives market of 'asset'
    /// @dev reverts if market is not INACTIVE
    function activateMarket(bytes32 asset) external onlyAdmin {
        Market storage market = StorageLib.loadMarket(asset);

        if (!market.exists()) revert MarketNotFound();

        if (StorageLib.loadMarketSettings(asset).status != Status.INACTIVE) revert CannotActivateMarket();

        StorageLib.loadMarketSettings(asset).status = Status.ACTIVE;

        emit MarketStatusUpdated(asset, Status.ACTIVE, StorageLib.incNonce());
    }

    /// @notice deactivates market of 'asset'
    /// @dev reverts if market is not ACTIVE
    function deactivateMarket(bytes32 asset) external onlyAdmin {
        Market storage market = StorageLib.loadMarket(asset);

        if (!market.exists()) revert MarketNotFound();

        if (StorageLib.loadMarketSettings(asset).status != Status.ACTIVE) revert CannotDeactivateMarket();

        StorageLib.loadMarketSettings(asset).status = Status.INACTIVE;

        emit MarketStatusUpdated(asset, Status.INACTIVE, StorageLib.incNonce());
    }

    /// @notice delists market of 'asset'
    /// @dev reverts if market is not INACTIVE
    function delistMarket(bytes32 asset) external onlyAdmin {
        Market storage market = StorageLib.loadMarket(asset);

        if (!market.exists()) revert MarketNotFound();

        if (StorageLib.loadMarketSettings(asset).status != Status.INACTIVE) revert CannotDelistMarket();

        StorageLib.loadMarketSettings(asset).status = Status.DELISTED;

        emit MarketStatusUpdated(asset, Status.DELISTED, StorageLib.incNonce());
    }

    /// @notice relists market of 'asset'
    /// @dev reverts if market is not DELISTED
    /// @dev reverts position oi and book oi are not cleared
    function relistMarket(bytes32 asset) external onlyAdmin {
        Market storage market = StorageLib.loadMarket(asset);
        MarketMetadata storage marketMetadata = StorageLib.loadMarketMetadata(asset);
        Book storage book = StorageLib.loadBook(asset);

        if (!market.exists()) revert MarketNotFound();
        if (!book.exists()) revert BookNotFound();

        if (StorageLib.loadMarketSettings(asset).status != Status.DELISTED) revert CannotRelistMarket();

        // book oi must be cleared
        if (book.metadata.baseOI + book.metadata.quoteOI > 0) revert CannotRelistMarket();

        // position oi must be cleared
        if (marketMetadata.longOI + marketMetadata.shortOI > 0) revert CannotRelistMarket();

        StorageLib.loadMarketSettings(asset).status = Status.INACTIVE;

        emit MarketStatusUpdated(asset, Status.INACTIVE, StorageLib.incNonce());
    }

    function enableCrossMargin(bytes32 asset) external onlyAdmin {
        Market storage market = StorageLib.loadMarket(asset);

        if (!market.exists()) revert MarketNotFound();

        if (StorageLib.loadMarketSettings(asset).crossMarginEnabled) revert CrossMarginAlreadyEnabled();

        StorageLib.loadMarketSettings(asset).crossMarginEnabled = true;

        emit CrossMarginEnabled(asset, StorageLib.incNonce());
    }

    function disableCrossMargin(bytes32 asset) external onlyAdmin {
        Market storage market = StorageLib.loadMarket(asset);

        if (!market.exists()) revert MarketNotFound();

        if (!StorageLib.loadMarketSettings(asset).crossMarginEnabled) revert CrossMarginAlreadyDisabled();

        StorageLib.loadMarketSettings(asset).crossMarginEnabled = false;

        emit CrossMarginDisabled(asset, StorageLib.incNonce());
    }

    /// @notice sets the maximum leverage for a market of 'asset'
    /// @param maxOpenLeverage the maximum leverage to set, must be between 1x and 100x (1e18 to 100e18)
    function setMaxLeverage(bytes32 asset, uint256 maxOpenLeverage) external onlyAdmin {
        _validateLeverage(maxOpenLeverage);

        Market storage market = StorageLib.loadMarket(asset);

        if (!market.exists()) revert MarketNotFound();

        StorageLib.loadMarketSettings(asset).maxOpenLeverage = maxOpenLeverage;

        emit MaxLeverageUpdated(asset, maxOpenLeverage, StorageLib.incNonce());
    }

    function setMinMarginRatio(bytes32 asset, uint256 maintenanceMarginRatio) external onlyAdmin {
        Market storage market = StorageLib.loadMarket(asset);
        MarketSettings storage settings = StorageLib.loadMarketSettings(asset);

        if (!market.exists()) revert MarketNotFound();

        _validateMaintenanceMarginRatio(maintenanceMarginRatio, settings.maxOpenLeverage);

        settings.maintenanceMarginRatio = maintenanceMarginRatio;

        emit MaintenanceMarginRatioUpdated(asset, maintenanceMarginRatio, StorageLib.incNonce());
    }

    /// @notice sets the liquidation fee rate for a market of 'asset'
    function setLiquidationFeeRate(bytes32 asset, uint256 liquidationFeeRate) external onlyAdmin {
        _assertDecimal(liquidationFeeRate);

        Market storage market = StorageLib.loadMarket(asset);

        if (!market.exists()) revert MarketNotFound();

        StorageLib.loadMarketSettings(asset).liquidationFeeRate = liquidationFeeRate;

        emit LiquidationFeeRateUpdated(asset, liquidationFeeRate, StorageLib.incNonce());
    }

    /// @notice sets max divergence between tradable price & mark
    /// @param divergenceCap e.g. .5 for 50% divergence from mark
    function setDivergenceCap(bytes32 asset, uint256 divergenceCap) external onlyAdmin {
        _assertDecimal(divergenceCap);

        Market storage market = StorageLib.loadMarket(asset);

        if (!market.exists()) revert MarketNotFound();

        StorageLib.loadMarketSettings(asset).divergenceCap = divergenceCap;

        emit DivergenceCapUpdated(asset, divergenceCap, StorageLib.incNonce());
    }

    /// @notice sets max number of reduce-only orders that can be placed
    function setReduceOnlyCap(bytes32 asset, uint256 reduceOnlyCap) external onlyAdmin {
        Market storage market = StorageLib.loadMarket(asset);

        if (!market.exists()) revert MarketNotFound();

        StorageLib.loadMarketSettings(asset).reduceOnlyCap = reduceOnlyCap;

        emit ReduceOnlyCapUpdated(asset, reduceOnlyCap, StorageLib.incNonce());
    }

    /// @notice sets the value threshold where a position must be partially liquidated
    /// @param partialLiquidationThreshold value in quote
    function setPartialLiquidationThreshold(bytes32 asset, uint256 partialLiquidationThreshold) external onlyAdmin {
        _assertNonZero(partialLiquidationThreshold);

        Market storage market = StorageLib.loadMarket(asset);

        if (!market.exists()) revert MarketNotFound();

        StorageLib.loadMarketSettings(asset).partialLiquidationThreshold = partialLiquidationThreshold;

        emit PartialLiquidationThresholdUpdated(asset, partialLiquidationThreshold, StorageLib.incNonce());
    }

    /// @notice sets the rate at which a position is partially liquidated
    /// @param partialLiquidationRate percentage of position to liquidate, e.g. 0.1 for 10%
    function setPartialLiquidationRate(bytes32 asset, uint256 partialLiquidationRate) external onlyAdmin {
        _assertDecimal(partialLiquidationRate);

        Market storage market = StorageLib.loadMarket(asset);

        if (!market.exists()) revert MarketNotFound();

        StorageLib.loadMarketSettings(asset).partialLiquidationRate = partialLiquidationRate;

        emit PartialLiquidationRateUpdated(asset, partialLiquidationRate, StorageLib.incNonce());
    }

    /// @notice sets the funding interval for a market of 'asset'
    function setFundingInterval(bytes32 asset, uint256 fundingInterval, uint256 resetInterval) external onlyAdmin {
        _assertNonZero(fundingInterval);

        Market storage market = StorageLib.loadMarket(asset);

        if (!market.exists()) revert MarketNotFound();

        FundingRateSettings storage settings = StorageLib.loadFundingRateSettings(asset);

        _validateFundingInterval(fundingInterval, resetInterval);

        settings.fundingInterval = fundingInterval;
        settings.resetInterval = resetInterval;

        emit FundingIntervalUpdated(asset, fundingInterval, resetInterval, StorageLib.incNonce());
    }

    function setResetIterations(bytes32 asset, uint256 resetIterations) external onlyAdmin {
        _assertNonZero(resetIterations);

        Market storage market = StorageLib.loadMarket(asset);

        if (!market.exists()) revert MarketNotFound();

        StorageLib.loadFundingRateSettings(asset).resetIterations = resetIterations;

        emit ResetIterationsUpdated(asset, resetIterations, StorageLib.incNonce());
    }

    /// @notice sets clamp range for funding rate
    function setFundingClamps(bytes32 asset, uint256 innerClamp, uint256 outerClamp) external onlyAdmin {
        Market storage market = StorageLib.loadMarket(asset);

        if (!market.exists()) revert MarketNotFound();

        FundingRateSettings storage settings = StorageLib.loadFundingRateSettings(asset);

        settings.innerClamp = innerClamp;
        settings.outerClamp = outerClamp;

        emit FundingClampsUpdated(asset, innerClamp, outerClamp, StorageLib.incNonce());
    }

    function setInterestRate(bytes32 asset, int256 interestRate) external onlyAdmin {
        _assertDecimal(interestRate.abs());

        Market storage market = StorageLib.loadMarket(asset);

        if (!market.exists()) revert MarketNotFound();

        StorageLib.loadFundingRateSettings(asset).interestRate = interestRate;

        emit InterestRateUpdated(asset, interestRate, StorageLib.incNonce());
    }

    function setMaxNumOrders(bytes32 asset, uint256 maxNumOrders) external onlyAdmin {
        _assertNonZero(maxNumOrders);

        Book storage book = StorageLib.loadBook(asset);

        if (!book.exists()) revert BookNotFound();

        StorageLib.loadBookSettings(asset).maxNumOrders = maxNumOrders;

        emit MaxNumOrdersUpdated(asset, maxNumOrders, StorageLib.incNonce());
    }

    function setMaxLimitsPerTx(bytes32 asset, uint8 maxLimitsPerTx) external onlyAdmin {
        _assertNonZero(maxLimitsPerTx);

        Book storage book = StorageLib.loadBook(asset);

        if (!book.exists()) revert BookNotFound();

        StorageLib.loadBookSettings(asset).maxLimitsPerTx = maxLimitsPerTx;

        emit MaxLimitsPerTxUpdated(asset, maxLimitsPerTx, StorageLib.incNonce());
    }

    function setMinLimitOrderAmountInBase(bytes32 asset, uint256 minLimitOrderAmountInBase) external onlyAdmin {
        Book storage book = StorageLib.loadBook(asset);

        if (!book.exists()) revert BookNotFound();

        _validateConform(minLimitOrderAmountInBase, book.config.lotSize);

        StorageLib.loadBookSettings(asset).minLimitOrderAmountInBase = minLimitOrderAmountInBase;

        emit MinLimitOrderAmountInBaseUpdated(asset, minLimitOrderAmountInBase, StorageLib.incNonce());
    }

    function setTickSize(bytes32 asset, uint256 tickSize) external onlyAdmin {
        Book storage book = StorageLib.loadBook(asset);

        if (!book.exists()) revert BookNotFound();

        _validateMinBookValue(StorageLib.loadBookSettings(asset).minLimitOrderAmountInBase, tickSize);
        _validateMinBookValue(book.config.lotSize, tickSize);

        StorageLib.loadBookSettings(asset).tickSize = tickSize;

        emit TickSizeUpdated(asset, tickSize, StorageLib.incNonce());
    }

    function setMarketSettings(bytes32 asset, MarketSettings calldata settings) external onlyAdmin {
        Market storage market = StorageLib.loadMarket(asset);
        MarketSettings storage marketSettings = StorageLib.loadMarketSettings(asset);

        if (!market.exists()) revert MarketNotFound();

        if (marketSettings.status != settings.status) revert InvalidSettings();

        _validateLeverage(settings.maxOpenLeverage);
        _validateMaintenanceMarginRatio(settings.maintenanceMarginRatio, settings.maxOpenLeverage);
        _assertDecimal(settings.liquidationFeeRate);
        _assertDecimal(settings.divergenceCap);
        _assertNonZero(settings.partialLiquidationThreshold);
        _assertDecimal(settings.partialLiquidationRate);

        marketSettings.init(settings);

        if (settings.crossMarginEnabled) emit CrossMarginEnabled(asset, StorageLib.incNonce());
        else emit CrossMarginDisabled(asset, StorageLib.incNonce());

        emit MaxLeverageUpdated(asset, settings.maxOpenLeverage, StorageLib.incNonce());
        emit MaintenanceMarginRatioUpdated(asset, settings.maintenanceMarginRatio, StorageLib.incNonce());
        emit LiquidationFeeRateUpdated(asset, settings.liquidationFeeRate, StorageLib.incNonce());
        emit DivergenceCapUpdated(asset, settings.divergenceCap, StorageLib.incNonce());
        emit ReduceOnlyCapUpdated(asset, settings.reduceOnlyCap, StorageLib.incNonce());
        emit PartialLiquidationThresholdUpdated(asset, settings.partialLiquidationThreshold, StorageLib.incNonce());
        emit PartialLiquidationRateUpdated(asset, settings.partialLiquidationRate, StorageLib.incNonce());
    }

    function setFundingRateSettings(bytes32 asset, FundingRateSettings calldata settings) external onlyAdmin {
        Market storage market = StorageLib.loadMarket(asset);

        if (!market.exists()) revert MarketNotFound();

        _validateFundingInterval(settings.fundingInterval, settings.resetInterval);
        _assertNonZero(settings.resetIterations);
        _assertDecimal(settings.interestRate.abs());

        StorageLib.loadFundingRateSettings(asset).init(settings);

        emit FundingIntervalUpdated(asset, settings.fundingInterval, settings.resetInterval, StorageLib.incNonce());
        emit ResetIterationsUpdated(asset, settings.resetIterations, StorageLib.incNonce());
        emit FundingClampsUpdated(asset, settings.innerClamp, settings.outerClamp, StorageLib.incNonce());
        emit InterestRateUpdated(asset, settings.interestRate, StorageLib.incNonce());
    }

    function setBookSettings(bytes32 asset, BookSettings calldata settings) external onlyAdmin {
        _validateMinBookValue(settings.minLimitOrderAmountInBase, settings.tickSize);
        _assertNonZero(settings.maxLimitsPerTx);
        _assertNonZero(settings.maxNumOrders);

        if (!StorageLib.loadBook(asset).exists()) revert BookNotFound();

        BookSettings storage bookSettings = StorageLib.loadBookSettings(asset);

        bookSettings.maxNumOrders = settings.maxNumOrders;
        bookSettings.maxLimitsPerTx = settings.maxLimitsPerTx;
        bookSettings.minLimitOrderAmountInBase = settings.minLimitOrderAmountInBase;
        bookSettings.tickSize = settings.tickSize;

        emit MaxNumOrdersUpdated(asset, settings.maxNumOrders, StorageLib.incNonce());
        emit MaxLimitsPerTxUpdated(asset, settings.maxLimitsPerTx, StorageLib.incNonce());
        emit MinLimitOrderAmountInBaseUpdated(asset, settings.minLimitOrderAmountInBase, StorageLib.incNonce());
        emit TickSizeUpdated(asset, settings.tickSize, StorageLib.incNonce());
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _validateSig(
        ClearingHouse storage clearingHouse,
        address signer,
        bytes memory order,
        SignData calldata signData
    ) internal view {
        if (clearingHouse.nonceUsed[signer][signData.nonce]) revert InvalidNonce();
        if (signData.expiry < block.timestamp) revert OrderExpired();

        bytes32 hash = keccak256(bytes.concat(order, abi.encode(signData.expiry, signData.nonce)));

        if (!signer.isValidSignatureNowCalldata(hash, signData.sig)) revert InvalidSignature();
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                              ASSERTIONS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _validateMinBookValue(uint256 minLimitOrderAmountInBase, uint256 tickSize) private pure {
        if (minLimitOrderAmountInBase == 0 || tickSize == 0) revert InvalidSettings();
        _assertNonZero(minLimitOrderAmountInBase.fullMulDiv(tickSize, 1e18));
    }

    function _validateConform(uint256 value, uint256 standard) private pure {
        _assertNonZero(value);
        if (value % standard != 0) revert InvalidSettings();
    }

    function _validateLeverage(uint256 maxOpenLeverage) private pure {
        if (maxOpenLeverage < 1e18 || maxOpenLeverage > 100e18) revert InvalidSettings();
    }

    function _validateFundingInterval(uint256 fundingInterval, uint256 resetInterval) private pure {
        _assertNonZero(fundingInterval);
        _assertNonZero(resetInterval);
        if (fundingInterval < resetInterval) revert InvalidSettings();
    }

    function _validateMaintenanceMarginRatio(uint256 maintenanceMarginRatio, uint256 maxLeverage) private pure {
        _assertDecimal(maintenanceMarginRatio);
        if (1e18.fullMulDiv(1e18, maintenanceMarginRatio) < maxLeverage) revert InvalidSettings();
    }

    function _assertNonZero(uint256 value) private pure {
        if (value == 0) revert InvalidSettings();
    }

    function _assertDecimal(uint256 decimal) private pure {
        if (decimal == 0) revert InvalidSettings();
        if (decimal > 1e18) revert InvalidSettings();
    }
}
