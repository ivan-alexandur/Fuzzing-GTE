// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IOperatorPanel} from "../interfaces/IOperatorPanel.sol";
import {SpotOperatorRoles, PerpsOperatorRoles, OperatorStorage} from "../OperatorPanel.sol";

library OperatorHelperLib {
    /// @dev sig: 0x732ea322
    error OperatorDoesNotHaveRole();

    function assertHasRole(uint256 rolesPacked, uint8 role) internal pure {
        if (rolesPacked & 1 << role == 0 && rolesPacked & 1 == 0) revert OperatorDoesNotHaveRole();
    }

    /// @dev Performs operator check with both operator and router bypass
    function onlySenderOrOperator(
        IOperatorPanel operator,
        address gteRouter,
        address account,
        SpotOperatorRoles requiredRole
    ) internal view {
        if (msg.sender == account || msg.sender == gteRouter) return;

        uint256 rolesPacked = operator.getOperatorRoleApprovals(account, msg.sender);
        assertHasRole(rolesPacked, uint8(requiredRole));
    }

    /// @dev Performs operator check with just operator
    function onlySenderOrOperator(IOperatorPanel operator, address account, SpotOperatorRoles requiredRole)
        internal
        view
    {
        if (msg.sender == account) return;

        uint256 rolesPacked = operator.getOperatorRoleApprovals(account, msg.sender);
        assertHasRole(rolesPacked, uint8(requiredRole));
    }

    /// @dev Performs spot operator check with storage directly (for contracts inheriting Operator)
    function onlySenderOrOperator(
        OperatorStorage storage self,
        address gteRouter,
        address account,
        SpotOperatorRoles requiredRole
    ) internal view {
        if (msg.sender == account || msg.sender == gteRouter) return;

        uint256 rolesPacked = self.operatorRoleApprovals[account][msg.sender];
        assertHasRole(rolesPacked, uint8(requiredRole));
    }

    /// @dev Performs perps operator check with storage directly (for contracts inheriting Operator)
    function onlySenderOrOperator(OperatorStorage storage self, address account, PerpsOperatorRoles requiredRole)
        internal
        view
    {
        if (msg.sender == account) return;

        uint256 rolesPacked = self.operatorRoleApprovals[account][msg.sender];
        assertHasRole(rolesPacked, uint8(requiredRole));
    }
}
