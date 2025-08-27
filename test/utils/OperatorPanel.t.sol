// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOperatorHub, OperatorHub} from "contracts/utils/OperatorHub.sol";
import {SpotOperatorRoles, OperatorPanel} from "contracts/utils/OperatorPanel.sol";
import {OperatorHelperLib} from "contracts/utils/types/OperatorHelperLib.sol";

import {PerpManager} from "contracts/perps/PerpManager.sol";
import {AdminPanel} from "contracts/perps/modules/AdminPanel.sol";
import {IViewPort} from "contracts/perps/interfaces/IViewPort.sol";
import {IAccountManager} from "contracts/account-manager/IAccountManager.sol";

import {ERC1967Factory} from "@solady/utils/ERC1967Factory.sol";
import {TestPlus} from "lib/solady/test/utils/TestPlus.sol";

import "forge-std/console.sol";
import "forge-std/Test.sol";

contract MockOperator is OperatorPanel {
    constructor(address _operatorHub) OperatorPanel(_operatorHub) {}
}

/// @notice This contract tests the operator functionality
contract OperatorPanelTest is Test, TestPlus {
    struct Params {
        address account;
        address operator;
        uint256 role;
    }

    OperatorPanel public accountManager;
    OperatorPanel public perpsManager;
    OperatorHub public operatorHub;

    ERC1967Factory internal factory;
    Params internal params;

    function setUp() public {
        factory = new ERC1967Factory();
        bytes32 accountManagerSalt = bytes32(abi.encodePacked(address(this), bytes12(keccak256("ACCOUNT_MANAGER"))));
        bytes32 perpsManagerSalt = bytes32(abi.encodePacked(address(this), bytes12(keccak256("PERPS_MANAGER"))));
        bytes32 operatorPanelSalt = bytes32(abi.encodePacked(address(this), bytes12(keccak256("OPERATOR_PANEL"))));

        address predictedAccountManager = factory.predictDeterministicAddress(accountManagerSalt);
        address predictedPerpsManager = factory.predictDeterministicAddress(perpsManagerSalt);
        address predictedOperatorPanel = factory.predictDeterministicAddress(operatorPanelSalt);

        address accountManagerLogic = address(new MockOperator(predictedOperatorPanel));
        address perpsManagerLogic = address(new MockOperator(predictedOperatorPanel));
        address operatorPanelLogic =
            address(new OperatorHub(IViewPort(predictedPerpsManager), IAccountManager(predictedAccountManager)));

        accountManager =
            OperatorPanel(factory.deployDeterministic(accountManagerLogic, address(this), accountManagerSalt));

        perpsManager = OperatorPanel(factory.deployDeterministic(perpsManagerLogic, address(this), perpsManagerSalt));

        operatorHub = OperatorHub(factory.deployDeterministic(operatorPanelLogic, address(this), operatorPanelSalt));

        assertEq(address(accountManager), predictedAccountManager, "accountManager deployed at wrong address");
        assertEq(address(perpsManager), predictedPerpsManager, "perpsManager deployed at wrong address");
        assertEq(address(operatorHub), predictedOperatorPanel, "operatorHub deployed at wrong address");

        assertEq(accountManager.operatorHub(), address(operatorHub), "accountManager operatorHub mismatch");
        assertEq(perpsManager.operatorHub(), address(operatorHub), "perpsManager operatorHub mismatch");
        assertEq(address(operatorHub.accountManager()), address(accountManager), "operatorHub accountManager mismatch");
        assertEq(address(operatorHub.perpManager()), address(perpsManager), "operatorHub perpsManager mismatch");
    }

    function testFuzz_approve_operator_Spot(uint256) public {
        params.account = _randomUniqueNonZeroAddress(_random());
        params.operator = _randomUniqueNonZeroAddress(_random());
        params.role = _random();
        vm.assume(params.account != params.operator);

        assertEq(accountManager.getOperatorRoleApprovals(params.account, params.operator), 0);
        assertEq(perpsManager.getOperatorRoleApprovals(params.account, params.operator), 0);
        assertEq(operatorHub.getRoleApprovalsSpot(params.account, params.operator), 0);

        vm.expectEmit(true, true, true, true);
        emit OperatorPanel.OperatorApproved(
            accountManager.getOperatorEventNonce() + 1, params.account, params.operator, params.role
        );

        vm.prank(params.account);
        operatorHub.approveOperatorSpot(params.operator, params.role);

        assertEq(accountManager.getOperatorRoleApprovals(params.account, params.operator), params.role);
        assertEq(perpsManager.getOperatorRoleApprovals(params.account, params.operator), 0);
        assertEq(operatorHub.getRoleApprovalsSpot(params.account, params.operator), params.role);
    }

    function testFuzz_disapprove_operator_Spot(uint256) public {
        testFuzz_approve_operator_Spot(_random());
        uint256 disaprovedRoles = _random();
        uint256 expectedRoles = params.role & ~disaprovedRoles;

        vm.expectEmit(true, true, true, true);
        emit OperatorPanel.OperatorDisapproved(
            accountManager.getOperatorEventNonce() + 1, params.account, params.operator, disaprovedRoles
        );

        vm.prank(params.account);
        operatorHub.disapproveOperatorSpot(params.operator, disaprovedRoles);

        assertEq(operatorHub.getRoleApprovalsSpot(params.account, params.operator), expectedRoles);
        assertEq(accountManager.getOperatorRoleApprovals(params.account, params.operator), expectedRoles);
    }

    function testFuzz_approve_operator_Perps(uint256) public {
        params.account = _randomUniqueNonZeroAddress(_random());
        params.operator = _randomUniqueNonZeroAddress(_random());
        params.role = _random();
        vm.assume(params.account != params.operator);

        assertEq(accountManager.getOperatorRoleApprovals(params.account, params.operator), 0);
        assertEq(perpsManager.getOperatorRoleApprovals(params.account, params.operator), 0);
        assertEq(operatorHub.getRoleApprovalsSpot(params.account, params.operator), 0);

        vm.expectEmit(true, true, true, true);
        emit OperatorPanel.OperatorApproved(
            perpsManager.getOperatorEventNonce() + 1, params.account, params.operator, params.role
        );

        vm.prank(params.account);
        operatorHub.approveOperatorPerps(params.operator, params.role);

        assertEq(accountManager.getOperatorRoleApprovals(params.account, params.operator), 0);
        assertEq(perpsManager.getOperatorRoleApprovals(params.account, params.operator), params.role);
        assertEq(operatorHub.getRoleApprovalsPerps(params.account, params.operator), params.role);
    }

    function testFuzz_disapprove_operator_Perps(uint256) public {
        testFuzz_approve_operator_Perps(_random());
        uint256 disaprovedRoles = _random();
        uint256 expectedRoles = params.role & ~disaprovedRoles;

        vm.expectEmit(true, true, true, true);
        emit OperatorPanel.OperatorDisapproved(
            perpsManager.getOperatorEventNonce() + 1, params.account, params.operator, disaprovedRoles
        );

        vm.prank(params.account);
        operatorHub.disapproveOperatorPerps(params.operator, disaprovedRoles);

        assertEq(operatorHub.getRoleApprovalsPerps(params.account, params.operator), expectedRoles);
        assertEq(perpsManager.getOperatorRoleApprovals(params.account, params.operator), expectedRoles);
    }
}
