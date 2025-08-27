// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "../PerpManagerTestBase.sol";

import {TestPlus} from "lib/solady/test/utils/TestPlus.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

import {Constants} from "../../../contracts/perps/types/Constants.sol";

import {PerpsOperatorRoles} from "../../../contracts/utils/OperatorPanel.sol";
import {OperatorHelperLib} from "../../../contracts/utils/types/OperatorHelperLib.sol";

contract PerpManagerAccessControlTest is PerpManagerTestBase {
    using FixedPointMathLib for uint256;

    struct Params {
        address account;
        uint256 subaccount;
        address operator;
        uint256 operatorRole;
        address to;
        uint256 amount;
        uint256 leverage;
        uint256 price;
        Side side;
        uint256 orderId;
    }

    Params params;

    function test_depositFreeCollateral_revert_notUser(uint256) public {
        _generateFuzzedParams();

        vm.prank(params.operator);
        vm.expectRevert(OperatorHelperLib.OperatorDoesNotHaveRole.selector);
        perpManager.deposit(params.account, params.amount);
    }

    function test_depositFreeCollateral_revert_notOperator(uint256) public {
        _generateFuzzedParams();

        params.operatorRole = 1 << uint8(_randomPerpRole(_random()));
        _assumeNotRole(params.operatorRole, PerpsOperatorRoles.DEPOSIT_ACCOUNT);
        _assumeNotRole(params.operatorRole, PerpsOperatorRoles.ADMIN);

        vm.prank(params.account);
        perpManager.approveOperator(params.account, params.operator, params.operatorRole);

        vm.prank(params.operator);
        vm.expectRevert(OperatorHelperLib.OperatorDoesNotHaveRole.selector);
        perpManager.deposit(params.account, params.amount);
    }

    function test_depositFreeCollateral_From_Operator(uint256) public {
        _generateFuzzedParams();

        params.operatorRole = 1 << uint8(PerpsOperatorRoles.DEPOSIT_ACCOUNT);

        _mintAndApprove(params.account, params.amount);

        vm.prank(params.account);
        perpManager.approveOperator(params.account, params.operator, params.operatorRole);

        vm.prank(params.operator);
        perpManager.deposit(params.account, params.amount);

        assertEq(usdc.balanceOf(params.account), 0);
        assertEq(perpManager.getFreeCollateralBalance(params.account), params.amount);
    }

    function test_depositTo(uint256) public {
        _generateFuzzedParams();
        vm.assume(params.account != params.to);

        _mintAndApprove(params.account, params.amount);

        vm.prank(params.account);
        perpManager.depositTo(params.to, params.amount);

        assertEq(usdc.balanceOf(params.account), 0);
        assertEq(perpManager.getFreeCollateralBalance(params.to), params.amount);
        assertEq(perpManager.getFreeCollateralBalance(params.account), 0);
    }

    function test_withdrawFreeCollateral_revert_notUser(uint256) public {
        _generateFuzzedParams();

        vm.prank(params.operator);
        vm.expectRevert(OperatorHelperLib.OperatorDoesNotHaveRole.selector);
        perpManager.deposit(params.account, params.amount);
    }

    function test_withdrawFreeCollateral_revert_notOperator(uint256) public {
        _generateFuzzedParams();

        params.operatorRole = 1 << uint8(_randomPerpRole(_random()));
        _assumeNotRole(params.operatorRole, PerpsOperatorRoles.WITHDRAW_ACCOUNT);
        _assumeNotRole(params.operatorRole, PerpsOperatorRoles.ADMIN);

        vm.prank(params.account);
        perpManager.approveOperator(params.account, params.operator, params.operatorRole);

        vm.prank(params.operator);
        vm.expectRevert(OperatorHelperLib.OperatorDoesNotHaveRole.selector);
        perpManager.withdraw(params.account, params.amount);
    }

    function test_withdrawFreeCollateral_From_Operator(uint256) public {
        _generateFuzzedParams();

        params.operatorRole = 1 << uint8(PerpsOperatorRoles.WITHDRAW_ACCOUNT);

        _mintAndApproveAndDeposit(params.account, params.amount);

        vm.prank(params.account);
        perpManager.approveOperator(params.account, params.operator, params.operatorRole);

        vm.prank(params.operator);
        perpManager.withdraw(params.account, params.amount);

        assertEq(usdc.balanceOf(params.account), params.amount);
        assertEq(perpManager.getFreeCollateralBalance(params.account), 0);
    }

    function test_depositMargin_revert_notOperator(uint256) public {
        _generateFuzzedParams();

        params.operatorRole = 1 << uint8(_randomPerpRole(_random()));
        _assumeNotRole(params.operatorRole, PerpsOperatorRoles.DEPOSIT_MARGIN);
        _assumeNotRole(params.operatorRole, PerpsOperatorRoles.ADMIN);

        _mintAndApprove(params.account, 100_000e18);

        _placeTrade({
            asset: ETH,
            taker: params.account,
            maker: jb,
            subaccount: params.subaccount,
            price: 4000e18,
            amount: 1e18,
            side: Side.BUY
        });

        vm.prank(params.account);
        perpManager.approveOperator(params.account, params.operator, params.operatorRole);

        vm.prank(params.operator);
        vm.expectRevert(OperatorHelperLib.OperatorDoesNotHaveRole.selector);
        perpManager.addMargin(params.account, params.subaccount, params.amount);
    }

    function test_withdrawMargin_revert_notUser(uint256) public {
        _generateFuzzedParams();

        vm.prank(params.operator);
        vm.expectRevert(OperatorHelperLib.OperatorDoesNotHaveRole.selector);
        perpManager.removeMargin(params.account, params.subaccount, params.amount);
    }

    function test_withdrawMargin_revert_notOperator(uint256) public {
        _generateFuzzedParams();

        params.operatorRole = 1 << uint8(_randomPerpRole(_random()));
        _assumeNotRole(params.operatorRole, PerpsOperatorRoles.WITHDRAW_MARGIN);
        _assumeNotRole(params.operatorRole, PerpsOperatorRoles.ADMIN);

        vm.prank(params.account);
        perpManager.approveOperator(params.account, params.operator, params.operatorRole);

        vm.prank(params.operator);
        vm.expectRevert(OperatorHelperLib.OperatorDoesNotHaveRole.selector);
        perpManager.removeMargin(params.account, params.subaccount, params.amount);
    }

    function test_setPositionLeverage_revert_notUser(uint256) public {
        _generateFuzzedParams();

        vm.prank(params.operator);
        vm.expectRevert(OperatorHelperLib.OperatorDoesNotHaveRole.selector);
        perpManager.setPositionLeverage("ETH", params.account, params.subaccount, params.leverage);
    }

    function test_setPositionLeverage_revert_notOperator(uint256) public {
        _generateFuzzedParams();

        _assumeNotRole(params.operatorRole, PerpsOperatorRoles.SET_LEVERAGE);
        _assumeNotRole(params.operatorRole, PerpsOperatorRoles.ADMIN);

        vm.prank(params.account);
        perpManager.approveOperator(params.account, params.operator, params.operatorRole);

        vm.prank(params.operator);
        vm.expectRevert(OperatorHelperLib.OperatorDoesNotHaveRole.selector);
        perpManager.setPositionLeverage("ETH", params.account, params.subaccount, params.leverage);
    }

    function test_setPositionLeverage_From_Operator(uint256) public {
        params.leverage = _hem(_random(), 1e18, 50e18);

        params.operator = _randomUniqueNonZeroAddress(_random());
        params.operatorRole = 1 << uint8(PerpsOperatorRoles.SET_LEVERAGE);

        vm.assume(params.account != params.operator);

        vm.prank(params.account);
        perpManager.approveOperator(params.account, params.operator, params.operatorRole);

        vm.prank(params.operator);
        perpManager.setPositionLeverage("ETH", params.account, params.subaccount, params.leverage);

        assertEq(
            perpManager.getPositionLeverage("ETH", params.account, params.subaccount),
            params.leverage,
            "leverage not set"
        );
        assertEq(
            perpManager.getMarginBalance(params.account, params.subaccount),
            int256(params.amount),
            "margin should be unchanged"
        ); // no position
    }

    function test_placeOrder_revert_notUser(uint256) public {
        _generateFuzzedParams();

        _mintAndApproveAndDeposit(params.account, params.amount.fullMulDiv(params.price, 1e18));

        vm.prank(admin);
        perpManager.mockSetMarkPrice("ETH", params.price);

        vm.expectRevert(OperatorHelperLib.OperatorDoesNotHaveRole.selector);
        _createLimitOrderFromOperator(
            "ETH", params.account, params.operator, params.subaccount, params.price, params.amount, params.side
        );
    }

    function test_placeOrder_revert_notOperator(uint256) public {
        _generateFuzzedParams();

        params.operatorRole = 1 << uint8(_randomPerpRole(_random()));
        _assumeNotRole(params.operatorRole, PerpsOperatorRoles.PLACE_ORDER);
        _assumeNotRole(params.operatorRole, PerpsOperatorRoles.ADMIN);

        _mintAndApproveAndDeposit(params.account, params.amount.fullMulDiv(params.price, 1e18));

        vm.prank(params.account);
        perpManager.approveOperator(params.account, params.operator, params.operatorRole);

        vm.prank(admin);
        perpManager.mockSetMarkPrice("ETH", params.price);

        vm.expectRevert(OperatorHelperLib.OperatorDoesNotHaveRole.selector);
        _createLimitOrderFromOperator(
            "ETH", params.account, params.operator, params.subaccount, params.price, params.amount, params.side
        );
    }

    function test_placeOrder_From_Operator(uint256) public {
        _generateFuzzedParams();

        params.operatorRole = 1 << uint8(PerpsOperatorRoles.PLACE_ORDER);

        _mintAndApproveAndDeposit(params.account, params.amount.fullMulDiv(params.price, 1e18));

        vm.prank(params.account);
        perpManager.approveOperator(params.account, params.operator, params.operatorRole);

        vm.prank(admin);
        perpManager.mockSetMarkPrice("ETH", params.price);

        params.orderId = _createLimitOrderFromOperator(
            "ETH", params.account, params.operator, params.subaccount, params.price, params.amount, params.side
        );
    }

    function test_amendLimitOrder_revert_notUser(uint256) public {
        test_placeOrder_From_Operator(_random());

        address newOperator = _randomUniqueNonZeroAddress(_random());
        vm.assume(params.account != newOperator && newOperator != params.operator);
        params.operator = newOperator;

        params.amount = _conformLots("ETH", _hem(_random(), 0.001e18, 1000e18));
        params.price = _conformTick("ETH", _hem(_random(), 1e18, 10_000e18));

        _mintAndApproveAndDeposit(params.account, params.amount.fullMulDiv(params.price, 1e18));

        vm.expectRevert(OperatorHelperLib.OperatorDoesNotHaveRole.selector);
        _amendLimitOrderFromOperator(
            "ETH",
            params.account,
            params.operator,
            params.subaccount,
            params.orderId,
            params.price,
            params.amount,
            params.side
        );
    }

    function test_amendLimitOrder_revert_notOperator(uint256) public {
        test_placeOrder_From_Operator(_random());

        address newOperator = _randomUniqueNonZeroAddress(_random());
        vm.assume(params.account != newOperator && newOperator != params.operator);
        params.operator = newOperator;

        params.amount = _conformLots("ETH", _hem(_random(), 0.001e18, 1000e18));
        params.price = _conformTick("ETH", _hem(_random(), 1e18, 10_000e18));

        params.operatorRole = 1 << uint8(_randomPerpRole(_random()));
        _assumeNotRole(params.operatorRole, PerpsOperatorRoles.PLACE_ORDER);
        _assumeNotRole(params.operatorRole, PerpsOperatorRoles.ADMIN);

        _mintAndApproveAndDeposit(params.account, params.amount.fullMulDiv(params.price, 1e18));

        vm.prank(params.account);
        perpManager.approveOperator(params.account, params.operator, params.operatorRole);

        vm.expectRevert(OperatorHelperLib.OperatorDoesNotHaveRole.selector);
        _amendLimitOrderFromOperator(
            "ETH",
            params.account,
            params.operator,
            params.subaccount,
            params.orderId,
            params.price,
            params.amount,
            params.side
        );
    }

    function test_amendLimitOrder_From_Operator(uint256) public {
        test_placeOrder_From_Operator(_random());

        address newOperator = _randomUniqueNonZeroAddress(_random());
        vm.assume(params.account != newOperator && newOperator != params.operator);
        params.operator = newOperator;

        params.amount = _conformLots("ETH", _hem(_random(), 0.001e18, 1000e18));
        params.price = _conformTick("ETH", _hem(_random(), 1e18, 10_000e18));

        params.operatorRole = 1 << uint8(PerpsOperatorRoles.PLACE_ORDER);

        _mintAndApproveAndDeposit(params.account, params.amount.fullMulDiv(params.price, 1e18));

        vm.prank(params.account);
        perpManager.approveOperator(params.account, params.operator, params.operatorRole);

        _amendLimitOrderFromOperator(
            "ETH",
            params.account,
            params.operator,
            params.subaccount,
            params.orderId,
            params.price,
            params.amount,
            params.side
        );
    }

    function test_cancelLimitOrders_revert_notUser(uint256) public {
        test_placeOrder_From_Operator(_random());

        address newOperator = _randomUniqueNonZeroAddress(_random());
        vm.assume(params.account != newOperator && newOperator != params.operator);

        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = params.orderId;

        vm.prank(newOperator);
        vm.expectRevert(OperatorHelperLib.OperatorDoesNotHaveRole.selector);
        perpManager.cancelLimitOrders("ETH", params.account, params.subaccount, orderIds);
    }

    function test_cancelLimitOrders_revert_notOperator(uint256) public {
        test_placeOrder_From_Operator(_random());

        address newOperator = _randomUniqueNonZeroAddress(_random());
        vm.assume(params.account != newOperator && newOperator != params.operator);
        params.operator = newOperator;

        params.operatorRole = 1 << uint8(_randomPerpRole(_random()));
        _assumeNotRole(params.operatorRole, PerpsOperatorRoles.PLACE_ORDER);
        _assumeNotRole(params.operatorRole, PerpsOperatorRoles.ADMIN);

        vm.prank(params.account);
        perpManager.approveOperator(params.account, params.operator, params.operatorRole);

        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = params.orderId;

        vm.prank(params.operator);
        vm.expectRevert(OperatorHelperLib.OperatorDoesNotHaveRole.selector);
        perpManager.cancelLimitOrders("ETH", params.account, params.subaccount, orderIds);
    }

    function test_cancelLimitOrders_From_Operator(uint256) public {
        test_placeOrder_From_Operator(_random());

        address newOperator = _randomUniqueNonZeroAddress(_random());
        vm.assume(params.account != newOperator && newOperator != params.operator);
        params.operator = newOperator;

        params.operatorRole = 1 << uint8(PerpsOperatorRoles.PLACE_ORDER);

        vm.prank(params.account);
        perpManager.approveOperator(params.account, params.operator, params.operatorRole);

        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = params.orderId;

        vm.prank(params.operator);
        perpManager.cancelLimitOrders("ETH", params.account, params.subaccount, orderIds);
    }

    function test_postLimitOrderBackstop_revert_notUser(uint256) public {
        _generateFuzzedParams();

        _mintAndApproveAndDeposit(params.account, params.amount.fullMulDiv(params.price, 1e18));

        vm.prank(admin);
        perpManager.mockSetMarkPrice("ETH", params.price);

        vm.expectRevert(OperatorHelperLib.OperatorDoesNotHaveRole.selector);
        _createLimitOrderBackstopFromOperator(
            "ETH", params.account, params.operator, params.subaccount, params.price, params.amount, params.side
        );
    }

    function test_postLimitOrderBackstop_revert_notOperator(uint256) public {
        _generateFuzzedParams();

        params.operatorRole = 1 << uint8(_randomPerpRole(_random()));
        _assumeNotRole(params.operatorRole, PerpsOperatorRoles.PLACE_ORDER);
        _assumeNotRole(params.operatorRole, PerpsOperatorRoles.ADMIN);

        _mintAndApproveAndDeposit(params.account, params.amount.fullMulDiv(params.price, 1e18));

        vm.prank(params.account);
        perpManager.approveOperator(params.account, params.operator, params.operatorRole);

        vm.prank(admin);
        perpManager.mockSetMarkPrice("ETH", params.price);

        vm.expectRevert(OperatorHelperLib.OperatorDoesNotHaveRole.selector);
        _createLimitOrderBackstopFromOperator(
            "ETH", params.account, params.operator, params.subaccount, params.price, params.amount, params.side
        );
    }

    function test_postLimitOrderBackstop_From_Operator(uint256) public {
        _generateFuzzedParams();

        params.operatorRole = 1 << uint8(PerpsOperatorRoles.PLACE_ORDER);

        _mintAndApproveAndDeposit(params.account, params.amount.fullMulDiv(params.price, 1e18));

        vm.prank(params.account);
        perpManager.approveOperator(params.account, params.operator, params.operatorRole);

        vm.prank(admin);
        perpManager.mockSetMarkPrice("ETH", params.price);

        params.orderId = _createLimitOrderBackstopFromOperator(
            "ETH", params.account, params.operator, params.subaccount, params.price, params.amount, params.side
        );
    }

    function test_amendLimitOrderBackstop_revert_notUser(uint256) public {
        test_postLimitOrderBackstop_From_Operator(_random());

        address newOperator = _randomUniqueNonZeroAddress(_random());
        vm.assume(params.account != newOperator && newOperator != params.operator);
        params.operator = newOperator;

        params.amount = _conformLots("ETH", _hem(_random(), 0.001e18, 1000e18));
        params.price = _conformTick("ETH", _hem(_random(), 1e18, 10_000e18));

        _mintAndApproveAndDeposit(params.account, params.amount.fullMulDiv(params.price, 1e18));

        vm.expectRevert(OperatorHelperLib.OperatorDoesNotHaveRole.selector);
        _amendLimitOrderBackstopFromOperator(
            "ETH",
            params.account,
            params.operator,
            params.subaccount,
            params.orderId,
            params.price,
            params.amount,
            params.side
        );
    }

    function test_amendLimitOrderBackstop_revert_notOperator(uint256) public {
        test_postLimitOrderBackstop_From_Operator(_random());

        address newOperator = _randomUniqueNonZeroAddress(_random());
        vm.assume(params.account != newOperator && newOperator != params.operator);
        params.operator = newOperator;

        params.amount = _conformLots("ETH", _hem(_random(), 0.001e18, 1000e18));
        params.price = _conformTick("ETH", _hem(_random(), 1e18, 10_000e18));

        params.operatorRole = 1 << uint8(_randomPerpRole(_random()));
        _assumeNotRole(params.operatorRole, PerpsOperatorRoles.PLACE_ORDER);
        _assumeNotRole(params.operatorRole, PerpsOperatorRoles.ADMIN);

        _mintAndApproveAndDeposit(params.account, params.amount.fullMulDiv(params.price, 1e18));

        vm.prank(params.account);
        perpManager.approveOperator(params.account, params.operator, params.operatorRole);

        vm.expectRevert(OperatorHelperLib.OperatorDoesNotHaveRole.selector);
        _amendLimitOrderBackstopFromOperator(
            "ETH",
            params.account,
            params.operator,
            params.subaccount,
            params.orderId,
            params.price,
            params.amount,
            params.side
        );
    }

    function test_amendLimitOrderBackstop_From_Operator(uint256) public {
        test_postLimitOrderBackstop_From_Operator(_random());

        address newOperator = _randomUniqueNonZeroAddress(_random());
        vm.assume(params.account != newOperator && newOperator != params.operator);
        params.operator = newOperator;

        params.amount = _conformLots("ETH", _hem(_random(), 0.001e18, 1000e18));
        params.price = _conformTick("ETH", _hem(_random(), 1e18, 10_000e18));

        params.operatorRole = 1 << uint8(PerpsOperatorRoles.PLACE_ORDER);

        _mintAndApproveAndDeposit(params.account, params.amount.fullMulDiv(params.price, 1e18));

        vm.prank(params.account);
        perpManager.approveOperator(params.account, params.operator, params.operatorRole);

        _amendLimitOrderBackstopFromOperator(
            "ETH",
            params.account,
            params.operator,
            params.subaccount,
            params.orderId,
            params.price,
            params.amount,
            params.side
        );
    }

    function test_cancelLimitOrdersBackstop_revert_notUser(uint256) public {
        test_postLimitOrderBackstop_From_Operator(_random());

        address newOperator = _randomUniqueNonZeroAddress(_random());
        vm.assume(params.account != newOperator && newOperator != params.operator);

        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = params.orderId;

        vm.prank(newOperator);
        vm.expectRevert(OperatorHelperLib.OperatorDoesNotHaveRole.selector);
        perpManager.cancelLimitOrdersBackstop("ETH", params.account, params.subaccount, orderIds);
    }

    function test_cancelLimitOrdersBackstop_revert_notOperator(uint256) public {
        test_postLimitOrderBackstop_From_Operator(_random());

        address newOperator = _randomUniqueNonZeroAddress(_random());
        vm.assume(params.account != newOperator && newOperator != params.operator);
        params.operator = newOperator;

        params.operatorRole = 1 << uint8(_randomPerpRole(_random()));
        _assumeNotRole(params.operatorRole, PerpsOperatorRoles.PLACE_ORDER);
        _assumeNotRole(params.operatorRole, PerpsOperatorRoles.ADMIN);

        vm.prank(params.account);
        perpManager.approveOperator(params.account, params.operator, params.operatorRole);

        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = params.orderId;

        vm.prank(params.operator);
        vm.expectRevert(OperatorHelperLib.OperatorDoesNotHaveRole.selector);
        perpManager.cancelLimitOrdersBackstop("ETH", params.account, params.subaccount, orderIds);
    }

    function test_cancelLimitOrdersBackstop_From_Operator(uint256) public {
        test_postLimitOrderBackstop_From_Operator(_random());

        address newOperator = _randomUniqueNonZeroAddress(_random());
        vm.assume(params.account != newOperator && newOperator != params.operator);
        params.operator = newOperator;

        params.operatorRole = 1 << uint8(PerpsOperatorRoles.PLACE_ORDER);

        vm.prank(params.account);
        perpManager.approveOperator(params.account, params.operator, params.operatorRole);

        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = params.orderId;

        vm.prank(params.operator);
        perpManager.cancelLimitOrdersBackstop("ETH", params.account, params.subaccount, orderIds);
    }

    function _generateFuzzedParams() internal {
        params.account = _randomUniqueNonZeroAddress(_random());
        params.subaccount = _random();
        params.operator = _randomUniqueNonZeroAddress(_random());
        params.to = _randomUniqueNonZeroAddress(_random());
        params.amount = _conformLots("ETH", _hem(_random(), 0.001e18, 1000e18));
        params.price = _conformTick("ETH", _hem(_random(), 1e18, 10_000e18));
        params.leverage = _hem(_random(), 1e18, 50e18);
        params.side = Side(_random() % 2);

        vm.assume(params.account != params.operator);
    }

    /// @dev has to use the last item in the enum
    function _randomPerpRole(uint256 rand) internal pure returns (PerpsOperatorRoles) {
        return PerpsOperatorRoles(uint8(rand % uint256(PerpsOperatorRoles.WITHDRAW_ACCOUNT)));
    }

    function _assumeNotRole(uint256 value, PerpsOperatorRoles operatorRole) internal pure {
        vm.assume(value & (1 << uint8(operatorRole)) == 0);
    }

    function _createLimitOrderFromOperator(
        bytes32 asset,
        address maker,
        address operator,
        uint256 subaccount,
        uint256 price,
        uint256 amount,
        Side side
    ) internal returns (uint256 orderId) {
        vm.prank(operator);
        orderId = perpManager.placeOrder(
            maker,
            PlaceOrderArgs({
                asset: asset,
                subaccount: subaccount,
                side: side,
                limitPrice: price,
                amount: amount,
                baseDenominated: true,
                tif: TiF.GTC,
                expiryTime: uint32(block.timestamp + _hem(_random(), 1, 365 days)),
                reduceOnly: false,
                clientOrderId: 0
            })
        ).orderId;

        vm.stopPrank();
    }

    function _createLimitOrderBackstopFromOperator(
        bytes32 asset,
        address maker,
        address operator,
        uint256 subaccount,
        uint256 price,
        uint256 amount,
        Side side
    ) internal returns (uint256 orderId) {
        vm.prank(operator);
        orderId = perpManager.postLimitOrderBackstop(
            maker,
            PlaceOrderArgs({
                asset: asset,
                subaccount: subaccount,
                side: side,
                limitPrice: price,
                amount: amount,
                baseDenominated: true,
                tif: TiF.MOC,
                expiryTime: uint32(block.timestamp + _hem(_random(), 1, 365 days)),
                reduceOnly: false,
                clientOrderId: 0
            })
        ).orderId;

        vm.stopPrank();
    }

    function _amendLimitOrderFromOperator(
        bytes32 asset,
        address maker,
        address operator,
        uint256 subaccount,
        uint256 orderId,
        uint256 price,
        uint256 amount,
        Side side
    ) internal {
        vm.prank(operator);
        perpManager.amendLimitOrder(
            maker,
            AmendLimitOrderArgs({
                asset: asset,
                subaccount: subaccount,
                orderId: orderId,
                baseAmount: amount,
                price: price,
                expiryTime: 0,
                side: side,
                reduceOnly: false
            })
        );
    }

    function _amendLimitOrderBackstopFromOperator(
        bytes32 asset,
        address maker,
        address operator,
        uint256 subaccount,
        uint256 orderId,
        uint256 price,
        uint256 amount,
        Side side
    ) internal {
        vm.prank(operator);
        perpManager.amendLimitOrderBackstop(
            maker,
            AmendLimitOrderArgs({
                asset: asset,
                subaccount: subaccount,
                orderId: orderId,
                baseAmount: amount,
                price: price,
                expiryTime: 0,
                side: side,
                reduceOnly: false
            })
        );
    }
}
