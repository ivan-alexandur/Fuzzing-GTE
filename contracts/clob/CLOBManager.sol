// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

// Local types, libs, contracts, and interfaces
import {CLOB, ICLOB} from "./CLOB.sol";
import {Side, OrderId} from "./types/Order.sol";
import {MakerCredit} from "./types/TransientMakerData.sol";
import {ICLOBManager, ConfigParams, SettingsParams} from "./ICLOBManager.sol";
import {FeeTiers} from "./types/FeeData.sol";
import {CLOBStorageLib, MarketConfig, MarketSettings, MIN_MIN_LIMIT_ORDER_AMOUNT_BASE} from "./types/Book.sol";

// Internal package libs and interfaces
import {IAccountManager} from "../account-manager/IAccountManager.sol";
import {EventNonceLib as CLOBEventNonce} from "contracts/utils/types/EventNonce.sol";

// Solady and OZ imports
import {Initializable} from "@solady/utils/Initializable.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {OwnableRoles as CLOBAdminOwnableRoles} from "@solady/auth/OwnableRoles.sol";
import {IERC20Metadata} from "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {BeaconProxy, IBeacon} from "@openzeppelin/proxy/beacon/BeaconProxy.sol";

struct CLOBManagerStorage {
    mapping(address clob => bool) isCLOB;
    mapping(bytes32 tokenPairHash => address) clob;
    mapping(address account => bool) maxLimitWhitelist;
}

using CLOBManagerStorageLib for CLOBManagerStorage global;

/// @custom:storage-location erc7201:CLOBManagerStorage
library CLOBManagerStorageLib {
    bytes32 constant CLOB_MANAGER_STORAGE_POSITION =
        keccak256(abi.encode(uint256(keccak256("CLOBManagerStorage")) - 1)) & ~bytes32(uint256(0xff));

    /// @dev Gets the storage slot of the storage struct for the contract calling this library function
    // slither-disable-next-line uninitialized-storage
    function getCLOBManagerStorage() internal pure returns (CLOBManagerStorage storage self) {
        bytes32 position = CLOB_MANAGER_STORAGE_POSITION;

        // slither-disable-next-line assembly
        assembly {
            self.slot := position
        }
    }
}

/**
 * @title CLOBManager
 * @notice Main contract that handles CLOB admin functionality and fee calculations
 */
contract CLOBManager is ICLOBManager, CLOBAdminOwnableRoles, Initializable {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for address;

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                ERRORS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @dev sig: 0x1e4f7d8c
    error InvalidPair();
    /// @dev sig: 0x8fc6f59b
    error MarketExists();
    /// @dev sig: 0xe591f33d
    error InvalidSettings();
    /// @dev sig: 0x1eb00b06
    error InvalidTokenAddress();
    /// @dev sig: 0x353f2237
    error AdminPanelArrayLengthsInvalid();
    /// @dev sig: 0xf9f68635
    error MarketUnauthorized();
    /// @dev sig: 0x6fbe54bd
    error InvalidBeaconAddress();
    /// @dev sig: 0x19ae8c78
    error CLOBBeaconMustHaveRouter();

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                EVENTS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    event MarketCreated(
        uint256 indexed eventNonce,
        address indexed creator,
        address indexed baseToken,
        address quoteToken,
        address market,
        uint8 quoteDecimals,
        uint8 baseDecimals,
        ConfigParams config,
        SettingsParams settings
    );

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                CONSTANTS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @dev The abi version of this impl so the indexer can handle event-changing upgrades
    uint256 public constant ABI_VERSION = 1;

    /// @dev Create and call markets to edit their settings
    uint256 public constant MARKET_MANAGER = 1;
    /// @dev Sets users' fee tiers in this contract
    uint256 public constant FEE_TIER_SETTER = 1 << 1;
    /// @dev Whitelists addresses to bypass the markets' max limits per txn
    uint256 public constant MAX_LIMIT_WHITELISTER = 1 << 2;
    /// @dev Clears expired orders from markets
    uint256 public constant EXPIRED_ORDER_CLEARER = 1 << 3;

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            IMMUTABLE STATE
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @dev The beacon proxy containing the logic implementation all clobs' storage use
    address public immutable beacon;
    /// @dev The external AccountManager contract
    IAccountManager public immutable accountManager;

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            CONSTRUCTOR
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    constructor(address _beacon, address _accountManager) {
        if (_beacon == address(0)) revert InvalidBeaconAddress();
        beacon = _beacon;
        accountManager = IAccountManager(_accountManager);
        _disableInitializers();
    }

    /// @dev Initializes the contract following ERC1967Factory pattern
    function initialize(address _owner) external initializer {
        _initializeOwner(_owner);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            EXTERNAL GETTERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @notice Gets the market address for a given `tokenA` and `tokenB`
    function getMarketAddress(address tokenA, address tokenB) external view returns (address marketAddress) {
        return _getStorage().clob[_getTokenHash(tokenA, tokenB)];
    }

    /// @notice Gets if `market` is a clob created by this factory
    function isMarket(address market) external view returns (bool) {
        return _getStorage().isCLOB[market];
    }

    /// @notice Gets whether an account is exempt from max limits
    function getMaxLimitExempt(address account) external view returns (bool) {
        return _getStorage().maxLimitWhitelist[account];
    }

    /// @notice Gets the current event nonce
    function getEventNonce() external view returns (uint256) {
        return CLOBEventNonce.getCurrentNonce();
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            ADMIN FUNCTIONS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @notice Creates a new market for `quoteToken` and `baseToken` using beacon proxy
    function createMarket(address baseToken, address quoteToken, SettingsParams calldata settings)
        external
        virtual
        onlyOwnerOrRoles(MARKET_MANAGER)
        returns (address marketAddress)
    {
        _assertValidTokenPair(quoteToken, baseToken);

        uint8 quoteDecimals = IERC20Metadata(quoteToken).decimals();
        uint8 baseDecimals = IERC20Metadata(baseToken).decimals();

        ConfigParams memory config;

        config.quoteToken = quoteToken;
        config.baseToken = baseToken;
        config.quoteSize = 10 ** quoteDecimals;
        config.baseSize = 10 ** baseDecimals;

        _assertValidSettings(settings, config.baseSize);

        CLOBManagerStorage storage self = _getStorage();

        bytes32 tokenPairHash = _getTokenHash(quoteToken, baseToken);

        if (self.clob[tokenPairHash] > address(0)) revert MarketExists();

        bytes memory initData = abi.encodeWithSelector(
            CLOB.initialize.selector,
            MarketConfig({
                quoteToken: config.quoteToken,
                baseToken: config.baseToken,
                quoteSize: config.quoteSize,
                baseSize: config.baseSize
            }),
            MarketSettings({
                status: true,
                maxLimitsPerTx: settings.maxLimitsPerTx,
                minLimitOrderAmountInBase: settings.minLimitOrderAmountInBase,
                tickSize: settings.tickSize,
                lotSizeInBase: settings.lotSizeInBase
            }),
            settings.owner
        );

        // Beacon is immutable and itself non upgradeable
        marketAddress = address(new BeaconProxy(beacon, initData));

        self.isCLOB[marketAddress] = true;
        self.clob[tokenPairHash] = marketAddress;

        // Register the market in AccountManager
        accountManager.registerMarket(marketAddress);

        _emitMarketCreated(msg.sender, marketAddress, quoteDecimals, baseDecimals, config, settings);
    }

    /// @notice Sets the tick size for a market
    function setTickSize(ICLOB market, uint256 newTickSize) external onlyOwnerOrRoles(MARKET_MANAGER) {
        market.setTickSize(newTickSize);
    }

    /// @notice Sets the lot size for a market
    function setLotSizeInBase(ICLOB market, uint256 newLotSize) external onlyOwnerOrRoles(MARKET_MANAGER) {
        market.setLotSizeInBase(newLotSize);
    }

    /// @notice Sets the min limit order amount in base for a market
    function setMinLimitOrderAmountInBase(ICLOB market, uint256 newMinLimitOrderAmountInBase)
        external
        onlyOwnerOrRoles(MARKET_MANAGER)
    {
        market.setMinLimitOrderAmountInBase(newMinLimitOrderAmountInBase);
    }

    /// @notice Clears out expired orders from one side of a market
    function adminCancelExpiredOrders(ICLOB market, OrderId[] calldata ids, Side side)
        external
        onlyOwnerOrRoles(EXPIRED_ORDER_CLEARER)
    {
        market.adminCancelExpiredOrders(ids, side);
    }

    /// @notice Sets fee tiers for accounts
    function setAccountFeeTiers(address[] calldata accounts, FeeTiers[] calldata feeTiers)
        external
        onlyOwnerOrRoles(FEE_TIER_SETTER)
    {
        accountManager.setSpotAccountFeeTiers(accounts, feeTiers);
    }

    /// @notice Sets max limit exemptions for accounts
    function setMaxLimitsExempt(address[] calldata accounts, bool[] calldata toggles)
        external
        onlyOwnerOrRoles(MAX_LIMIT_WHITELISTER)
    {
        if (accounts.length != toggles.length) revert AdminPanelArrayLengthsInvalid();

        CLOBManagerStorage storage self = _getStorage();
        for (uint256 i = 0; i < accounts.length; i++) {
            self.maxLimitWhitelist[accounts[i]] = toggles[i];
        }
    }

    /// @notice Sets the max limits per tx for a market
    function setMaxLimitsPerTx(ICLOB market, uint8 newMaxLimits) external onlyOwnerOrRoles(MARKET_MANAGER) {
        market.setMaxLimitsPerTx(newMaxLimits);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            INTERNAL ASSERTIONS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @dev Checks config and settings params are within correct bounds
    function _assertValidSettings(SettingsParams calldata settings, uint256 baseSize) internal pure {
        if (settings.maxLimitsPerTx == 0) revert InvalidSettings();
        if (settings.minLimitOrderAmountInBase < MIN_MIN_LIMIT_ORDER_AMOUNT_BASE) revert InvalidSettings();
        if (settings.minLimitOrderAmountInBase < settings.lotSizeInBase) revert InvalidSettings();
        if (settings.tickSize.fullMulDiv(settings.lotSizeInBase, baseSize) == 0) revert InvalidSettings();
    }

    /// @dev Performs sanity checks on the addresses passed to make it slightly more difficult to deploy a broken market
    function _assertValidTokenPair(address quoteToken, address baseToken) internal pure {
        if (quoteToken == baseToken) revert InvalidPair();
        if (quoteToken == address(0)) revert InvalidTokenAddress();
        if (baseToken == address(0)) revert InvalidTokenAddress();
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            PRIVATE HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @dev Event helper that prevents stack from blowing without IR
    function _emitMarketCreated(
        address creator,
        address marketAddress,
        uint8 quoteDecimals,
        uint8 baseDecimals,
        ConfigParams memory config,
        SettingsParams calldata settings
    ) internal {
        emit MarketCreated(
            CLOBEventNonce.inc(),
            creator,
            config.baseToken,
            config.quoteToken,
            marketAddress,
            quoteDecimals,
            baseDecimals,
            config,
            settings
        );
    }

    /// @dev Gets the token hash which can be used as a UID for a market
    function _getTokenHash(address tokenA, address tokenB) internal pure returns (bytes32) {
        (tokenA, tokenB) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        return keccak256(abi.encodePacked(tokenA, tokenB));
    }

    /// @dev Helper to set the storage slot of the storage struct for this contract
    function _getStorage() internal pure returns (CLOBManagerStorage storage ds) {
        return CLOBManagerStorageLib.getCLOBManagerStorage();
    }
}
