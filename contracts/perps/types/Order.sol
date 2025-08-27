// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {PlaceOrderArgs, AmendLimitOrderArgs} from "./Structs.sol";
import {Side} from "./Enums.sol";

type OrderId is uint256;

using OrderIdLib for OrderId global;

library OrderIdLib {
    error UintExceedsOrderIdSize();

    function getOrderId(address account, uint96 id) internal pure returns (uint256) {
        return uint256(bytes32(abi.encodePacked(account, id)));
    }

    // @todo rename to toOrderId
    function wrap(uint256 id) internal pure returns (OrderId) {
        return OrderId.wrap(id);
    }

    function unwrap(OrderId id) internal pure returns (uint256) {
        return OrderId.unwrap(id);
    }
}

uint256 constant NULL_ORDER_ID = 0;
uint32 constant NULL_TIMESTAMP = 0;

struct Order {
    // SLOT 0 //
    Side side;
    uint32 expiryTime;
    OrderId id;
    OrderId prevOrderId;
    OrderId nextOrderId;
    // SLOT 1 //
    address owner;
    // SLOT 2 //
    uint256 price;
    // SLOT 3 //
    uint256 amount;
    // SLOT 4 //
    uint256 subaccount;
    // SLOT 5 //
    bool reduceOnly;
}

using OrderLib for Order global;

library OrderLib {
    using OrderIdLib for uint256;

    error OrderNotFound();

    function toOrder(PlaceOrderArgs memory args, uint256 orderId, address owner)
        internal
        pure
        returns (Order memory order)
    {
        order.side = args.side;
        order.expiryTime = args.expiryTime;
        order.id = orderId.wrap();
        order.owner = owner;
        order.amount = args.amount;
        order.price = args.limitPrice;
        order.subaccount = args.subaccount;
        order.reduceOnly = args.reduceOnly;

        // zero price == max slippage
        if (order.price == 0 && order.side == Side.BUY) order.price = type(uint256).max; // set to max for buy orders
    }

    function toOrder(AmendLimitOrderArgs calldata args, Order storage currentOrder)
        internal
        view
        returns (Order memory newOrder)
    {
        newOrder.owner = currentOrder.owner;
        newOrder.id = currentOrder.id;
        newOrder.side = args.side;
        newOrder.price = args.price;
        newOrder.amount = args.baseAmount;
        newOrder.reduceOnly = args.reduceOnly;
        newOrder.subaccount = currentOrder.subaccount;
        newOrder.expiryTime = args.expiryTime;
    }

    function isExpired(Order memory self) internal view returns (bool) {
        // slither-disable-next-line timestamp
        return self.expiryTime != NULL_TIMESTAMP && self.expiryTime < block.timestamp;
    }

    function isExpired(uint256 expiryTime) internal view returns (bool) {
        // slither-disable-next-line timestamp
        return expiryTime != NULL_TIMESTAMP && expiryTime < block.timestamp;
    }

    // @todo this reads the whole order into memory
    function isNull(Order memory self) internal pure returns (bool) {
        return self.id.unwrap() == NULL_ORDER_ID;
    }

    // @todo this reads the whole order into memory
    function assertExists(Order memory self) internal pure {
        if (self.isNull()) revert OrderNotFound();
    }
}
