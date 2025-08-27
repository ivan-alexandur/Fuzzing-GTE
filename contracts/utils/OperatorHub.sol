// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IOperatorPanel} from "./interfaces/IOperatorPanel.sol";
import {IOperatorHub} from "./interfaces/IOperatorHub.sol";

import {IViewPort} from "../perps/interfaces/IViewPort.sol";
import {IAccountManager} from "../account-manager/IAccountManager.sol";

contract OperatorHub is IOperatorHub {
    IOperatorPanel public immutable perpManager;
    IOperatorPanel public immutable accountManager;

    constructor(IViewPort perpManager_, IAccountManager accountManager_) {
        perpManager = IOperatorPanel(address(perpManager_));
        accountManager = IOperatorPanel(address(accountManager_));
    }

    function getRoleApprovalsSpot(address account, address operator) external view returns (uint256 roles) {
        return accountManager.getOperatorRoleApprovals(account, operator);
    }

    function getRoleApprovalsPerps(address account, address operator) external view returns (uint256 roles) {
        return perpManager.getOperatorRoleApprovals(account, operator);
    }

    function approveOperatorSpot(address operator, uint256 roles) external {
        accountManager.approveOperator(msg.sender, operator, roles);
    }

    function approveOperatorPerps(address operator, uint256 roles) external {
        perpManager.approveOperator(msg.sender, operator, roles);
    }

    function disapproveOperatorSpot(address operator, uint256 roles) external {
        accountManager.disapproveOperator(msg.sender, operator, roles);
    }

    function disapproveOperatorPerps(address operator, uint256 roles) external {
        perpManager.disapproveOperator(msg.sender, operator, roles);
    }
}
