// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IViewPort} from "./IViewPort.sol";

interface IPerpManager is IViewPort {
    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                             PERP MANAGER
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function depositFreeCollateral(address account, uint256 amount) external;

    function withdrawFreeCollateral(address account, uint256 amount) external;

    function depositFromSpot(address account, uint256 amount) external;

    function withdrawToSpot(address account, uint256 amount) external;
}
