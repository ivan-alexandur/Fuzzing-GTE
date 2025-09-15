// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract BondingCurveMock {
    //<>=============================================================<>
    //||                                                             ||
    //||                    NON-VIEW FUNCTIONS                       ||
    //||                                                             ||
    //<>=============================================================<>


    //<>=============================================================<>
    //||                                                             ||
    //||                    SETTER FUNCTIONS                         ||
    //||                                                             ||
    //<>=============================================================<>
    // Function to set return values for getAverageCostInY
    function setGetAverageCostInYReturn(uint256 _value0) public {
        _getAverageCostInYReturn_0 = _value0;
    }

    // Function to set return values for viewAverageCostInY
    function setViewAverageCostInYReturn(uint256 _value0) public {
        _viewAverageCostInYReturn_0 = _value0;
    }

    // Function to set return values for viewAveragePriceInX
    function setViewAveragePriceInXReturn(uint256 _value0) public {
        _viewAveragePriceInXReturn_0 = _value0;
    }


    /*******************************************************************
     *   ⚠️ WARNING ⚠️ WARNING ⚠️ WARNING ⚠️ WARNING ⚠️ WARNING ⚠️  *
     *-----------------------------------------------------------------*
     *      Generally you only need to modify the sections above.      *
     *          The code below handles system operations.              *
     *******************************************************************/

    //<>=============================================================<>
    //||                                                             ||
    //||        ⚠️  STRUCT DEFINITIONS - DO NOT MODIFY  ⚠️          ||
    //||                                                             ||
    //<>=============================================================<>

    //<>=============================================================<>
    //||                                                             ||
    //||        ⚠️  EVENTS DEFINITIONS - DO NOT MODIFY  ⚠️          ||
    //||                                                             ||
    //<>=============================================================<>

    //<>=============================================================<>
    //||                                                             ||
    //||         ⚠️  INTERNAL STORAGE - DO NOT MODIFY  ⚠️           ||
    //||                                                             ||
    //<>=============================================================<>
    uint256 private _getAverageCostInYReturn_0;
    uint256 private _viewAverageCostInYReturn_0;
    uint256 private _viewAveragePriceInXReturn_0;

    //<>=============================================================<>
    //||                                                             ||
    //||          ⚠️  VIEW FUNCTIONS - DO NOT MODIFY  ⚠️            ||
    //||                                                             ||
    //<>=============================================================<>
    // Mock implementation of getAverageCostInY
    function getAverageCostInY(address token, uint256 x_0, uint256 x_1) public view returns (uint256) {
        return _getAverageCostInYReturn_0;
    }

    // Mock implementation of viewAverageCostInY
    function viewAverageCostInY(address token, uint256 x_0, uint256 x_1) public view returns (uint256) {
        return _viewAverageCostInYReturn_0;
    }

    // Mock implementation of viewAveragePriceInX
    function viewAveragePriceInX(address token, uint256 deltaY, bool isBuy) public view returns (uint256) {
        return _viewAveragePriceInXReturn_0;
    }

}