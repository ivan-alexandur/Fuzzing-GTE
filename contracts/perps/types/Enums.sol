// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

enum Side {
    BUY,
    SELL
}

enum TiF {
    // MAKER
    GTC, // good-till-cancelled
    MOC, // maker-or-cancel (post-only)
    // TAKER
    FOK, // fill-or-kill
    IOC // immediate-or-cancel

}

enum Status {
    NULL,
    INACTIVE,
    ACTIVE,
    DELISTED
}

enum FeeTier {
    ZERO,
    ONE,
    TWO
}

enum BookType {
    STANDARD,
    BACKSTOP
}

enum TradeType {
    TAKER,
    MAKER,
    LIQUIDATOR,
    LIQUIDATEE,
    DELEVERAGE_MAKER,
    DELEVERAGE_TAKER,
    DELIST
}
