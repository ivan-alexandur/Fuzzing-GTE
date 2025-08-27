// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Launchpad} from "contracts/launchpad/Launchpad.sol";
import {ILaunchpad} from "contracts/launchpad/interfaces/ILaunchpad.sol";
import {SimpleBondingCurve} from "contracts/launchpad/BondingCurves/SimpleBondingCurve.sol";
import {IBondingCurveMinimal} from "contracts/launchpad/BondingCurves/IBondingCurveMinimal.sol";
import {LaunchToken} from "contracts/launchpad/LaunchToken.sol";
import {LaunchpadLPVault} from "contracts/launchpad/LaunchpadLPVault.sol";
import {IDistributor} from "contracts/launchpad/interfaces/IDistributor.sol";

import {ERC1967Factory} from "@solady/utils/ERC1967Factory.sol";

import {ERC20Harness} from "../harnesses/ERC20Harness.sol";

import {MockUniV2Router} from "../mocks/MockUniV2Router.sol";
import {MockDistributor} from "../mocks/MockDistributor.sol";

import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {ICLOBManager} from "contracts/clob/ICLOBManager.sol";
import {IOperatorPanel} from "contracts/utils/interfaces/IOperatorPanel.sol";

import {UniV2Bytecode} from "./integration/UniV2Bytecode.t.sol";

import "forge-std/Test.sol";

contract LaunchpadTest is Test {
    using FixedPointMathLib for uint256;

    ERC1967Factory factory;
    Launchpad launchpad;
    address distributor;
    IBondingCurveMinimal curve;
    LaunchpadLPVault launchpadLPVault;

    ERC20Harness quoteToken;
    MockUniV2Router uniV2Router;

    address owner = makeAddr("owner");
    address user = makeAddr("user");
    address dev = makeAddr("dev");

    uint256 constant MIN_BASE_AMOUNT = 100_000_000;

    address token;

    uint256 BONDING_SUPPLY;
    uint256 TOTAL_SUPPLY;

    function setUp() public {
        quoteToken = new ERC20Harness("Quote", "QTE");

        factory = new ERC1967Factory();

        address uniV2Factory = makeAddr("factory");
        vm.etch(uniV2Factory, UniV2Bytecode.UNIV2_FACTORY);

        uniV2Router = new MockUniV2Router(makeAddr("factory"));

        bytes32 launchpadSalt = bytes32(abi.encode("GTE.V1.TESTNET.LAUNCHPAD", owner));

        launchpad = Launchpad(factory.predictDeterministicAddress(launchpadSalt));

        address c_logic = address(new SimpleBondingCurve(address(launchpad)));
        address v_logic = address(new LaunchpadLPVault());

        curve = SimpleBondingCurve(factory.deploy(address(c_logic), owner));
        launchpadLPVault = LaunchpadLPVault(factory.deploy(address(v_logic), owner));

        address clobManager = makeAddr("clob manager");
        address operatorAddr = makeAddr("operator");
        vm.mockCall(
            operatorAddr,
            abi.encodeWithSelector(IOperatorPanel.getOperatorRoleApprovals.selector, user, address(0)),
            abi.encode(0)
        );

        distributor = address(new MockDistributor());
        vm.label(distributor, "MOCK_DISTRIBUTOR");

        address l_logic =
            address(new Launchpad(address(uniV2Router), address(0), clobManager, operatorAddr, distributor));

        vm.prank(owner);
        Launchpad(
            factory.deployDeterministicAndCall({
                implementation: l_logic,
                admin: owner,
                salt: launchpadSalt,
                data: abi.encodeCall(
                    Launchpad.initialize,
                    (
                        owner,
                        address(quoteToken),
                        address(curve),
                        address(launchpadLPVault),
                        abi.encode(200_000_000 ether, 10 ether)
                    )
                )
            })
        );

        token = _launchToken();

        BONDING_SUPPLY = curve.bondingSupply(token);
        TOTAL_SUPPLY = curve.totalSupply(token);

        vm.startPrank(user);
        quoteToken.approve(address(launchpad), type(uint256).max);
        ERC20Harness(token).approve(address(launchpad), type(uint256).max);
        vm.stopPrank();
    }

    function _launchToken() internal returns (address) {
        uint256 fee = launchpad.launchFee();
        deal(dev, 30 ether);

        vm.prank(dev);
        return launchpad.launch{value: fee}("TestToken", "TST", "https://testtoken.com");
    }

    function test_QuoterQuoteBuy(uint256 base) public {
        base = bound(base, MIN_BASE_AMOUNT, BONDING_SUPPLY - 1);

        uint256 quote = curve.quoteQuoteForBase(token, base, true);

        quoteToken.mint(user, quote);

        vm.prank(user);
        (uint256 baseActual, uint256 quoteActual) = launchpad.buy(
            ILaunchpad.BuyData({
                account: user,
                token: token,
                recipient: user,
                amountOutBase: base,
                maxAmountInQuote: quote
            })
        );

        assertEq(baseActual, base);
        assertEq(quoteActual, quote);

        assertEq(quoteToken.balanceOf(address(launchpad)), quote + launchpad.launchFee(), "launchpad quote incorrect");
        assertEq(quoteToken.balanceOf(user), 0, "user quote incorrect");
        assertEq(ERC20Harness(token).balanceOf(address(launchpad)), TOTAL_SUPPLY - base, "launchpad token incorrect");
        assertEq(ERC20Harness(token).balanceOf(user), base, "user token incorrect");
    }

    function test_QuoterQuoteSell(uint256 base) public {
        base = bound(base, MIN_BASE_AMOUNT, BONDING_SUPPLY - 1);

        uint256 quote = curve.quoteQuoteForBase(token, base, true);

        quoteToken.mint(user, quote);

        vm.startPrank(user);
        launchpad.buy(
            ILaunchpad.BuyData({
                account: user,
                token: token,
                recipient: user,
                amountOutBase: base,
                maxAmountInQuote: quote
            })
        );
        (uint256 baseActual, uint256 quoteActual) = launchpad.sell(user, token, user, base, quote);

        assertEq(baseActual, base, "base incorrect");
        assertEq(quoteActual, quote, "quoter incorrect");

        assertEq(quoteToken.balanceOf(address(launchpad)), launchpad.launchFee(), "launchpad quote incorrect");
        assertEq(quoteToken.balanceOf(user), quote, "user quote incorrect");
        assertEq(ERC20Harness(token).balanceOf(address(launchpad)), TOTAL_SUPPLY, "launchpad token incorrect");
        assertEq(ERC20Harness(token).balanceOf(user), 0, "user token incorrect");
    }

    function test_BuyRandomFromRandomPrice(uint256 end, uint256 base1) public {
        end = bound(end, MIN_BASE_AMOUNT + 100, BONDING_SUPPLY);

        uint256 quoteTotal = curve.quoteQuoteForBase(token, end, true);

        quoteToken.mint(user, quoteTotal);

        base1 = bound(base1, MIN_BASE_AMOUNT, end);
        uint256 base2 = end - base1;

        uint256 expectedQuote = curve.quoteQuoteForBase(token, base1, true);

        vm.startPrank(user);
        (uint256 baseActual, uint256 quote1) = launchpad.buy(
            ILaunchpad.BuyData({
                account: user,
                token: token,
                recipient: user,
                amountOutBase: base1,
                maxAmountInQuote: expectedQuote
            })
        );

        assertEq(baseActual, base1, "BUY1: UNEXPECTED BASE");
        assertEq(quote1, expectedQuote, "BUY1: UNEXPECTED QUOTE");

        uint256 quote2;
        if (base2 >= MIN_BASE_AMOUNT) {
            expectedQuote = curve.quoteQuoteForBase(token, base2, true);
            if (expectedQuote == 0 && base2 + base1 < BONDING_SUPPLY) {
                vm.expectRevert(Launchpad.DustAttackInvalid.selector);
            }
            (baseActual, quote2) = launchpad.buy(
                ILaunchpad.BuyData({
                    account: user,
                    token: token,
                    recipient: user,
                    amountOutBase: base2,
                    maxAmountInQuote: expectedQuote
                })
            );

            assertEq(baseActual, base2, "BUY2: UNEXPECTED BASE");
            assertEq(quote2, expectedQuote, "BUY2: UNEXPECTED QUOTE");
        }

        assertTrue(quoteTotal.dist(quote1 + quote2) < 30, "IMPRECISION TOO HIGH");
    }

    function test_GraduateFromRandomPrice(uint256 end, uint256 base1) public {
        end = BONDING_SUPPLY;

        uint256 quoteTotal = curve.quoteQuoteForBase(token, end, true);

        quoteToken.mint(user, quoteTotal);

        base1 = bound(base1, MIN_BASE_AMOUNT, end);
        uint256 base2 = end - base1;

        if (base2 < MIN_BASE_AMOUNT) base2 = 0;

        uint256 expectedQuote = curve.quoteQuoteForBase(token, base1, true);

        vm.startPrank(user);
        (uint256 baseActual, uint256 quote1) = launchpad.buy(
            ILaunchpad.BuyData({
                account: user,
                token: token,
                recipient: user,
                amountOutBase: base1,
                maxAmountInQuote: expectedQuote
            })
        );

        assertEq(baseActual, base1, "BUY1: UNEXPECTED BASE");
        assertEq(quote1, expectedQuote, "BUY1: UNEXPECTED QUOTE");

        uint256 quote2;
        if (base2 > 0) {
            expectedQuote = curve.quoteQuoteForBase(token, base2, true);
            (baseActual, quote2) = launchpad.buy(
                ILaunchpad.BuyData({
                    account: user,
                    token: token,
                    recipient: user,
                    amountOutBase: base2,
                    maxAmountInQuote: expectedQuote
                })
            );

            assertEq(baseActual, base2, "BUY2: UNEXPECTED BASE");
            assertEq(quote2, expectedQuote, "BUY2: UNEXPECTED QUOTE");
        }

        assertTrue(quoteTotal.dist(quote1 + quote2) < 30, "IMPRECISION TOO HIGH");
    }

    function test_BuySellSymmetry(uint256 amount) public {
        amount = bound(amount, MIN_BASE_AMOUNT, BONDING_SUPPLY - 1);

        uint256 quote = curve.quoteQuoteForBase(token, amount, true);

        quoteToken.mint(user, quote);

        vm.startPrank(user);
        launchpad.buy(
            ILaunchpad.BuyData({
                account: user,
                token: token,
                recipient: user,
                amountOutBase: amount,
                maxAmountInQuote: quote
            })
        );

        (uint256 baseActual, uint256 quoteActual) = launchpad.sell(user, token, user, amount, quote);

        assertEq(baseActual, amount, "base incorrect");
        assertEq(quoteActual, quote, "quote incorrect");
    }

    function test_SellRandomFromRandomPrice(uint256 start, uint256 base1) public {
        start = bound(start, MIN_BASE_AMOUNT + 100, BONDING_SUPPLY - 1);

        uint256 quoteTotal = curve.quoteQuoteForBase(token, start, true);

        quoteToken.mint(user, quoteTotal);

        vm.startPrank(user);

        launchpad.buy(
            ILaunchpad.BuyData({
                account: user,
                token: token,
                recipient: user,
                amountOutBase: start,
                maxAmountInQuote: quoteTotal
            })
        );

        base1 = bound(base1, MIN_BASE_AMOUNT, start);
        uint256 base2 = start - base1;

        if (base2 < MIN_BASE_AMOUNT) base2 = 0;

        uint256 expectedQuote = curve.quoteQuoteForBase(token, base1, false);
        (uint256 baseActual, uint256 quote1) = launchpad.sell(user, token, user, base1, expectedQuote);

        assertEq(baseActual, base1, "SELL1: UNEXPECTED BASE");
        assertEq(quote1, expectedQuote, "SELL1: UNEXPECTED QUOTE");

        uint256 quote2;
        if (base2 > 0) {
            expectedQuote = curve.quoteQuoteForBase(token, base2, false);
            (baseActual, quote2) = launchpad.sell(user, token, user, base2, expectedQuote);

            assertEq(baseActual, base2, "SELL2: UNEXPECTED BASE");
            assertEq(quote2, expectedQuote, "SELL2: UNEXPECTED QUOTE");
        }

        assertTrue(quoteTotal.dist(quote1 + quote2) < 30, "IMPRECISION TOO HIGH");
    }

    function test_DustAttack_ExpectRevert() public {
        quoteToken.mint(user, 40 ether);

        vm.startPrank(user);
        uint256 quoteAmount = curve.quoteQuoteForBase(token, 1 ether, true);
        launchpad.buy(
            ILaunchpad.BuyData({
                account: user,
                token: token,
                recipient: user,
                amountOutBase: 1 ether,
                maxAmountInQuote: type(uint256).max
            })
        );

        quoteAmount = curve.quoteQuoteForBase(token, 1_000_000, true);

        assertEq(quoteAmount, 0, "base amount does not cause dust attack");

        vm.expectRevert(abi.encodeWithSelector(Launchpad.DustAttackInvalid.selector));
        launchpad.buy(
            ILaunchpad.BuyData({
                account: user,
                token: token,
                recipient: user,
                amountOutBase: 1_000_000,
                maxAmountInQuote: type(uint256).max
            })
        );

        vm.expectRevert(abi.encodeWithSelector(Launchpad.DustAttackInvalid.selector));
        launchpad.sell(user, token, user, 1_000_000, 0);
    }

    function test_MaxCost() public view {
        assertEq(40e18, curve.quoteQuoteForBase(token, BONDING_SUPPLY, true));
    }

    function test_PostGraduate_Swap() public {
        uint256 bondedBase = curve.bondingSupply(token);
        uint256 bondedQuote = curve.quoteQuoteForBase(token, bondedBase, true);

        uint256 baseLiquidity = curve.totalSupply(token) - bondedBase;

        uint256 ammBase = 80 ether;
        uint256 ammQuote = uniV2Router.getAmountIn(ammBase, bondedQuote, baseLiquidity);

        quoteToken.mint(user, bondedQuote + ammQuote + 50 ether);

        vm.prank(user);
        (uint256 baseActual, uint256 quoteActual) = launchpad.buy(
            ILaunchpad.BuyData({
                account: user,
                token: token,
                recipient: user,
                amountOutBase: bondedBase + ammBase,
                maxAmountInQuote: bondedQuote + ammQuote + 50 ether
            })
        ); // + random amount

        assertEq(baseActual, bondedBase + ammBase, "base incorrect");
        assertEq(quoteActual, bondedQuote + ammQuote, "quote incorrect");
    }

    function test_relaunch() public {
        uint256 launchFee = launchpad.launchFee();
        deal(address(this), 2 * launchFee);

        address _token = launchpad.launch{value: launchFee}("test", "symb", "uri");
        address _token2 = launchpad.launch{value: launchFee}("test", "symb", "uri");
        assertTrue(_token2 != _token, "equivalent addresses deployed");

        uint256 totalSupply = LaunchToken(_token).totalSupply();
        assertEq(totalSupply, curve.totalSupply(token), "total supply invalid");
    }

    function test_RoundingOnBuy() public {
        uint256 requiredUSDC = 1e30;
        deal(address(quoteToken), address(this), requiredUSDC);
        quoteToken.approve(address(launchpad), type(uint256).max);

        // Buy a minimal amount (1e18) and verify that nonzero USDC is spent.
        (uint256 tokensBought, uint256 usdcSpent) = launchpad.buy(
            ILaunchpad.BuyData({
                account: address(this),
                token: token,
                recipient: address(this),
                amountOutBase: 1e18,
                maxAmountInQuote: requiredUSDC
            })
        );

        assertFalse(tokensBought > 0 && usdcSpent == 0, "free tokens purchased");

        // Buy a minimal amount (1e18) and verify that nonzero USDC is spent.

        vm.expectRevert(Launchpad.DustAttackInvalid.selector);
        (tokensBought, usdcSpent) = launchpad.buy(
            ILaunchpad.BuyData({
                account: address(this),
                token: token,
                recipient: address(this),
                amountOutBase: 1,
                maxAmountInQuote: requiredUSDC
            })
        );
    } // Still need to test rounding from 2 -> 1 which could leak value at some specified rate.

    function test_RoundingOnDoubleBuy() public {
        uint256 buyAmount = curve.bondingSupply(token) - 2;
        uint256 requiredUSDC = curve.quoteQuoteForBase(token, buyAmount, true);
        deal(address(quoteToken), address(this), type(uint256).max);
        quoteToken.approve(address(launchpad), type(uint256).max);

        // First buy: attempt to purchase almost all bonding supply.
        launchpad.buy(
            ILaunchpad.BuyData({
                account: address(this),
                token: token,
                recipient: address(this),
                amountOutBase: buyAmount,
                maxAmountInQuote: requiredUSDC
            })
        );

        // Then buy a minimal extra amount.
        vm.expectRevert(Launchpad.DustAttackInvalid.selector);
        launchpad.buy(
            ILaunchpad.BuyData({
                account: address(this),
                token: token,
                recipient: address(this),
                amountOutBase: 1,
                maxAmountInQuote: requiredUSDC
            })
        );
    }

    function test_RoundingOnSell() public {
        uint256 buyAmount = curve.bondingSupply(token) - 1;
        uint256 tokensToSell = 1e18;
        uint256 requiredUSDC = curve.quoteQuoteForBase(token, buyAmount, true);
        deal(address(quoteToken), address(this), type(uint256).max);
        quoteToken.approve(address(launchpad), type(uint256).max);

        launchpad.buy(
            ILaunchpad.BuyData({
                account: address(this),
                token: token,
                recipient: address(this),
                amountOutBase: buyAmount,
                maxAmountInQuote: requiredUSDC
            })
        );
        ERC20Harness(token).approve(address(launchpad), tokensToSell);

        (uint256 tokensSold, uint256 usdcReturned) =
            launchpad.sell(address(this), token, address(this), tokensToSell, 1);
        assertFalse(usdcReturned > 0 && tokensSold == 0, "free tokens purchased");
    }

    function test_Fuzz_BuySellSymmetry(uint256 buyAmount) public {
        // Bound inputs to avoid graduation and extreme values.
        uint256 bondingSupply = curve.bondingSupply(token);
        uint256 boundedBuyAmount = bound(buyAmount, 1e18 - 1, bondingSupply - 1);

        uint256 requiredUSDC = curve.quoteQuoteForBase(token, boundedBuyAmount, true);
        deal(address(quoteToken), address(this), requiredUSDC * 2);
        quoteToken.approve(address(launchpad), type(uint256).max);

        uint256 tokensBought;
        uint256 usdcSpent;
        {
            (tokensBought, usdcSpent) = launchpad.buy(
                ILaunchpad.BuyData({
                    account: address(this),
                    token: token,
                    recipient: address(this),
                    amountOutBase: boundedBuyAmount,
                    maxAmountInQuote: requiredUSDC * 2
                })
            );
            ERC20Harness(token).approve(address(launchpad), tokensBought);
        }
        (uint256 tokensSold, uint256 usdcReturned) =
            launchpad.sell(address(this), token, address(this), tokensBought, usdcSpent);

        assertEq(usdcReturned, usdcSpent, "USDC symmetry mismatch");
        assertEq(tokensSold, tokensBought, "Token symmetry mismatch");
    }

    function test_BuyAfterGraduation_Revert() public {
        uint256 requiredUSDC = curve.quoteQuoteForBase(token, curve.bondingSupply(token), true);
        // Fund this caller with sufficient quote tokens.
        deal(address(quoteToken), address(this), requiredUSDC);
        quoteToken.approve(address(launchpad), type(uint256).max);
        // Buy the full bonding supply to graduate the bonding phase.
        launchpad.buy(
            ILaunchpad.BuyData({
                account: address(this),
                token: token,
                recipient: address(this),
                amountOutBase: curve.bondingSupply(token),
                maxAmountInQuote: requiredUSDC
            })
        );
        // Now any further buy should revert with BondingInactive.
        vm.expectRevert(abi.encodeWithSelector(Launchpad.BondingInactive.selector));
        launchpad.buy(
            ILaunchpad.BuyData({
                account: address(this),
                token: token,
                recipient: address(this),
                amountOutBase: 1e18,
                maxAmountInQuote: type(uint256).max
            })
        );
    }

    /// @notice Test that sequential buys (first part1 then part2) yield a cumulative quote
    /// that is nearly equal to the quote computed initially for the total amount.
    function test_SequentialBuyInvariance(uint256 part1, uint256 part2) public {
        // Bound inputs so each part is at least 1e18 and their sum does not exceed half the bonding supply.
        uint256 bondingSupply = curve.bondingSupply(token);
        uint256 part1Bounded = bound(part1, 1e18, bondingSupply / 2);
        uint256 part2Bounded = bound(part2, 1e18, bondingSupply / 2);
        uint256 totalAmount = part1Bounded + part2Bounded;

        // From the untouched bonding curve state, get the total quote for buying totalAmount tokens.
        uint256 quoteTotalInitial = curve.quoteQuoteForBase(token, totalAmount, true);

        // Fund the buyer (user) with ample quote tokens.
        uint256 funding = quoteTotalInitial * 2; // extra margin to avoid supply issues
        deal(address(quoteToken), user, funding);
        vm.prank(user);
        quoteToken.approve(address(launchpad), type(uint256).max);

        vm.prank(user);
        (uint256 tokensBought1, uint256 usdcSpent1) = launchpad.buy(
            ILaunchpad.BuyData({
                account: user,
                token: token,
                recipient: user,
                amountOutBase: part1Bounded,
                maxAmountInQuote: type(uint256).max
            })
        );

        vm.prank(user);
        (uint256 tokensBought2, uint256 usdcSpent2) = launchpad.buy(
            ILaunchpad.BuyData({
                account: user,
                token: token,
                recipient: user,
                amountOutBase: part2Bounded,
                maxAmountInQuote: type(uint256).max
            })
        );

        uint256 cumulativeQuoteActual = usdcSpent1 + usdcSpent2;

        console.log("Expected total quote (initial state):", quoteTotalInitial);
        console.log("Actual cumulative quote from sequential buys:", cumulativeQuoteActual);

        // Allow for rounding tolerances (here, a tolerance of 30000 units is acceptable).
        assertTrue(cumulativeQuoteActual.dist(quoteTotalInitial) < 30, "Sequential buy invariant failed");
    }

    function test_GraduationDenialByQuoteRounding() public {
        uint256 bondingSupply = curve.bondingSupply(token);
        // For this test we want the computed quote amount to be 0 for a minimal buy.
        // In the bonding curve, the quoteAmount is computed as:
        //   (quoteReserve * baseAmount) / (baseReserve - baseAmount)
        // From our initialization the base reserve is:
        //   baseReserve = BONDING_SUPPLY + VIRTUAL_BASE.
        // If we set the virtual quote very low (e.g. 1 wei), then for a buy of 1e18 tokens:
        //   quoteAmount = (1 * 1e18) / ((BONDING_SUPPLY + VIRTUAL_BASE) - 1e18)
        // For realistic parameters (BONDING_SUPPLY is huge), the division will return 0.

        // Set the virtual quote to 1 (wei) while keeping the current virtual base.
        // We assume launchpad exposes a function to update virtual reserves.
        uint256 currentVirtualBase = 200_000_000 ether; // as per initialization
        uint256 newVirtualQuote = 20_000_000 ether; // extremely low value

        uint256 launchFee = launchpad.launchFee();
        deal(address(this), 2 * launchFee);

        vm.prank(owner);
        SimpleBondingCurve(address(curve)).setVirtualReserves(currentVirtualBase, newVirtualQuote);

        address _token = launchpad.launch{value: launchFee}("test", "symb", "uri");

        deal(address(quoteToken), user, type(uint256).max);

        vm.startPrank(user);
        quoteToken.approve(address(launchpad), type(uint256).max);

        // Leave just enough such that the last buy to graduate would be free
        launchpad.buy(
            ILaunchpad.BuyData({
                account: user,
                token: _token,
                recipient: user,
                amountOutBase: bondingSupply - 2,
                maxAmountInQuote: type(uint256).max
            })
        );

        // Dust buy does not graduate, expect revert
        vm.expectRevert(abi.encodeWithSelector(Launchpad.DustAttackInvalid.selector));
        launchpad.buy(
            ILaunchpad.BuyData({
                account: user,
                token: _token,
                recipient: user,
                amountOutBase: 1,
                maxAmountInQuote: type(uint256).max
            })
        );

        // This would be free, but it graduates the curve so give it away
        launchpad.buy(
            ILaunchpad.BuyData({
                account: user,
                token: _token,
                recipient: user,
                amountOutBase: 2,
                maxAmountInQuote: type(uint256).max
            })
        );
    }
}
// function setVirtualReserves(uint256 virtualBase, uint256 virtualQuote) external onlyOwner {
//     bondingCurve.setVirtualReserves(virtualBase, virtualQuote);
// }
