// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {BeforeAfter} from "../BeforeAfter.sol";
import {Properties} from "../Properties.sol";
// Chimera deps
import {vm} from "@chimera/Hevm.sol";

// Helpers
import {Panic} from "@recon/Panic.sol";

import "contracts/utils/OperatorPanel.sol";

abstract contract OperatorPanelTargets is
    BaseTargetFunctions,
    Properties
{
    /// CUSTOM TARGET FUNCTIONS - Add your own target functions here ///


    /// AUTO GENERATED TARGET FUNCTIONS - WARNING: DO NOT DELETE OR MODIFY THIS LINE ///

    function operatorPanel_approveOperator(address account, address operator, uint256 roles) public asActor {
        operatorPanel.approveOperator(account, operator, roles);
    }

    function operatorPanel_disapproveOperator(address account, address operator, uint256 roles) public asActor {
        operatorPanel.disapproveOperator(account, operator, roles);
    }
}