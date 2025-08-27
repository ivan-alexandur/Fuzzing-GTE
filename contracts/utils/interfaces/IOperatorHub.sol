// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IOperatorHub {
    function getRoleApprovalsSpot(address account, address operator) external view returns (uint256 roles);
    function getRoleApprovalsPerps(address account, address operator) external view returns (uint256 roles);
    function approveOperatorSpot(address operator, uint256 roles) external;
    function approveOperatorPerps(address operator, uint256 roles) external;
    function disapproveOperatorSpot(address operator, uint256 roles) external;
    function disapproveOperatorPerps(address operator, uint256 roles) external;
}
