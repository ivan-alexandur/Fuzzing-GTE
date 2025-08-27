// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

interface IGTL {
    function orderUpdated(int256 marginDelta) external;
    function addSubaccount(uint256 subaccount) external;
    function removeSubaccount(uint256 subaccount) external;
}
