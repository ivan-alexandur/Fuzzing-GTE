// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

// Local types, libs, and interfaces
import {ICLOB} from "./ICLOB.sol";
import {ICLOBManager} from "./ICLOBManager.sol";
import {IAccountManager} from "../account-manager/IAccountManager.sol";
import {CLOBStorageLib} from "./types/Book.sol";
import {TransientMakerData, MakerCredit} from "./types/TransientMakerData.sol";
import {Order, OrderLib, OrderId, OrderIdLib, Side} from "./types/Order.sol";
import {Book, BookLib, Limit, MarketConfig, MarketSettings} from "./types/Book.sol";

// Internal package types, libs, and interfaces
import {IOperatorPanel} from "contracts/utils/interfaces/IOperatorPanel.sol";
import {SpotOperatorRoles} from "contracts/utils/OperatorPanel.sol";
import {OperatorHelperLib} from "contracts/utils/types/OperatorHelperLib.sol";
import {EventNonceLib as CLOBEventNonce} from "contracts/utils/types/EventNonce.sol";

// Solady and OZ imports
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

/**
 * @title CLOB
 * Main spot market contract for trading asset pairs on an orderbook
 */
contract CLOB is ICLOB, Ownable2StepUpgradeable {
    using OrderLib for *;
    using OrderIdLib for uint256;
    using OrderIdLib for address;
    using FixedPointMathLib for uint256;
    using SafeCastLib for uint256;

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                EVENTS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @dev sig: 0xc0208cc462e0f7d7b2329363da41c40e123ba2c9db4b8b03a183140d67ad1c60
    event CancelFailed(uint256 indexed eventNonce, uint256 orderId, address owner);

    /// @dev sig: 0xacb8106c549e32473004de43588b1bd716fc82873c60790caab04149f2cb9466
    event OrderCanceled(
        uint256 indexed eventNonce,
        uint256 indexed orderId,
        address indexed owner,
        uint256 quoteTokenRefunded,
        uint256 baseTokenRefunded,
        CancelType context
    );

    /// @dev sig: 0x06956ad87855e4ad9efb290bad3c7ef7a8c7cff5e28b5926b570b492c45b9c37
    event OrderAmended(
        uint256 indexed eventNonce, Order preAmend, AmendArgs args, int256 quoteTokenDelta, int256 baseTokenDelta
    );

    /// @dev sig: 0x76a9cd4a6124a3883e613ae4146376b48db63cfd526306751587a148642fce56
    event OrderProcessed(
        uint256 indexed eventNonce,
        address indexed account,
        uint256 indexed orderId,
        ICLOB.TiF tif,
        uint256 limitPrice,
        uint256 basePosted,
        int256 quoteDelta,
        int256 baseDelta,
        uint256 takerFee
    );

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                ERRORS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @dev sig: 0x175e7f45
    error ZeroAmend();
    /// @dev sig: 0xb82df155
    error ZeroOrder();
    /// @dev sig: 0x91b373e1
    error AmendInvalid();
    /// @dev sig: 0xc56873ba
    error OrderExpired();
    /// @dev sig: 0xd8a00083
    error ZeroCostTrade();
    /// @dev sig: 0xf1a5cd31
    error FOKOrderNotFilled();
    /// @dev sig: 0xba2ea531
    error AmendUnauthorized();
    /// @dev sig: 0xf99412b1
    error CancelUnauthorized();
    /// @dev sig: 0xd268c85f
    error ManagerUnauthorized();
    /// @dev sig: 0xd093feb7
    error FactoryUnauthorized();
    /// @dev sig: 0x3e27eb6d
    error PostOnlyOrderWouldFill();
    /// @dev sig: 0xb134397c
    error AmendNonPostOnlyInvalid();
    /// @dev sig: 0x315ff5e5
    error MaxOrdersInBookPostNotCompetitive();

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                CONSTANTS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/


    /// @dev The abi version of this impl so the indexer can handle event-changing upgrades
    uint256 public constant ABI_VERSION = 1;

    /// @dev The global router address available to all CLOBs that can bypass the operator check
    address public immutable gteRouter;
    /// @dev The operator contract for role-based access control (same as accountManager)
    IOperatorPanel public immutable operator;
    /// @dev The factory that created this contract and controls its settings as well as processing maker settlement
    ICLOBManager public immutable factory;
    /// @dev The account manager contract for direct balance operations (and operator checks)
    IAccountManager public immutable accountManager;
    /// @dev Maximum number of maker orders allowed per side of the order book
    /// before the least competitive orders get bumped
    uint256 public immutable maxNumOrdersPerSide;

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                MODIFIERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    modifier onlySenderOrOperator(address account, SpotOperatorRoles requiredRole) {
        OperatorHelperLib.onlySenderOrOperator(operator, gteRouter, account, requiredRole);
        _;
    }

    modifier onlyManager() {
        if (msg.sender != address(factory)) revert ManagerUnauthorized();
        _;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                    CONSTRUCTOR AND INITIALIZATION
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _factory, address _gteRouter, address _accountManager, uint256 _maxNumOrdersPerSide) {
        factory = ICLOBManager(_factory);
        gteRouter = _gteRouter;
        operator = IOperatorPanel(_accountManager);
        accountManager = IAccountManager(_accountManager);
        maxNumOrdersPerSide = _maxNumOrdersPerSide;
        _disableInitializers();
    }

    /// @notice Initializes the `marketConfig`, `marketSettings`, and `initialOwner` of the market
    function initialize(MarketConfig memory marketConfig, MarketSettings memory marketSettings, address initialOwner)
        external
        initializer
    {
        __CLOB_init(marketConfig, marketSettings, initialOwner);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            EXTERNAL GETTERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @notice Gets base token
    function getBaseToken() external view returns (address) {
        return _getStorage().config().baseToken;
    }

    /// @notice Gets quote token
    function getQuoteToken() external view returns (address) {
        return _getStorage().config().quoteToken;
    }

    /// @notice Gets the base token amount equivalent to `quoteAmount` at a given `price`
    /// @dev This price does not have to be within tick size
    function getBaseTokenAmount(uint256 price, uint256 quoteAmount) external view returns (uint256) {
        return _getStorage().getBaseTokenAmount(price, quoteAmount);
    }

    /// @notice Gets the quote token amount equivalent to `baseAmount` at a given `price`
    /// @dev This price dos not have to be within tick size
    function getQuoteTokenAmount(uint256 price, uint256 baseAmount) external view returns (uint256) {
        return _getStorage().getQuoteTokenAmount(price, baseAmount);
    }

    /// @notice Gets the market config
    function getMarketConfig() external view returns (MarketConfig memory) {
        return _getStorage().config();
    }

    /// @notice Gets the market settings
    function getMarketSettings() external view returns (MarketSettings memory) {
        return _getStorage().settings();
    }

    /// @notice Gets tick size
    function getTickSize() external view returns (uint256) {
        return _getStorage().settings().tickSize;
    }

    /// @notice Gets lot size in base
    function getLotSizeInBase() external view returns (uint256) {
        return _getStorage().settings().lotSizeInBase;
    }

    /// @notice Gets quote and base open interest
    function getOpenInterest() external view returns (uint256 quoteOi, uint256 baseOi) {
        return (_getStorage().metadata().quoteTokenOpenInterest, _getStorage().metadata().baseTokenOpenInterest);
    }

    /// @notice Gets an order in the book from its id
    function getOrder(uint256 orderId) external view returns (Order memory) {
        return _getStorage().orders[orderId.toOrderId()];
    }

    /// @notice Gets top of book as price (max bid and min ask)
    function getTOB() external view returns (uint256 maxBid, uint256 minAsk) {
        return (_getStorage().getBestBidPrice(), _getStorage().getBestAskPrice());
    }

    /// @notice Gets the bid or ask Limit at a price depending on `side`
    function getLimit(uint256 price, Side side) external view returns (Limit memory) {
        return _getStorage().getLimit(price, side);
    }

    /// @notice Gets total bid limit orders in the book
    function getNumBids() external view returns (uint256) {
        return _getStorage().metadata().numBids;
    }

    /// @notice Gets total ask limit orders in the book
    function getNumAsks() external view returns (uint256) {
        return _getStorage().metadata().numAsks;
    }

    /// @notice Gets a list of orders, starting at an orderId
    function getNextOrders(uint256 startOrderId, uint256 numOrders) external view returns (Order[] memory) {
        return _getStorage().getNextOrders(startOrderId.toOrderId(), numOrders);
    }

    /// @notice Gets the next populated higher price limit to `price` on a side of the book
    function getNextBiggestPrice(uint256 price, Side side) external view returns (uint256) {
        return _getStorage().getNextBiggestPrice(price, side);
    }

    /// @notice Gets the next populated lower price limit to `price` on a side of the book
    function getNextSmallestPrice(uint256 price, Side side) external view returns (uint256) {
        return _getStorage().getNextSmallestPrice(price, side);
    }

    /// @notice Gets the next order id (nonce) that will be used upon placing an order
    /// @dev Placing both limit and fill orders increment the next orderId
    function getNextOrderId() external view returns (uint256) {
        return (_getStorage().metadata().orderIdCounter + 1);
    }

    /// @notice Gets the current event nonce
    function getEventNonce() external view returns (uint256) {
        return CLOBEventNonce.getCurrentNonce();
    }

    /// @notice Gets `pageSize` of orders from TOB down from a `startPrice` and on a given `side` of the book
    function getOrdersPaginated(uint256 startPrice, Side side, uint256 pageSize)
        external
        view
        returns (Order[] memory result, Order memory nextOrder)
    {
        Book storage ds = _getStorage();

        nextOrder = side == Side.BUY
            ? ds.orders[ds.bidLimits[startPrice].headOrder]
            : ds.orders[ds.askLimits[startPrice].headOrder];

        return ds.getOrdersPaginated(nextOrder, pageSize);
    }

    /// @notice Gets `pageSize` of orders from TOB down, starting at `startOrderId`
    function getOrdersPaginated(OrderId startOrderId, uint256 pageSize)
        external
        view
        returns (Order[] memory result, Order memory nextOrder)
    {
        Book storage ds = _getStorage();
        nextOrder = ds.orders[startOrderId];

        return ds.getOrdersPaginated(nextOrder, pageSize);
    }

    function getBaseQuanta() external view returns (uint256) {
        return _getStorage().getBaseQuanta();
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            AUTH-ONLY SETTERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @notice Sets the new max limits per txn
    function setMaxLimitsPerTx(uint8 newMaxLimits) external onlyManager {
        _getStorage().setMaxLimitsPerTx(newMaxLimits);
    }

    /// @notice Sets the tick size of the book
    /// @dev New orders' limit prices % tickSize must be 0
    function setTickSize(uint256 tickSize) external onlyManager {
        _getStorage().setTickSize(tickSize);
    }

    /// @notice Sets the minimum amount an order (in base) must be to be placed on the book
    /// @dev Reducing an order below this amount will cause the order to get cancelled
    function setMinLimitOrderAmountInBase(uint256 newMinLimitOrderAmountInBase) external onlyManager {
        _getStorage().setMinLimitOrderAmountInBase(newMinLimitOrderAmountInBase);
    }

    /// @notice Sets the lot size in base for standardized trade sizes
    /// @dev Orders must be multiples of lot size. Setting to 0 disables lot size restrictions
    function setLotSizeInBase(uint256 newLotSizeInBase) external onlyManager {
        _getStorage().setLotSizeInBase(newLotSizeInBase);
    }

    /// @notice Clears out expired orders from one side of the book
    /// @dev Cancels must be on a single side bc settlement only treats one side (either base or quote)
    /// as a refund and the other side as a fill that incurs trading fees
    function adminCancelExpiredOrders(OrderId[] calldata ids, Side side) external onlyManager returns (bool[] memory) {
        bool[] memory removed = new bool[](ids.length);

        Book storage ds = _getStorage();

        for (uint256 i = 0; i < ids.length; i++) {
            Order storage o = ds.orders[ids[i]];

            if (!o.isExpired() || o.side != side) continue;

            removed[i] = true;
            side == Side.BUY ? _removeExpiredBid(ds, o) : _removeExpiredAsk(ds, o);
        }

        // Virtual taker side is opposite of cancelled orders' side to ensure refunds aren't charged fees
        Side virtualTakerSide = side == Side.BUY ? Side.SELL : Side.BUY;
        _settleIncomingOrder({
            ds: ds,
            account: address(0),
            side: virtualTakerSide,
            quoteTokenAmount: 0,
            baseTokenAmount: 0
        });

        return removed;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                        EXTERNAL ORDER PLACEMENT
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function placeOrder(address account, ICLOB.PlaceOrderArgs calldata args)
        external
        onlySenderOrOperator(account, SpotOperatorRoles.PLACE_ORDER)
        returns (ICLOB.PlaceOrderResult memory)
    {
        Book storage ds = _getStorage();

        // inc order nonce regardless if the order is a pure take, or a custom id is used
        uint256 orderId = ds.incrementOrderId();

        if (args.clientOrderId > 0) {
            orderId = account.getClientOrderId(args.clientOrderId);
            ds.assertUnusedOrderId(orderId);
        }

        Order memory newOrder = args.toOrderChecked(orderId, account);

        // Fires an {OrderProcessed} event at the end of either sub-routines
        if (args.side == Side.BUY) return _processBid(ds, account, newOrder, args);
        else return _processAsk(ds, account, newOrder, args);
    }

    /// @notice Amends an existing order for `account`
    function amend(address account, AmendArgs calldata args)
        external
        onlySenderOrOperator(account, SpotOperatorRoles.PLACE_ORDER)
        returns (int256 quoteDelta, int256 baseDelta)
    {
        Book storage ds = _getStorage();
        Order storage order = ds.orders[args.orderId.toOrderId()];

        if (order.id.unwrap() == 0) revert OrderLib.OrderNotFound();
        if (order.owner != account) revert AmendUnauthorized();

        ds.assertLimitPriceInBounds(args.price);
        ds.assertMakeAmountInBounds(args.amountInBase);

        if (args.cancelTimestamp.isExpired()) revert AmendInvalid();

        // Update order
        (quoteDelta, baseDelta) = _processAmend(ds, order, args);
    }

    /// @notice Cancels a list of orders for `account`
    function cancel(address account, CancelArgs memory args)
        external
        onlySenderOrOperator(account, SpotOperatorRoles.PLACE_ORDER)
        returns (uint256, uint256)
    {
        Book storage ds = _getStorage();
        (address quoteToken, address baseToken) = (ds.config().quoteToken, ds.config().baseToken);

        (uint256 totalQuoteTokenRefunded, uint256 totalBaseTokenRefunded) = _executeCancel(ds, account, args);

        if (totalBaseTokenRefunded > 0) accountManager.creditAccount(account, baseToken, totalBaseTokenRefunded);
        if (totalQuoteTokenRefunded > 0) accountManager.creditAccount(account, quoteToken, totalQuoteTokenRefunded);

        return (totalQuoteTokenRefunded, totalBaseTokenRefunded);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            INTERNAL FILL LOGIC
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @dev Performs matching and settlement for a bid order
    function _processBid(Book storage ds, address account, Order memory newOrder, ICLOB.PlaceOrderArgs calldata args)
        internal
        returns (ICLOB.PlaceOrderResult memory res)
    {
        (uint256 postAmount, uint256 totalQuoteSent, uint256 totalBaseReceived) =
            _executeBid(ds, newOrder, args.tif, args.baseDenominated);

        if (postAmount + totalQuoteSent + totalBaseReceived == 0) revert ZeroOrder();

        if (totalBaseReceived != totalQuoteSent && (totalBaseReceived == 0 || totalQuoteSent == 0)) {
            revert ZeroCostTrade();
        }

        uint256 takerFee = _settleIncomingOrder(ds, account, Side.BUY, totalQuoteSent + postAmount, totalBaseReceived);

        // Populate result struct
        res.account = account;
        res.orderId = newOrder.id.unwrap();
        res.quoteTokenAmountTraded = -int256(totalQuoteSent);
        res.baseTokenAmountTraded = int256(totalBaseReceived);
        res.takerFee = takerFee;

        // Sets the base posted of the remainder of the order that was a make
        // Order amount is always converted to base when posting
        if (uint8(args.tif) <= 1) res.basePosted = newOrder.amount;

        // Set whether this was a market order (limitPrice = max) or limit order
        res.wasMarketOrder = (args.limitPrice == type(uint256).max);

        emit OrderProcessed({
            eventNonce: CLOBEventNonce.inc(),
            account: account,
            orderId: res.orderId,
            tif: args.tif,
            limitPrice: args.limitPrice,
            basePosted: res.basePosted,
            quoteDelta: res.quoteTokenAmountTraded,
            baseDelta: res.baseTokenAmountTraded,
            takerFee: takerFee
        });
    }

    function _processAsk(Book storage ds, address account, Order memory newOrder, ICLOB.PlaceOrderArgs calldata args)
        internal
        returns (ICLOB.PlaceOrderResult memory res)
    {
        (uint256 postAmount, uint256 totalQuoteReceived, uint256 totalBaseSent) =
            _executeAsk(ds, newOrder, args.tif, args.baseDenominated);

        if (postAmount + totalQuoteReceived + totalBaseSent == 0) revert ZeroOrder();

        if (totalBaseSent != totalQuoteReceived && (totalBaseSent == 0 || totalQuoteReceived == 0)) {
            revert ZeroCostTrade();
        }

        uint256 takerFee = _settleIncomingOrder(ds, account, Side.SELL, totalQuoteReceived, totalBaseSent + postAmount);

        // Populate result struct
        res.account = account;
        res.orderId = newOrder.id.unwrap();
        res.quoteTokenAmountTraded = int256(totalQuoteReceived);
        res.baseTokenAmountTraded = -int256(totalBaseSent);
        res.takerFee = takerFee;

        // Sets the base posted of the remainder of the order that was a make
        // Order amount is always converted to base when posting
        if (uint8(args.tif) <= 1) res.basePosted = newOrder.amount;

        // Set whether this was a market order (limitPrice = 0) or limit order
        res.wasMarketOrder = (args.limitPrice == 0);

        emit OrderProcessed({
            eventNonce: CLOBEventNonce.inc(),
            account: account,
            orderId: res.orderId,
            tif: args.tif,
            limitPrice: args.limitPrice,
            basePosted: res.basePosted,
            quoteDelta: res.quoteTokenAmountTraded,
            baseDelta: res.baseTokenAmountTraded,
            takerFee: takerFee
        });
    }

    /// @dev Performs the core matching and placement of a bid order into the book
    function _executeBid(Book storage ds, Order memory newOrder, ICLOB.TiF tif, bool baseDenominated)
        internal
        returns (uint256 postAmount, uint256 totalQuoteSent, uint256 totalBaseReceived)
    {
        // Attempt to fill any of the incoming order that's overlapping into asks
        if (ds.getBestAskPrice() <= newOrder.price) {
            if (tif == ICLOB.TiF.MOC) revert PostOnlyOrderWouldFill();
            (totalQuoteSent, totalBaseReceived) = _matchIncomingBid(ds, newOrder, baseDenominated);
        }

        if (tif == ICLOB.TiF.FOK && newOrder.amount > 0) revert FOKOrderNotFilled();

        bool isTake = false;
        (isTake, newOrder.amount) = _getTakeOrPostAmount(
            ds, tif, newOrder.amount, totalQuoteSent | totalBaseReceived > 0, baseDenominated, newOrder.price
        );

        // The order was a TAKE only either due to TIF settings,
        // or because a partially filled GTC had insufficient remaining amount in base
        if (isTake) return (0, totalQuoteSent, totalBaseReceived);

        // Validate price and amount bounds
        ds.assertLimitPriceInBounds(newOrder.price);

        // // Enforce per-tx max limit placements (unless exempt) and increment counter
        ds.incrementLimitsPlaced(address(factory), msg.sender);

        // The book is full, pop the least competitive order (or revert if incoming is the least competitive)
        if (ds.metadata().numBids == maxNumOrdersPerSide) {
            uint256 minBidPrice = ds.getWorstBidPrice();
            if (newOrder.price <= minBidPrice) revert MaxOrdersInBookPostNotCompetitive();

            _removeNonCompetitiveOrder(ds, ds.orders[ds.bidLimits[minBidPrice].tailOrder]);
        }

        ds.addOrderToBook(newOrder);
        postAmount = ds.getQuoteTokenAmount(newOrder.price, newOrder.amount);

        return (postAmount, totalQuoteSent, totalBaseReceived);
    }

    function _executeAsk(Book storage ds, Order memory newOrder, ICLOB.TiF tif, bool baseDenominated)
        internal
        returns (uint256 postAmount, uint256 totalQuoteReceived, uint256 totalBaseSent)
    {
        // Attempt to fill any of the incoming order that's overlapping into bids
        if (ds.getBestBidPrice() >= newOrder.price) {
            if (tif == ICLOB.TiF.MOC) revert PostOnlyOrderWouldFill();
            (totalQuoteReceived, totalBaseSent) = _matchIncomingAsk(ds, newOrder, baseDenominated);
        }

        if (tif == ICLOB.TiF.FOK && newOrder.amount > 0) revert FOKOrderNotFilled();

        bool isTake = false;
        (isTake, newOrder.amount) = _getTakeOrPostAmount(
            ds, tif, newOrder.amount, totalQuoteReceived | totalBaseSent > 0, baseDenominated, newOrder.price
        );

        // The order was a TAKE only either due to TIF settings,
        // or because a partially filled GTC had insufficient remaining amount in base
        if (isTake) return (0, totalQuoteReceived, totalBaseSent);

        // Validate price and amount bounds
        ds.assertLimitPriceInBounds(newOrder.price);

        // Enforce per-tx max limit placements (unless exempt) and increment counter
        ds.incrementLimitsPlaced(address(factory), msg.sender);

        // The book is full, pop the least competitive order (or revert if incoming is the least competitive)
        if (ds.metadata().numAsks == maxNumOrdersPerSide) {
            uint256 maxAskPrice = ds.getWorstAskPrice();
            if (newOrder.price >= maxAskPrice) revert MaxOrdersInBookPostNotCompetitive();

            _removeNonCompetitiveOrder(ds, ds.orders[ds.askLimits[maxAskPrice].tailOrder]);
        }

        ds.addOrderToBook(newOrder);
        postAmount = newOrder.amount;

        return (postAmount, totalQuoteReceived, totalBaseSent);
    }

    function _getTakeOrPostAmount(
        Book storage ds,
        ICLOB.TiF tif,
        uint256 remainingAmount,
        bool matchOccurred,
        bool baseDenominated,
        uint256 limitPrice
    ) internal view returns (bool isTake, uint256 postAmount) {
        // Order is explicitly a TAKE
        if (tif == ICLOB.TiF.FOK || tif == ICLOB.TiF.IOC) return (true, 0);

        // Order amount must be in base and conform to current lot size before posting
        remainingAmount = baseDenominated
            ? ds.boundToLots(remainingAmount)
            : ds.boundToLots(ds.getBaseTokenAmount(remainingAmount, limitPrice));

        // There is not enough order amount to post
        if (remainingAmount < ds.settings().minLimitOrderAmountInBase) {
            // If a GTC had any take, and the remaining amount is invalid,
            // this is permissible as a full take instead of reverting
            if (tif == ICLOB.TiF.GTC && matchOccurred) return (true, 0);

            // The make-only order violates minimum amount
            revert BookLib.LimitOrderAmountInvalid();
        }

        return (false, remainingAmount);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                        INTERNAL AMEND LOGIC
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @dev Performs the amending of an order
    function _processAmend(Book storage ds, Order storage order, AmendArgs calldata args)
        internal
        returns (int256 quoteTokenDelta, int256 baseTokenDelta)
    {
        Order memory preAmend = order;
        address maker = preAmend.owner;

        if (args.cancelTimestamp.isExpired() || args.amountInBase < ds.settings().minLimitOrderAmountInBase) {
            revert AmendInvalid();
        }

        // Check lot size compliance after other validations
        ds.assertLotSizeCompliant(args.amountInBase);

        if (order.side != args.side || order.price != args.price) {
            // change place in book
            (quoteTokenDelta, baseTokenDelta) = _executeAmendNewOrder(ds, order, args);
        } else if (order.amount != args.amountInBase) {
            // change amount
            (quoteTokenDelta, baseTokenDelta) =
                _executeAmendAmount(ds, order, args.amountInBase, uint32(args.cancelTimestamp));
        } else if (args.cancelTimestamp != order.cancelTimestamp) {
            order.cancelTimestamp = uint32(args.cancelTimestamp);
        } else {
            revert ZeroAmend();
        }

        emit OrderAmended(CLOBEventNonce.inc(), preAmend, args, quoteTokenDelta, baseTokenDelta);

        _settleAmend(ds, maker, quoteTokenDelta, baseTokenDelta);
    }

    /// @dev Performs the removal and replacement of an amended order with a new price or side
    function _executeAmendNewOrder(Book storage ds, Order storage order, AmendArgs calldata args)
        internal
        returns (int256 quoteTokenDelta, int256 baseTokenDelta)
    {
        Order memory newOrder;

        newOrder.owner = order.owner;
        newOrder.id = order.id;
        newOrder.side = args.side;
        newOrder.price = args.price;
        newOrder.amount = args.amountInBase;
        newOrder.cancelTimestamp = uint32(args.cancelTimestamp);

        if (order.side == Side.BUY) quoteTokenDelta = ds.getQuoteTokenAmount(order.price, order.amount).toInt256();
        else baseTokenDelta = order.amount.toInt256();

        ds.removeOrderFromBook(order);

        uint256 postAmount;
        if (args.side == Side.BUY) {
            (postAmount,,) = _executeBid(ds, newOrder, ICLOB.TiF.MOC, true);

            quoteTokenDelta -= postAmount.toInt256();
        } else {
            (postAmount,,) = _executeAsk(ds, newOrder, ICLOB.TiF.MOC, true);

            baseTokenDelta -= postAmount.toInt256();
        }
    }

    /// @dev Performs the updating of an amended order with a new amount
    function _executeAmendAmount(Book storage ds, Order storage order, uint256 amount, uint32 cancelTimestamp)
        internal
        returns (int256 quoteTokenDelta, int256 baseTokenDelta)
    {
        if (order.side == Side.BUY) {
            int256 oldAmountInQuote = ds.getQuoteTokenAmount(order.price, order.amount).toInt256();
            int256 newAmountInQuote = ds.getQuoteTokenAmount(order.price, amount).toInt256();

            quoteTokenDelta = oldAmountInQuote - newAmountInQuote;

            ds.metadata().quoteTokenOpenInterest =
                uint256(ds.metadata().quoteTokenOpenInterest.toInt256() - quoteTokenDelta);
        } else {
            baseTokenDelta = order.amount.toInt256() - amount.toInt256();

            ds.metadata().baseTokenOpenInterest =
                uint256(ds.metadata().baseTokenOpenInterest.toInt256() - baseTokenDelta);
        }

        order.amount = amount;
        order.cancelTimestamp = cancelTimestamp;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                        INTERNAL MATCHING LOGIC
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @dev Internal struct to prevent blowing stack
    struct __MatchData__ {
        uint256 matchedAmount;
        uint256 baseDelta;
        uint256 quoteDelta;
    }

    /// @dev Match incoming bid order to best asks
    function _matchIncomingBid(Book storage ds, Order memory incomingOrder, bool amountIsBase)
        internal
        returns (uint256 totalQuoteSent, uint256 totalBaseReceived)
    {
        uint256 bestAskPrice = ds.getBestAskPrice();

        while (bestAskPrice <= incomingOrder.price && incomingOrder.amount > 0) {
            Limit storage limit = ds.askLimits[bestAskPrice];
            Order storage bestAskOrder = ds.orders[limit.headOrder];

            if (bestAskOrder.isExpired()) {
                _removeExpiredAsk(ds, bestAskOrder);
                bestAskPrice = ds.getBestAskPrice();
                continue;
            }

            // slither-disable-next-line uninitialized-local
            __MatchData__ memory currMatch =
                _matchIncomingOrder(ds, bestAskOrder, incomingOrder, bestAskPrice, amountIsBase);

            incomingOrder.amount -= currMatch.matchedAmount;

            totalQuoteSent += currMatch.quoteDelta;
            totalBaseReceived += currMatch.baseDelta;

            bestAskPrice = ds.getBestAskPrice();
        }
    }

    /// @dev Match incoming ask order to best bids
    function _matchIncomingAsk(Book storage ds, Order memory incomingOrder, bool amountIsBase)
        internal
        returns (uint256 totalQuoteReceived, uint256 totalBaseSent)
    {
        uint256 bestBidPrice = ds.getBestBidPrice();

        while (bestBidPrice >= incomingOrder.price && incomingOrder.amount > 0) {
            Limit storage limit = ds.bidLimits[bestBidPrice];
            Order storage bestBidOrder = ds.orders[limit.headOrder];

            if (bestBidOrder.isExpired()) {
                _removeExpiredBid(ds, bestBidOrder);
                bestBidPrice = ds.getBestBidPrice();
                continue;
            }

            // slither-disable-next-line uninitialized-local
            __MatchData__ memory currMatch =
                _matchIncomingOrder(ds, bestBidOrder, incomingOrder, bestBidPrice, amountIsBase);

            incomingOrder.amount -= currMatch.matchedAmount;

            totalQuoteReceived += currMatch.quoteDelta;
            totalBaseSent += currMatch.baseDelta;

            bestBidPrice = ds.getBestBidPrice();
        }
    }

    function _boundMakerToLotSize(Book storage ds, Order storage order, uint256 lotSize) internal {
        uint256 remainder = order.amount % lotSize;
        if (remainder == 0) return;

        if (remainder == order.amount) {
            if (order.side == Side.BUY) _removeExpiredBid(ds, order);
            else _removeExpiredAsk(ds, order);
            return;
        }

        if (order.side == Side.BUY) {
            uint256 quoteTokenAmount = ds.getQuoteTokenAmount(order.price, remainder);
            TransientMakerData.addQuoteToken(order.owner, quoteTokenAmount);

            ds.metadata().quoteTokenOpenInterest -= quoteTokenAmount;
        } else {
            TransientMakerData.addBaseToken(order.owner, remainder);
            ds.metadata().baseTokenOpenInterest -= remainder;
        }
        order.amount -= remainder;
    }

    /// @dev Matches an incoming order to its next counterparty order, crediting the maker and removing the counterparty order if fully filled
    function _matchIncomingOrder(
        Book storage ds,
        Order storage makerOrder,
        Order memory takerOrder,
        uint256 matchedPrice,
        bool amountIsBase
    ) internal returns (__MatchData__ memory matchData) {
        uint256 lotSize = ds.settings().lotSizeInBase;

        _boundMakerToLotSize(ds, makerOrder, lotSize);
        uint256 matchedBase = makerOrder.amount;

        if (amountIsBase) {
            // denominated in base
            matchData.baseDelta = (matchedBase.min(takerOrder.amount) / lotSize) * lotSize;
            matchData.quoteDelta = ds.getQuoteTokenAmount(matchedPrice, matchData.baseDelta);
            matchData.matchedAmount = matchData.baseDelta != matchedBase ? takerOrder.amount : matchData.baseDelta;
        } else {
            // denominated in quote
            matchData.baseDelta =
                (matchedBase.min(ds.getBaseTokenAmount(matchedPrice, takerOrder.amount)) / lotSize) * lotSize;
            matchData.quoteDelta = ds.getQuoteTokenAmount(matchedPrice, matchData.baseDelta);
            matchData.matchedAmount = matchData.baseDelta != matchedBase ? takerOrder.amount : matchData.quoteDelta;
        }

        // Early return if no tradeable amount due to lot size constraints (dust)
        if (matchData.baseDelta == 0) return matchData;

        bool orderRemoved = matchData.baseDelta == matchedBase;

        // Handle token accounting for maker.
        if (takerOrder.side == Side.BUY) {
            TransientMakerData.addQuoteToken(makerOrder.owner, matchData.quoteDelta);

            if (!orderRemoved) ds.metadata().baseTokenOpenInterest -= matchData.baseDelta;
        } else {
            TransientMakerData.addBaseToken(makerOrder.owner, matchData.baseDelta);

            if (!orderRemoved) ds.metadata().quoteTokenOpenInterest -= matchData.quoteDelta;
        }

        if (orderRemoved) ds.removeOrderFromBook(makerOrder);
        else makerOrder.amount -= matchData.baseDelta;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                        INTERNAL EXPIRY LOGIC
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @dev Removes an expired ask, adding the order's amount to settlement data as a base refund
    function _removeExpiredAsk(Book storage ds, Order storage order) internal {
        uint256 baseTokenAmount = order.amount;

        // We can add the refund to maker fills because both cancelled asks and filled bids are credited in baseTokens
        TransientMakerData.addBaseToken(order.owner, baseTokenAmount);

        ds.removeOrderFromBook(order);
    }

    /// @dev Removes an expired bid, adding the order's amount to settlement as a quote refund
    function _removeExpiredBid(Book storage ds, Order storage order) internal {
        uint256 quoteTokenAmount = ds.getQuoteTokenAmount(order.price, order.amount);

        // We can add the refund to maker fills because both cancelled bids and filled asks are credited in quoteTokens
        TransientMakerData.addQuoteToken(order.owner, quoteTokenAmount);

        ds.removeOrderFromBook(order);
    }

    /// @notice Removes the least competitive order from the book
    function _removeNonCompetitiveOrder(Book storage ds, Order storage order) internal {
        uint256 quoteRefunded;
        uint256 baseRefunded;
        if (order.side == Side.BUY) {
            quoteRefunded = ds.getQuoteTokenAmount(order.price, order.amount);
            accountManager.creditAccountNoEvent(order.owner, address(ds.config().quoteToken), quoteRefunded);
        } else {
            baseRefunded = order.amount;
            accountManager.creditAccountNoEvent(order.owner, address(ds.config().baseToken), baseRefunded);
        }

        emit OrderCanceled(
            CLOBEventNonce.inc(),
            order.id.unwrap(),
            order.owner,
            quoteRefunded,
            baseRefunded,
            CancelType.NON_COMPETITIVE
        );

        ds.removeOrderFromBook(order);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                        INTERNAL CANCEL LOGIC
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @dev Performs the cancellation of an account's orders
    function _executeCancel(Book storage ds, address account, CancelArgs memory args)
        internal
        returns (uint256 totalQuoteTokenRefunded, uint256 totalBaseTokenRefunded)
    {
        uint256 numOrders = args.orderIds.length;
        for (uint256 i = 0; i < numOrders; i++) {
            uint256 orderId = args.orderIds[i];
            Order storage order = ds.orders[orderId.toOrderId()];

            if (order.isNull()) {
                emit CancelFailed(CLOBEventNonce.inc(), orderId, account);
                continue; // Order may have been matched
            } else if (order.owner != account) {
                revert CancelUnauthorized();
            }

            uint256 quoteTokenRefunded = 0;
            uint256 baseTokenRefunded = 0;

            if (order.side == Side.BUY) {
                quoteTokenRefunded = ds.getQuoteTokenAmount(order.price, order.amount);
                totalQuoteTokenRefunded += quoteTokenRefunded;
            } else {
                baseTokenRefunded = order.amount;
                totalBaseTokenRefunded += baseTokenRefunded;
            }

            ds.removeOrderFromBook(order);

            uint256 eventNonce = CLOBEventNonce.inc();
            emit OrderCanceled(eventNonce, orderId, account, quoteTokenRefunded, baseTokenRefunded, CancelType.USER);
        }
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                        INTERNAL SETTLEMENT LOGIC
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @dev Settles token accounting in the factory for the incoming trade
    function _settleIncomingOrder(
        Book storage ds,
        address account,
        Side side,
        uint256 quoteTokenAmount,
        uint256 baseTokenAmount
    ) internal returns (uint256 takerFee) {
        SettleParams memory settleParams;

        (settleParams.quoteToken, settleParams.baseToken) = (ds.config().quoteToken, ds.config().baseToken);

        settleParams.taker = account;
        settleParams.side = side;

        settleParams.takerQuoteAmount = quoteTokenAmount;
        settleParams.takerBaseAmount = baseTokenAmount;

        settleParams.makerCredits = TransientMakerData.getMakerCreditsAndClearStorage();

        return accountManager.settleIncomingOrder(settleParams);
    }

    /// @dev Settles the token deltas in the factory from an amend
    function _settleAmend(Book storage ds, address maker, int256 quoteTokenDelta, int256 baseTokenDelta) internal {
        if (quoteTokenDelta > 0) {
            accountManager.creditAccount(maker, address(ds.config().quoteToken), uint256(quoteTokenDelta));
        } else if (quoteTokenDelta < 0) {
            accountManager.debitAccount(maker, address(ds.config().quoteToken), uint256(-quoteTokenDelta));
        }

        if (baseTokenDelta > 0) {
            accountManager.creditAccount(maker, address(ds.config().baseToken), uint256(baseTokenDelta));
        } else if (baseTokenDelta < 0) {
            accountManager.debitAccount(maker, address(ds.config().baseToken), uint256(-baseTokenDelta));
        }
    }

    // This naming reflects OZ initializer naming
    // slither-disable-next-line naming-convention
    function __CLOB_init(MarketConfig memory marketConfig, MarketSettings memory marketSettings, address initialOwner)
        internal
    {
        __Ownable_init(initialOwner);
        CLOBStorageLib.init(_getStorage(), marketConfig, marketSettings);
    }

    /// @dev Helper to assign the storage slot to the Book struct
    function _getStorage() internal pure returns (Book storage) {
        return CLOBStorageLib._getCLOBStorage();
    }
}
