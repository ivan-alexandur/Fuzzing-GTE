// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IOperatorPanel {
    function approveOperator(address account, address operator, uint256 roles) external;
    function disapproveOperator(address account, address operator, uint256 roles) external;
    function getOperatorRoleApprovals(address account, address operator) external view returns (uint256);
    function getOperatorEventNonce() external view returns (uint256);
}
