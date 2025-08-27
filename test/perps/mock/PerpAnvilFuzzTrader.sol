// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/Script.sol";

import {TestPlus} from "../../../lib/solady/test/utils/TestPlus.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

import {Constants} from "../../../contracts/perps/types/Constants.sol";
import {Position} from "../../../contracts/perps/types/Position.sol";

import {MockPerpManager} from "./MockPerpManager.sol";

import {PlaceOrderArgs, PlaceOrderResult} from "../../../contracts/perps/types/Structs.sol";
import {TiF, Side} from "../../../contracts/perps/types/Enums.sol";
import {Order} from "../../../contracts/perps/types/Order.sol";

contract PerpAnvilFuzzTrader is Script, TestPlus {
    using SafeTransferLib for address;
    using FixedPointMathLib for uint256;

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                SETUP
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    constructor(address _perpManager, bytes32 _market, bytes32 _alternateMarket, address[] memory _accounts) {
        perpManager = MockPerpManager(_perpManager);
        market = _market;
        alternateMarket = _alternateMarket;
        accounts = _accounts;
    }

    function setAccounts(address[] memory _accounts) external {
        accounts = _accounts;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                STATE
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    address[] accounts;

    MockPerpManager perpManager;

    bytes32 market;
    bytes32 alternateMarket;

    mapping(bytes32 => uint256) public totalBaseTraded;

    mapping(address => bool) hasSetLeverage;

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               FUZZ TRADE
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    address constant TOKEN = Constants.USDC;

    address taker;
    address maker1;
    address maker2;
    address maker3;

    uint256 takerAmount;
    uint256 maker1Amount;
    uint256 maker2Amount;
    uint256 maker3Amount;

    uint256 orderId1;
    uint256 orderId2;
    uint256 orderId3;
    uint256 orderId4;

    function fuzzTrade(uint256, uint256 iterations) public {
        _setupFunds();
        _setAlternatePositions();

        for (uint256 i; i < iterations; i++) {
            _setupTraders();
            _setupAmounts();
            _setupLeverage();
            _setupFundingPayment();

            uint256 price = _getPrice();

            perpManager.mockSetMarkPrice(market, price);

            bool takerLong = _randomChance(2);

            orderId1 = _placeLimitOrder(maker1, maker1Amount, price, !takerLong);
            orderId2 = _placeLimitOrder(maker2, maker2Amount, price, !takerLong);
            orderId3 = _placeLimitOrder(maker3, maker3Amount, price, !takerLong);

            _placeFillOrder(price, takerLong);

            _clearBook();
        }
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _placeLimitOrder(address maker, uint256 amount, uint256 price, bool bid)
        internal
        returns (uint256 orderId)
    {
        PlaceOrderArgs memory makerArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: market,
            side: bid ? Side.BUY : Side.SELL,
            limitPrice: price,
            amount: amount,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        return perpManager.placeOrder(maker, makerArgs).orderId;
    }

    function _placeFillOrder(uint256 price, bool long) internal {
        _fillOrder(price, long);
    }

    function _fillOrder(uint256 price, bool long) internal {
        PlaceOrderArgs memory takerArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: market,
            side: long ? Side.BUY : Side.SELL,
            limitPrice: price,
            amount: takerAmount,
            baseDenominated: true,
            tif: _randomChance(2) ? TiF.IOC : TiF.GTC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        PlaceOrderResult memory result = perpManager.placeOrder(taker, takerArgs);

        orderId4 = result.orderId;
        totalBaseTraded[market] += result.baseTraded;
    }

    function _clearBook() internal {
        _cancelOrder(orderId1);
        _cancelOrder(orderId2);
        _cancelOrder(orderId3);
        _cancelOrder(orderId4);
    }

    function _cancelOrder(uint256 orderId) internal {
        Order memory order = perpManager.getLimitOrder(market, orderId);

        if (order.amount == 0) return;

        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = orderId;

        perpManager.cancelLimitOrders(market, order.owner, order.subaccount, orderIds);
    }

    function _setupTraders() internal {
        address[] memory traders = new address[](4);

        for (uint256 i; i < traders.length; ++i) {
            traders[i] = _getUniqueTrader(traders);
        }

        taker = traders[0];
        maker1 = traders[1];
        maker2 = traders[2];
        maker3 = traders[3];
    }

    function _setupFunds() internal {
        for (uint256 i; i < 4; i++) {
            _deposit(accounts[i]);
        }
    }

    function _setupAmounts() internal {
        maker1Amount = _conformLots(_hem(_random(), 1e18, 3e18));
        maker2Amount = _conformLots(_hem(_random(), 1e18, 3e18));
        maker3Amount = _conformLots(_hem(_random(), 1e18, 3e18));

        takerAmount =
            _conformLots(_hem(_random(), maker1Amount / 2, (maker1Amount + maker2Amount + maker3Amount) + maker1Amount));
    }

    function _setupFundingPayment() internal {
        int256 funding = int256(_hem(_random(), 1000, 100_000));
        int256 altMarketFunding = int256(_hem(_random(), 1000, 100_000));

        if (_randomChance(2)) funding = -funding;
        if (_randomChance(2)) altMarketFunding = -altMarketFunding;

        // accumulate funding
        perpManager.mockSetCumulativeFunding(market, perpManager.getCumulativeFunding(market) + funding);

        perpManager.mockSetCumulativeFunding(
            alternateMarket, perpManager.getCumulativeFunding(alternateMarket) + altMarketFunding
        );
    }

    function _setAlternatePositions() internal {
        if (perpManager.getPosition(alternateMarket, accounts[0], 1).amount > 0) return;

        perpManager.mockSetMarkPrice(alternateMarket, 100_000e18);

        for (uint256 i = 1; i < accounts.length; i += 2) {
            _setAlternatePositionForAccount(accounts[i - 1], accounts[i]);
        }
    }

    function _setupLeverage() internal {
        _setupLeverageForAccount(taker);
        _setupLeverageForAccount(maker1);
        _setupLeverageForAccount(maker2);
        _setupLeverageForAccount(maker3);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                 UTILS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _setAlternatePositionForAccount(address t, address m) internal {
        Side side = _randomChance(2) ? Side.BUY : Side.SELL;

        PlaceOrderArgs memory makerArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: alternateMarket,
            side: side == Side.BUY ? Side.SELL : Side.BUY,
            limitPrice: 100_000e18,
            amount: 10e18,
            baseDenominated: true,
            tif: TiF.MOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        PlaceOrderArgs memory takerArgs = PlaceOrderArgs({
            subaccount: 1,
            asset: alternateMarket,
            side: side,
            limitPrice: 100_000e18,
            amount: 10e18,
            baseDenominated: true,
            tif: TiF.FOK,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: false
        });

        perpManager.placeOrder(m, makerArgs);
        totalBaseTraded[alternateMarket] += perpManager.placeOrder(t, takerArgs).baseTraded;
    }

    function _setupLeverageForAccount(address account) internal {
        if (hasSetLeverage[account]) return;

        uint256 leverage = _hem(_random(), 1, 3) * 1e18;

        perpManager.setPositionLeverage(market, account, 1, leverage);

        hasSetLeverage[account] = true;
    }

    function _getUniqueTrader(address[] memory exclude) internal returns (address trader) {
        trader = accounts[_hem(_random(), 0, accounts.length - 1)];

        for (uint256 i; i < exclude.length; i++) {
            if (trader == exclude[i]) return _getUniqueTrader(exclude);
        }
    }

    function _deposit(address account) internal {
        uint256 bal = TOKEN.balanceOf(account);

        if (bal == 0) return;

        perpManager.deposit(account, bal);
    }

    function _getPrice() internal returns (uint256 price) {
        uint256 mark = perpManager.getMarkPrice(market);
        uint256 tickSize = perpManager.getTickSize(market);

        uint256 min = mark > 50e18 ? mark - 50e18 : tickSize;
        uint256 max = (mark + 50e18).min(10_000e18);

        price = _hem(_random(), min, max);

        if (price % tickSize != 0) price -= price % tickSize;
    }

    function _conformLots(uint256 amount) internal view returns (uint256) {
        uint256 lotSize = perpManager.getLotSize(market);

        if (amount % lotSize == 0) return amount;
        if (amount < lotSize) return lotSize;

        return amount - (amount % lotSize);
    }
}
