// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "../PerpManagerTestBase.sol";

contract PerpQuoterTest is PerpManagerTestBase {
    using FixedPointMathLib for *;
    using SafeCastLib for uint256;

    // Order book structure: 2 sides x 2 price levels x 2 orders per level = 8 total orders
    uint256 internal constant MID_PRICE = 1e18; // Simple mid price for order book
    uint256 internal tickSize;
    uint256 internal lotSize;

    // Price levels around 1e18 mid price
    uint256 internal buyPrice1; // MID_PRICE - 1 tick (best bid)
    uint256 internal buyPrice2; // MID_PRICE - 2 ticks (second bid level)
    uint256 internal sellPrice1; // MID_PRICE + 1 tick (best ask)
    uint256 internal sellPrice2; // MID_PRICE + 2 ticks (second ask level)

    function setUp() public override {
        // Call parent setUp to initialize the test environment
        super.setUp();

        // Get market parameters (only need tick and lot size)
        tickSize = perpManager.getTickSize(ETH);
        lotSize = perpManager.getLotSize(ETH);

        // Calculate price levels around 1e18 mid price
        buyPrice1 = MID_PRICE - tickSize; // Best bid
        buyPrice2 = MID_PRICE - (2 * tickSize); // Second bid level
        sellPrice1 = MID_PRICE + tickSize; // Best ask
        sellPrice2 = MID_PRICE + (2 * tickSize); // Second ask level

        // Create order book with 2 orders at each price level
        _createQuoterOrderbook();
    }

    /// @dev Test to verify the order book setup is correct
    function test_OrderBookSetup() public view {
        // Verify price calculations are correct
        assertEq(buyPrice1, MID_PRICE - tickSize, "buyPrice1 should be MID_PRICE - 1 tick");
        assertEq(buyPrice2, MID_PRICE - (2 * tickSize), "buyPrice2 should be MID_PRICE - 2 ticks");
        assertEq(sellPrice1, MID_PRICE + tickSize, "sellPrice1 should be MID_PRICE + 1 tick");
        assertEq(sellPrice2, MID_PRICE + (2 * tickSize), "sellPrice2 should be MID_PRICE + 2 ticks");

        // Verify prices don't cross (no fills should occur)
        assertTrue(buyPrice1 < sellPrice1, "Buy orders should be below sell orders");
        assertTrue(buyPrice2 < buyPrice1, "buyPrice2 should be lower than buyPrice1");
        assertTrue(sellPrice1 < sellPrice2, "sellPrice1 should be lower than sellPrice2");
    }

    /// @dev Tests quoting to clear the two bid orders closest to mid price
    /// Should clear 2 ETH worth of bids at buyPrice1 (best bid level)
    /// Expected cost: 2 * buyPrice1 = 2 * (MID_PRICE - tickSize)
    function test_QuoteBookInBase_Bid_SingleLimit() public view {
        uint256 baseAmount = 2e18; // Want to sell 2 ETH (clear both orders at best bid)

        // Quote selling 2 ETH (Side.SELL means we're hitting bids)
        (uint256 quoteAmount, uint256 baseUsed) = perpManager.quoteBookInBase(ETH, baseAmount, Side.SELL);

        // Expected: 2 ETH * buyPrice1 (since buyPrice1 ≈ 1e18, this should be close to 2e18)
        uint256 expectedQuoteAmount = 2 * buyPrice1;

        assertEq(baseUsed, baseAmount, "Should use all 2 ETH");
        assertEq(quoteAmount, expectedQuoteAmount, "Quote amount should equal 2 * buyPrice1");
    }

    /// @dev Tests quoting to clear orders at the second bid level (buyPrice2)
    /// Should clear the first 2 ETH at buyPrice1, then 2 ETH at buyPrice2
    /// Expected cost: 2 * buyPrice1 + 2 * buyPrice2
    function test_QuoteBookInBase_Bid_MultipleLimits() public view {
        uint256 baseAmount = 4e18; // Want to sell 4 ETH (clear both price levels)

        // Quote selling 4 ETH (Side.SELL means we're hitting bids)
        (uint256 quoteAmount, uint256 baseUsed) = perpManager.quoteBookInBase(ETH, baseAmount, Side.SELL);

        // Expected: 2 ETH * buyPrice1 + 2 ETH * buyPrice2
        // Since buyPrice2 < buyPrice1, we get less total quote amount
        uint256 expectedQuoteAmount = 2 * buyPrice1 + 2 * buyPrice2;

        assertEq(baseUsed, baseAmount, "Should use all 4 ETH");
        assertEq(quoteAmount, expectedQuoteAmount, "Quote amount should equal 2*buyPrice1 + 2*buyPrice2");

        // Verify the price levels are different (buyPrice2 < buyPrice1)
        assertTrue(buyPrice2 < buyPrice1, "Second bid level should be cheaper than first");
        assertTrue(quoteAmount < 4 * buyPrice1, "Total should be less than if all at buyPrice1");
    }

    /// @dev Tests quoting to clear the two ask orders closest to mid price
    /// Should clear 2 ETH worth of asks at sellPrice1 (best ask level)
    /// Expected cost: 2 * sellPrice1 = 2 * (MID_PRICE + tickSize)
    function test_QuoteBookInBase_Ask_SingleLimit() public view {
        uint256 baseAmount = 2e18; // Want to buy 2 ETH (clear both orders at best ask)

        // Quote buying 2 ETH (Side.BUY means we're hitting asks)
        (uint256 quoteAmount, uint256 baseUsed) = perpManager.quoteBookInBase(ETH, baseAmount, Side.BUY);

        // Expected: 2 ETH * sellPrice1 (since sellPrice1 ≈ 1e18, this should be close to 2e18)
        uint256 expectedQuoteAmount = 2 * sellPrice1;

        assertEq(baseUsed, baseAmount, "Should use all 2 ETH");
        assertEq(quoteAmount, expectedQuoteAmount, "Quote amount should equal 2 * sellPrice1");
    }

    /// @dev Tests quoting to clear orders at multiple ask levels
    /// Should clear the first 2 ETH at sellPrice1, then 2 ETH at sellPrice2
    /// Expected cost: 2 * sellPrice1 + 2 * sellPrice2
    function test_QuoteBookInBase_Ask_MultipleLimits() public view {
        uint256 baseAmount = 4e18; // Want to buy 4 ETH (clear both price levels)

        // Quote buying 4 ETH (Side.BUY means we're hitting asks)
        (uint256 quoteAmount, uint256 baseUsed) = perpManager.quoteBookInBase(ETH, baseAmount, Side.BUY);

        // Expected: 2 ETH * sellPrice1 + 2 ETH * sellPrice2
        // Since sellPrice2 > sellPrice1, we pay more total quote amount
        uint256 expectedQuoteAmount = 2 * sellPrice1 + 2 * sellPrice2;

        assertEq(baseUsed, baseAmount, "Should use all 4 ETH");
        assertEq(quoteAmount, expectedQuoteAmount, "Quote amount should equal 2*sellPrice1 + 2*sellPrice2");

        // Verify the price levels are different (sellPrice2 > sellPrice1)
        assertTrue(sellPrice2 > sellPrice1, "Second ask level should be more expensive than first");
        assertTrue(quoteAmount > 4 * sellPrice1, "Total should be more than if all at sellPrice1");
    }

    /// @dev Tests quoting bids using quote amount (how much ETH can we sell for X quote tokens)
    /// Should sell ETH to the best bid orders for a target quote amount
    function test_QuoteBookInQuote_Bid_SingleLimit() public view {
        // Target: get exactly 2 * buyPrice1 quote tokens by selling ETH
        uint256 targetQuoteAmount = 2 * buyPrice1;

        // Quote how much ETH we need to sell to get this quote amount
        (uint256 baseAmount, uint256 quoteUsed) = perpManager.quoteBookInQuote(ETH, targetQuoteAmount, Side.SELL);

        // Should need exactly 2 ETH to get 2 * buyPrice1 quote tokens
        uint256 expectedBaseAmount = 2e18;

        assertEq(quoteUsed, targetQuoteAmount, "Should use all target quote amount");
        assertEq(baseAmount, expectedBaseAmount, "Should need exactly 2 ETH");
    }

    /// @dev Tests quoting bids across multiple limits using quote amount
    function test_QuoteBookInQuote_Bid_MultipleLimits() public view {
        // Target: get exactly the quote amount from clearing both bid levels
        uint256 targetQuoteAmount = 2 * buyPrice1 + 2 * buyPrice2;

        // Quote how much ETH we need to sell to get this quote amount
        (uint256 baseAmount, uint256 quoteUsed) = perpManager.quoteBookInQuote(ETH, targetQuoteAmount, Side.SELL);

        // Should need exactly 4 ETH to get the full quote amount
        uint256 expectedBaseAmount = 4e18;

        assertEq(quoteUsed, targetQuoteAmount, "Should use all target quote amount");
        assertEq(baseAmount, expectedBaseAmount, "Should need exactly 4 ETH");
    }

    /// @dev Tests quoting asks using quote amount (how much ETH can we buy for X quote tokens)
    /// Should buy ETH from the best ask orders for a target quote amount
    function test_QuoteBookInQuote_Ask_SingleLimit() public view {
        // Target: spend exactly 2 * sellPrice1 quote tokens to buy ETH
        uint256 targetQuoteAmount = 2 * sellPrice1;

        // Quote how much ETH we can buy with this quote amount
        (uint256 baseAmount, uint256 quoteUsed) = perpManager.quoteBookInQuote(ETH, targetQuoteAmount, Side.BUY);

        // Should get exactly 2 ETH for 2 * sellPrice1 quote tokens
        uint256 expectedBaseAmount = 2e18;

        assertEq(quoteUsed, targetQuoteAmount, "Should use all target quote amount");
        assertEq(baseAmount, expectedBaseAmount, "Should get exactly 2 ETH");
    }

    /// @dev Tests quoting asks across multiple limits using quote amount
    function test_QuoteBookInQuote_Ask_MultipleLimits() public view {
        // Target: spend exactly the quote amount to clear both ask levels
        uint256 targetQuoteAmount = 2 * sellPrice1 + 2 * sellPrice2;

        // Quote how much ETH we can buy with this quote amount
        (uint256 baseAmount, uint256 quoteUsed) = perpManager.quoteBookInQuote(ETH, targetQuoteAmount, Side.BUY);

        // Should get exactly 4 ETH for the full quote amount
        uint256 expectedBaseAmount = 4e18;

        assertEq(quoteUsed, targetQuoteAmount, "Should use all target quote amount");
        assertEq(baseAmount, expectedBaseAmount, "Should get exactly 4 ETH");
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                              SETUP HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @dev Creates the initial order book with 8 orders total:
    /// - 2 buy orders at buyPrice1 (MID_PRICE - 1 tick)
    /// - 2 buy orders at buyPrice2 (MID_PRICE - 2 ticks)
    /// - 2 sell orders at sellPrice1 (MID_PRICE + 1 tick)
    /// - 2 sell orders at sellPrice2 (MID_PRICE + 2 ticks)
    function _createQuoterOrderbook() internal {
        uint256 orderAmount = _conformToLots(1e18); // 1 ETH per order
        assertEq(orderAmount, 1e18, "Order amount should be exactly 1e18 (1 ETH)");

        // Create buy orders at first price level
        _createLimitOrder(ETH, rite, 1, buyPrice1, orderAmount, Side.BUY);
        _createLimitOrder(ETH, jb, 1, buyPrice1, orderAmount, Side.BUY);

        // Create buy orders at second price level
        _createLimitOrder(ETH, nate, 1, buyPrice2, orderAmount, Side.BUY);
        _createLimitOrder(ETH, julien, 1, buyPrice2, orderAmount, Side.BUY);

        // Create sell orders at first price level
        _createLimitOrder(ETH, moses, 1, sellPrice1, orderAmount, Side.SELL);
        _createLimitOrder(ETH, admin, 1, sellPrice1, orderAmount, Side.SELL);

        // Create sell orders at second price level (need additional users)
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        // Mint USDC and approve for the new users
        usdc.mint(user1, 100_000e18);
        usdc.mint(user2, 100_000e18);
        vm.prank(user1);
        usdc.approve(address(perpManager), type(uint256).max);
        vm.prank(user2);
        usdc.approve(address(perpManager), type(uint256).max);

        _createLimitOrder(ETH, user1, 1, sellPrice2, orderAmount, Side.SELL);
        _createLimitOrder(ETH, user2, 1, sellPrice2, orderAmount, Side.SELL);
    }

    /// @dev Conforms amount to lot size for ETH market
    function _conformToLots(uint256 amount) internal view returns (uint256) {
        return amount / lotSize * lotSize;
    }

    /// @dev Conforms price to tick size for ETH market
    function _conformToTicks(uint256 price) internal view returns (uint256) {
        if (price % tickSize == 0) return price;
        return price - (price % tickSize);
    }
}
