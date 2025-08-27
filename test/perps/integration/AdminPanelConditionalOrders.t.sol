// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {PerpManagerTestBase} from "../PerpManagerTestBase.sol";
import {SignData, PlaceOrderArgs, Side, Condition} from "contracts/perps/types/Structs.sol";
import {AdminPanel} from "contracts/perps/modules/AdminPanel.sol";
import {MockAdminPanel} from "../mock/MockAdminPanel.t.sol";
import {MarketParams} from "contracts/perps/types/Structs.sol";

import {Ownable} from "@solady/auth/Ownable.sol";
import {OwnableRoles} from "@solady/auth/OwnableRoles.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import "contracts/perps/types/Enums.sol";

contract AdminPanelConditionalOrdersTest is PerpManagerTestBase {
    using FixedPointMathLib for *;

    MockAdminPanel internal adminPanel;

    function setUp() public virtual override {
        super.setUp();

        address adminPanelLogic = address(new MockAdminPanel());

        adminPanel = MockAdminPanel(
            factory.deployAndCall({
                admin: admin,
                implementation: adminPanelLogic,
                data: abi.encodeCall(AdminPanel.initialize, (admin, takerFees, makerFees))
            })
        );

        vm.prank(admin);
        adminPanel.activateProtocol();
    }

    function test_Perp_Conditional_PlaceTwapOrder_Success(uint256) public {
        _createMarketAdminPanel(admin, ETH, _createMarketParams(4000e18, true));
        vm.prank(admin);
        adminPanel.activateMarket(ETH);

        uint32 expiry = uint32(block.timestamp + _hem(_random(), 0, 31 days));
        uint256 userNonce = 0;

        (address signer, uint256 signerPrivateKey) = _randomUniqueSigner();
        PlaceOrderArgs memory args = _generateLimitOrderArgs(ETH, expiry, false);

        _mintAndDeposit(signer, args.amount * args.limitPrice);

        SignData memory signData = SignData({
            sig: _generateSignature(args, signerPrivateKey, expiry, userNonce),
            nonce: userNonce,
            expiry: expiry
        });

        vm.prank(admin);
        adminPanel.placeTwapOrder(signer, args, signData);
    }

    function test_Perp_Conditional_PlaceTwapOrder_Fail_Unauthorized(uint256) public {
        _createMarketAdminPanel(admin, ETH, _createMarketParams(4000e18, true));
        vm.prank(admin);
        adminPanel.activateMarket(ETH);

        uint32 expiry = uint32(block.timestamp + _hem(_random(), 0, 31 days));
        uint256 userNonce = 0;

        (address signer, uint256 signerPrivateKey) = _randomUniqueSigner();
        PlaceOrderArgs memory args = _generateLimitOrderArgs(ETH, expiry, false);

        _mintAndDeposit(signer, args.amount * args.limitPrice);

        SignData memory signData = SignData({
            sig: _generateSignature(args, signerPrivateKey, expiry, userNonce),
            nonce: userNonce,
            expiry: expiry
        });

        vm.prank(signer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        adminPanel.placeTwapOrder(signer, args, signData);
    }

    function test_Perp_Conditional_PlaceTwapOrder_Fail_InvalidNonce(uint256) public {
        _createMarketAdminPanel(admin, ETH, _createMarketParams(4000e18, true));
        vm.prank(admin);
        adminPanel.activateMarket(ETH);

        uint32 expiry = uint32(block.timestamp + _hem(_random(), 0, 31 days));
        uint256 userNonce = 0;

        (address signer, uint256 signerPrivateKey) = _randomUniqueSigner();
        PlaceOrderArgs memory args = _generateLimitOrderArgs(ETH, expiry, false);

        _mintAndDeposit(signer, args.amount * args.limitPrice);

        SignData memory signData = SignData({
            sig: _generateSignature(args, signerPrivateKey, expiry, userNonce),
            nonce: userNonce,
            expiry: expiry
        });

        vm.prank(admin);
        adminPanel.placeTwapOrder(signer, args, signData);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(AdminPanel.InvalidNonce.selector));
        adminPanel.placeTwapOrder(signer, args, signData);
    }

    function test_Perp_Conditional_PlaceTwapOrder_Fail_InvalidSignature(uint256) public {
        _createMarketAdminPanel(admin, ETH, _createMarketParams(4000e18, true));
        vm.prank(admin);
        adminPanel.activateMarket(ETH);

        uint32 expiry = uint32(block.timestamp + _hem(_random(), 0, 31 days));
        uint256 userNonce = 0;

        (address signer,) = _randomUniqueSigner();
        PlaceOrderArgs memory args = _generateLimitOrderArgs(ETH, expiry, false);

        _mintAndDeposit(signer, args.amount * args.limitPrice);

        SignData memory signData = SignData({sig: abi.encode(""), nonce: userNonce, expiry: expiry});

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(AdminPanel.InvalidSignature.selector));
        adminPanel.placeTwapOrder(signer, args, signData);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                        CONDITIONAL ORDER TESTS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function test_Perp_PlaceTPSLOrder_Success(uint256) public {
        _createMarketAdminPanel(admin, ETH, _createMarketParams(4000e18, true));
        vm.prank(admin);
        adminPanel.activateMarket(ETH);

        uint32 expiry = uint32(block.timestamp + _hem(_random(), 0, 31 days));
        uint256 userNonce = 0;

        (address signer, uint256 signerPrivateKey) = _randomUniqueSigner();
        PlaceOrderArgs memory args = _generatePostFillCloseOrderArgs(ETH);

        uint256 markPrice = args.limitPrice;

        Condition memory condition = Condition({triggerPrice: markPrice, stopLoss: _random() % 2 == 0 ? true : false});

        vm.prank(admin);
        adminPanel.mockSetMarkPrice(ETH, markPrice);

        SignData memory signData = SignData({
            sig: _generateSignature(args, condition, signerPrivateKey, expiry, userNonce),
            nonce: userNonce,
            expiry: expiry
        });

        _mintApprove(signer, type(uint128).max);
        _mintApprove(julien, type(uint128).max);

        _mockPlaceTrade({
            asset: ETH,
            taker: signer,
            maker: julien,
            price: args.limitPrice,
            amount: args.amount,
            side: args.side == Side.BUY ? Side.SELL : Side.BUY,
            subaccount: 0
        });

        _mockCreateLimitOrder({
            asset: ETH,
            maker: julien,
            subaccount: 0,
            price: args.limitPrice,
            amount: args.amount,
            side: args.side == Side.BUY ? Side.SELL : Side.BUY
        });

        _mintAndDeposit(signer, args.amount * args.limitPrice);

        _setMarkPriceConditional(ETH, condition.triggerPrice, condition.stopLoss, args.side == Side.BUY);

        vm.prank(admin);
        adminPanel.placeTPSLOrder(signer, args, condition, signData);
    }

    function test_Perp_PlaceTPSLOrder_Fail_Unauthorized(uint256) public {
        _createMarketAdminPanel(admin, ETH, _createMarketParams(4000e18, true));
        vm.prank(admin);
        adminPanel.activateMarket(ETH);

        uint32 expiry = uint32(block.timestamp + _hem(_random(), 0, 31 days));
        uint256 userNonce = 0;

        (address signer, uint256 signerPrivateKey) = _randomUniqueSigner();
        PlaceOrderArgs memory args = _generatePostFillCloseOrderArgs(ETH);

        Condition memory condition = Condition({triggerPrice: args.limitPrice, stopLoss: false});

        SignData memory signData = SignData({
            sig: _generateSignature(args, condition, signerPrivateKey, expiry, userNonce),
            nonce: userNonce,
            expiry: expiry
        });

        vm.prank(signer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        adminPanel.placeTPSLOrder(signer, args, condition, signData);
    }

    function test_Perp_PlaceTPSLOrder_Fail_InvalidNonce(uint256) public {
        _createMarketAdminPanel(admin, ETH, _createMarketParams(4000e18, true));
        vm.prank(admin);
        adminPanel.activateMarket(ETH);

        uint32 expiry = uint32(block.timestamp + _hem(_random(), 0, 31 days));
        uint256 userNonce = 0;

        (address signer, uint256 signerPrivateKey) = _randomUniqueSigner();
        PlaceOrderArgs memory args = _generatePostFillCloseOrderArgs(ETH);

        uint256 markPrice = args.limitPrice;
        vm.prank(admin);
        adminPanel.mockSetMarkPrice(ETH, markPrice);

        Condition memory condition = Condition({triggerPrice: markPrice, stopLoss: false});

        SignData memory signData = SignData({
            sig: _generateSignature(args, condition, signerPrivateKey, expiry, userNonce),
            nonce: userNonce,
            expiry: expiry
        });

        _mintApprove(signer, type(uint128).max);
        _mintApprove(julien, type(uint128).max);

        _mockPlaceTrade({
            asset: ETH,
            taker: signer,
            maker: julien,
            price: args.limitPrice,
            amount: args.amount,
            side: args.side == Side.BUY ? Side.SELL : Side.BUY,
            subaccount: 0
        });

        _mockCreateLimitOrder({
            asset: ETH,
            maker: julien,
            subaccount: 0,
            price: args.limitPrice,
            amount: args.amount,
            side: args.side == Side.BUY ? Side.SELL : Side.BUY
        });

        _mintAndDeposit(signer, args.amount * args.limitPrice);

        vm.prank(admin);
        _setMarkPriceConditional(ETH, condition.triggerPrice, condition.stopLoss, args.side == Side.BUY);

        vm.prank(admin);
        adminPanel.placeTPSLOrder(signer, args, condition, signData);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(AdminPanel.InvalidNonce.selector));
        adminPanel.placeTPSLOrder(signer, args, condition, signData);
    }

    function test_Perp_PlaceTPSLOrder_Fail_InvalidSignature(uint256) public {
        _createMarketAdminPanel(admin, ETH, _createMarketParams(4000e18, true));
        vm.prank(admin);
        adminPanel.activateMarket(ETH);

        uint32 expiry = uint32(block.timestamp + _hem(_random(), 0, 31 days));
        uint256 userNonce = 0;

        (address signer,) = _randomUniqueSigner();
        PlaceOrderArgs memory args = _generatePostFillCloseOrderArgs(ETH);

        Condition memory condition = Condition({triggerPrice: args.limitPrice, stopLoss: false});

        SignData memory signData = SignData({sig: abi.encode(""), nonce: userNonce, expiry: expiry});

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(AdminPanel.InvalidSignature.selector));
        adminPanel.placeTPSLOrder(signer, args, condition, signData);
    }

    function test_Perp_PlaceTPSLOrder_Fail_ConditionNotMet(uint256) public {
        _createMarketAdminPanel(admin, ETH, _createMarketParams(4000e18, true));
        vm.prank(admin);
        adminPanel.activateMarket(ETH);

        uint32 expiry = uint32(block.timestamp + _hem(_random(), 0, 31 days));
        uint256 userNonce = 0;

        (address signer, uint256 signerPrivateKey) = _randomUniqueSigner();
        PlaceOrderArgs memory args = _generatePostFillCloseOrderArgs(ETH);

        uint256 markPrice = args.limitPrice;
        vm.prank(admin);
        adminPanel.mockSetMarkPrice(ETH, markPrice);

        Condition memory condition = Condition({triggerPrice: markPrice, stopLoss: false});

        SignData memory signData = SignData({
            sig: _generateSignature(args, condition, signerPrivateKey, expiry, userNonce),
            nonce: userNonce,
            expiry: expiry
        });

        _mintApprove(signer, type(uint128).max);
        _mintApprove(julien, type(uint128).max);

        _mockPlaceTrade({
            asset: ETH,
            taker: signer,
            maker: julien,
            price: args.limitPrice,
            amount: args.amount,
            side: args.side == Side.BUY ? Side.SELL : Side.BUY,
            subaccount: 0
        });

        _mockCreateLimitOrder({
            asset: ETH,
            maker: julien,
            subaccount: 0,
            price: args.limitPrice,
            amount: args.amount,
            side: args.side == Side.BUY ? Side.SELL : Side.BUY
        });

        _mintAndDeposit(signer, args.amount * args.limitPrice);

        vm.prank(admin);
        _setMarkPriceConditionalNotMet(ETH, condition.triggerPrice, condition.stopLoss, args.side == Side.BUY);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(AdminPanel.ConditionNotMet.selector));
        adminPanel.placeTPSLOrder(signer, args, condition, signData);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                          INTERNAL HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _mintAndDeposit(address account, uint256 amount) internal {
        usdc.mint(account, amount);

        vm.startPrank(account);
        usdc.approve(address(adminPanel), amount);
        adminPanel.deposit(account, amount);
        vm.stopPrank();
    }

    function _mintApprove(address account, uint256 amount) internal {
        usdc.mint(account, amount);

        vm.startPrank(account);
        usdc.approve(address(adminPanel), amount);
        vm.stopPrank();
    }

    function _generateLimitOrderArgs(bytes32 asset, uint32 expiry, bool reduceOnly)
        internal
        returns (PlaceOrderArgs memory)
    {
        return PlaceOrderArgs({
            subaccount: 0,
            asset: asset,
            side: _random() % 2 == 0 ? Side.BUY : Side.SELL,
            limitPrice: _conformTick(asset, _hem(_random(), 1e18, 10_000e18)),
            amount: _conformLots(asset, _hem(_random(), 0.001 ether, 10 ether)),
            baseDenominated: true,
            tif: TiF.GTC,
            expiryTime: expiry,
            clientOrderId: 0,
            reduceOnly: reduceOnly
        });
    }

    function _generatePostFillCloseOrderArgs(bytes32 asset) internal returns (PlaceOrderArgs memory) {
        return PlaceOrderArgs({
            subaccount: 0,
            asset: ETH,
            side: _random() % 2 == 0 ? Side.BUY : Side.SELL,
            limitPrice: _conformTick(asset, _hem(_random(), 1e18, 10_000e18)),
            amount: _conformLots(asset, _hem(_random(), 0.001 ether, 10 ether)),
            baseDenominated: true,
            tif: TiF.IOC,
            expiryTime: 0,
            clientOrderId: 0,
            reduceOnly: true
        });
    }

    function _mockPlaceTrade(
        bytes32 asset,
        address taker,
        address maker,
        uint256 price,
        uint256 amount,
        Side side,
        uint256 subaccount
    ) internal {
        _mockCreateLimitOrder({
            asset: asset,
            maker: maker,
            subaccount: subaccount,
            price: price,
            amount: amount,
            side: side == Side.BUY ? Side.SELL : Side.BUY
        });

        vm.startPrank(taker);

        adminPanel.deposit(taker, amount.fullMulDiv(price, 1e18));

        adminPanel.placeOrder({
            account: taker,
            args: PlaceOrderArgs({
                asset: asset,
                amount: amount,
                limitPrice: price,
                expiryTime: 0,
                side: side,
                tif: TiF.IOC,
                subaccount: subaccount,
                baseDenominated: true,
                reduceOnly: false,
                clientOrderId: 0
            })
        });

        vm.stopPrank();
    }

    function _mockCreateLimitOrder(
        bytes32 asset,
        address maker,
        uint256 subaccount,
        uint256 price,
        uint256 amount,
        Side side
    ) internal returns (uint256 orderId) {
        vm.startPrank(maker);

        adminPanel.deposit(maker, amount.fullMulDiv(price, 1e18));

        orderId = adminPanel.placeOrder(
            maker,
            PlaceOrderArgs({
                asset: asset,
                amount: amount,
                limitPrice: price,
                expiryTime: 0,
                side: side,
                tif: TiF.MOC,
                subaccount: subaccount,
                reduceOnly: false,
                baseDenominated: true,
                clientOrderId: 0
            })
        ).orderId;

        vm.stopPrank();
    }

    function _setMarkPriceConditional(bytes32 asset, uint256 triggerPrice, bool isStopLoss, bool isBuy) internal {
        uint256 delta = _hem(_random(), 0, 500) * adminPanel.getTickSize(asset);
        uint256 markPrice;

        if (isBuy) {
            if (isStopLoss) markPrice = triggerPrice + delta;
            else markPrice = triggerPrice > delta ? triggerPrice - delta : 0;
        } else {
            if (isStopLoss) markPrice = triggerPrice > delta ? triggerPrice - delta : 0;
            else markPrice = triggerPrice + delta;
        }

        vm.prank(admin);
        adminPanel.mockSetMarkPrice(asset, markPrice);
    }

    function _setMarkPriceConditionalNotMet(bytes32 asset, uint256 triggerPrice, bool isStopLoss, bool isBuy)
        internal
    {
        uint256 delta = _hem(_random(), 1, 1000) * adminPanel.getTickSize(asset);
        uint256 markPrice;

        if (isBuy) {
            if (isStopLoss) markPrice = triggerPrice > delta ? triggerPrice - delta : 0;
            else markPrice = triggerPrice + delta;
        } else {
            if (isStopLoss) markPrice = triggerPrice + delta;
            else markPrice = triggerPrice > delta ? triggerPrice - delta : 0;
        }

        vm.prank(admin);
        adminPanel.mockSetMarkPrice(asset, markPrice);
    }

    function _generateSignature(PlaceOrderArgs memory args, uint256 privateKey, uint256 expiry, uint256 nonce)
        internal
        pure
        returns (bytes memory)
    {
        bytes memory orderData = abi.encode(args);

        bytes32 hash = keccak256(bytes.concat(orderData, abi.encode(expiry, nonce)));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function _generateSignature(
        PlaceOrderArgs memory args,
        Condition memory condition,
        uint256 privateKey,
        uint256 expiry,
        uint256 nonce
    ) internal pure returns (bytes memory) {
        bytes memory orderData = abi.encode(args, condition);

        bytes32 hash = keccak256(bytes.concat(orderData, abi.encode(expiry, nonce)));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function _createMarketAdminPanel(address caller, bytes32 asset, MarketParams memory marketParams) internal {
        vm.prank(caller);
        adminPanel.createMarket({asset: asset, params: marketParams});
    }

    function _createMarketParams(uint256 price, bool crossMarginEnabled) internal pure returns (MarketParams memory) {
        return MarketParams({
            maxOpenLeverage: 50 ether, // 50x
            maintenanceMarginRatio: 0.01 ether,
            liquidationFeeRate: 0.01 ether, // 1%
            divergenceCap: 1 ether, // 100%
            reduceOnlyCap: 4,
            partialLiquidationThreshold: type(uint256).max, // max = no partial liquidation
            partialLiquidationRate: 0.2 ether, // 20% of position
            fundingInterval: 1 hours,
            resetInterval: 30 minutes,
            resetIterations: 5,
            innerClamp: 0.01 ether,
            outerClamp: 0.02 ether,
            interestRate: 0.005 ether,
            maxNumOrders: 1_000_000,
            maxLimitsPerTx: 40,
            minLimitOrderAmountInBase: 0.001 ether,
            lotSize: 0.001 ether,
            tickSize: 0.001 ether,
            initialPrice: price,
            crossMarginEnabled: crossMarginEnabled
        });
    }

    function _assumeNotRole(address caller, uint256 role) internal view {
        vm.assume(OwnableRoles(adminPanel).rolesOf(caller) & role == 0);
    }
}
