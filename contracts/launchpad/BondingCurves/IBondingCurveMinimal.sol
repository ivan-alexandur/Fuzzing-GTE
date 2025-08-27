// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import {IERC165} from "@openzeppelin/interfaces/IERC165.sol";

interface IBondingCurveMinimal is IERC165 {
    function init(bytes memory data) external;

    function initializeCurve(address token, uint256 totalSupply, uint256 bondingSupply) external;
    function buy(address token, uint256 baseAmount) external returns (uint256 quoteAmount);
    function sell(address token, uint256 baseAmount) external returns (uint256 quoteAmount);

    function quoteBaseForQuote(address token, uint256 quoteAmount, bool isBuy)
        external
        view
        returns (uint256 baseAmount);
    function quoteQuoteForBase(address token, uint256 baseAmount, bool isBuy)
        external
        view
        returns (uint256 quoteAmount);
    function baseSoldFromCurve(address token) external view returns (uint256);
    function quoteBoughtByCurve(address token) external view returns (uint256);
    function totalSupply(address token) external view returns (uint256);
    function bondingSupply(address token) external view returns (uint256);

    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
