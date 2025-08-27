// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ICLOB} from "../ICLOB.sol";

type OrderId is uint256;

using OrderIdLib for OrderId global;

library OrderIdLib {
    function getClientOrderId(address account, uint96 id) internal pure returns (uint256) {
        return uint256(bytes32(abi.encodePacked(account, id)));
    }

    function toOrderId(uint256 id) internal pure returns (OrderId) {
        return OrderId.wrap(id);
    }

    function unwrap(OrderId id) internal pure returns (uint256) {
        return uint256(OrderId.unwrap(id));
    }

    function isNull(OrderId id) internal pure returns (bool) {
        return id.unwrap() == NULL_ORDER_ID;
    }
}

uint256 constant NULL_ORDER_ID = 0;
uint32 constant NULL_TIMESTAMP = 0;

enum Side {
    BUY,
    SELL
}

struct Order {
    // SLOT 0 //
    Side side;
    uint32 cancelTimestamp;
    OrderId id;
    OrderId prevOrderId;
    OrderId nextOrderId;
    // SLOT 1 //
    address owner;
    // SLOT 2 //
    uint256 price;
    // SLOT 3 //
    uint256 amount; // denominated in base for limit & either token for fill
}

using OrderLib for Order global;

library OrderLib {
    using OrderIdLib for uint256;

    /// @dev sig: 0xd36d8965
    error OrderNotFound();
    /// @dev sig: 0x207d0854
    error MarketOrderCannotMake();
    /// @dev sig: 0x3228b943
    error TakerOrdersCannotExpire();
    /// @dev sig: 0x048fe9b3
    error MakerOrderExpired();
    /// @dev sig: 0x07928dcd
    error PostOnlyOrderMustBeBaseDenominated();

    /// @dev Generates and Order from place order args and verifies the args do not conflict with eachother
    function toOrderChecked(ICLOB.PlaceOrderArgs calldata args, uint256 orderId, address owner)
        internal
        view
        returns (Order memory order)
    {
        // Validate market order constraints
        if (args.limitPrice == 0 && uint8(args.tif) < 2) revert MarketOrderCannotMake();

        // Check expiry for GTC and MOC orders (TiF 0 and 1)
        if (uint8(args.tif) <= 1 && args.expiryTime > 0 && args.expiryTime < block.timestamp) {
            revert MakerOrderExpired();
        }

        if (args.expiryTime > 0 && uint8(args.tif) > 1) revert TakerOrdersCannotExpire();

        if (args.tif == ICLOB.TiF.MOC && !args.baseDenominated) revert PostOnlyOrderMustBeBaseDenominated();

        // Set order fields after validation
        if (args.limitPrice > 0) {
            // limit order
            order.price = args.limitPrice;
        } else {
            // market order, limitPrice = 0 | +inf
            order.price = args.side == Side.BUY ? type(uint256).max : 0;
        }

        order.id = orderId.toOrderId();
        order.side = args.side;
        order.owner = owner;
        order.amount = args.amount;
        order.cancelTimestamp = args.expiryTime;
    }

    /// @dev Checks whether an order is expired from an Order struct
    function isExpired(Order memory self) internal view returns (bool) {
        // slither-disable-next-line timestamp
        return self.cancelTimestamp != NULL_TIMESTAMP && self.cancelTimestamp < block.timestamp;
    }

    /// @dev Checks whether an order is expired from a timestamp
    function isExpired(uint256 cancelTimestamp) internal view returns (bool) {
        // slither-disable-next-line timestamp
        return cancelTimestamp != NULL_TIMESTAMP && cancelTimestamp < block.timestamp;
    }

    /// @dev Checks whether an order is null
    function isNull(Order storage self) internal view returns (bool) {
        return self.id.unwrap() == NULL_ORDER_ID;
    }

    /// @dev Asserts that an order exists
    function assertExists(Order storage self) internal view {
        if (self.isNull()) revert OrderNotFound();
    }
}
