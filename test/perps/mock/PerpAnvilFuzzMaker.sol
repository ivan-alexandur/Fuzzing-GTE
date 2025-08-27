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

contract PerpAnvilFuzzMaker is Script, TestPlus {
    using SafeTransferLib for address;
    using FixedPointMathLib for uint256;

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                SETUP
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    constructor(address _perpManager, bytes32 _market, address[] memory _accounts) {
        perpManager = MockPerpManager(_perpManager);
        market = _market;
        accounts = _accounts;
    }

    function setAccounts(address[] memory _accounts) external {
        accounts = _accounts;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                STATE
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    address constant TOKEN = Constants.USDC;

    address[] public accounts;

    mapping(address maker => uint256[] orderIds) public makerOrders;

    uint256 public totalBasePosted;

    MockPerpManager perpManager;

    bytes32 market;

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               FUZZ MAKE
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function fuzzMake(uint256, uint256 orders) public {
        for (uint256 i; i < orders; i++) {
            address maker = _getRandomMaker();

            _deposit(maker);

            Side side = _randomChance(2) ? Side.BUY : Side.SELL;

            uint256 price = _getPrice(side);
            bool baseDenominated = _randomChance(10); // 9 in 10 orders are base denominated

            PlaceOrderArgs memory makerArgs = PlaceOrderArgs({
                subaccount: 1,
                asset: market,
                side: side,
                limitPrice: price,
                amount: _getAmount(price, baseDenominated),
                baseDenominated: baseDenominated,
                tif: TiF.MOC,
                expiryTime: 0,
                clientOrderId: 0,
                reduceOnly: false
            });

            PlaceOrderResult memory result = perpManager.placeOrder(maker, makerArgs);

            totalBasePosted += result.basePosted;
            makerOrders[maker].push(result.orderId);
        }
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function deleteOrders(address maker) public {
        uint256[] memory orders = makerOrders[maker];

        perpManager.cancelLimitOrders(market, maker, 1, orders);

        delete makerOrders[maker];
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                 UTILS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _getRandomMaker() internal returns (address maker) {
        maker = accounts[_hem(_random(), 0, accounts.length - 1)];
    }

    function _getAmount(uint256 price, bool baseDenominated) internal returns (uint256 amount) {
        if (baseDenominated) {
            amount = _hem(_random(), 0.5e18, 10e18);
        } else {
            amount = _hem(_random(), 50e18, 5000e18);

            if (_conformLots(amount.fullMulDiv(1e18, price)) < perpManager.getMinLimitOrderAmountInBase(market)) {
                amount = _getAmount(price, baseDenominated);
            }
        }
    }

    function _deposit(address account) internal {
        uint256 bal = TOKEN.balanceOf(account);

        if (bal == 0) return;

        perpManager.deposit(account, bal);
    }

    function _getPrice(Side side) internal returns (uint256 price) {
        uint256 mark = perpManager.getMarkPrice(market);
        uint256 tickSize = perpManager.getTickSize(market);

        uint256 max;
        uint256 min;
        if (side == Side.SELL) {
            max = mark + 100_000e18;
            min = mark + tickSize;
        } else {
            max = mark - tickSize;
            min = mark > (100_000e18 + tickSize) ? mark - 100_000e18 : tickSize;
        }

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
