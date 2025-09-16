// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {BeforeAfter} from "../BeforeAfter.sol";
import {Properties} from "../Properties.sol";
// Chimera deps
import {vm} from "@chimera/Hevm.sol";

// Helpers
import {Panic} from "@recon/Panic.sol";

import "contracts/perps/modules/LiquidatorPanel.sol";

abstract contract LiquidatorPanelTargets is
    BaseTargetFunctions,
    Properties
{
    /// CUSTOM TARGET FUNCTIONS - Add your own target functions here ///


    /// AUTO GENERATED TARGET FUNCTIONS - WARNING: DO NOT DELETE OR MODIFY THIS LINE ///

    function liquidatorPanel_backstopLiquidate(bytes32 asset, address account, uint256 subaccount) public asActor {
        liquidatorPanel.backstopLiquidate(asset, account, subaccount);
    }

    function liquidatorPanel_cancelOwnershipHandover() public payable asActor {
        liquidatorPanel.cancelOwnershipHandover{value: msg.value}();
    }

    function liquidatorPanel_completeOwnershipHandover(address pendingOwner) public payable asActor {
        liquidatorPanel.completeOwnershipHandover{value: msg.value}(pendingOwner);
    }

    function liquidatorPanel_deleverage(bytes32 asset, DeleveragePair[] memory pairs) public asActor {
        liquidatorPanel.deleverage(asset, pairs);
    }

    function liquidatorPanel_delistClose(bytes32 asset, Account[] memory accounts) public asActor {
        liquidatorPanel.delistClose(asset, accounts);
    }

    function liquidatorPanel_grantRoles(address user, uint256 roles) public payable asActor {
        liquidatorPanel.grantRoles{value: msg.value}(user, roles);
    }

    function liquidatorPanel_liquidate(bytes32 asset, address account, uint256 subaccount) public asActor {
        liquidatorPanel.liquidate(asset, account, subaccount);
    }

    function liquidatorPanel_renounceOwnership() public payable asActor {
        liquidatorPanel.renounceOwnership{value: msg.value}();
    }

    function liquidatorPanel_renounceRoles(uint256 roles) public payable asActor {
        liquidatorPanel.renounceRoles{value: msg.value}(roles);
    }

    function liquidatorPanel_requestOwnershipHandover() public payable asActor {
        liquidatorPanel.requestOwnershipHandover{value: msg.value}();
    }

    function liquidatorPanel_revokeRoles(address user, uint256 roles) public payable asActor {
        liquidatorPanel.revokeRoles{value: msg.value}(user, roles);
    }

    function liquidatorPanel_transferOwnership(address newOwner) public payable asActor {
        liquidatorPanel.transferOwnership{value: msg.value}(newOwner);
    }
}