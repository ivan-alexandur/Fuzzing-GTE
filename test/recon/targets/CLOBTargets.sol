// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {BeforeAfter} from "../BeforeAfter.sol";
import {Properties} from "../Properties.sol";
// Chimera deps
import {vm} from "@chimera/Hevm.sol";

// Helpers
import {Panic} from "@recon/Panic.sol";

import "contracts/clob/CLOB.sol";

abstract contract ClobTargets is
    BaseTargetFunctions,
    Properties
{
    /// CUSTOM TARGET FUNCTIONS - Add your own target functions here ///


    /// AUTO GENERATED TARGET FUNCTIONS - WARNING: DO NOT DELETE OR MODIFY THIS LINE ///

    function clob_acceptOwnership() public asActor {
        clob.acceptOwnership();
    }

    function clob_adminCancelExpiredOrders(uint256[] memory ids, Side side) public asActor {
        clob.adminCancelExpiredOrders(ids, side);
    }

    function clob_amend(address account, ICLOB.AmendArgs memory args) public asActor {
        clob.amend(account, args);
    }

    function clob_cancel(address account, ICLOB.CancelArgs memory args) public asActor {
        clob.cancel(account, args);
    }

    function clob_initialize(MarketConfig memory marketConfig, MarketSettings memory marketSettings, address initialOwner) public asActor {
        clob.initialize(marketConfig, marketSettings, initialOwner);
    }

    function clob_placeOrder(address account, ICLOB.PlaceOrderArgs memory args) public asActor {
        clob.placeOrder(account, args);
    }

    function clob_renounceOwnership() public asActor {
        clob.renounceOwnership();
    }

    function clob_setLotSizeInBase(uint256 newLotSizeInBase) public asActor {
        clob.setLotSizeInBase(newLotSizeInBase);
    }

    function clob_setMaxLimitsPerTx(uint8 newMaxLimits) public asActor {
        clob.setMaxLimitsPerTx(newMaxLimits);
    }

    function clob_setMinLimitOrderAmountInBase(uint256 newMinLimitOrderAmountInBase) public asActor {
        clob.setMinLimitOrderAmountInBase(newMinLimitOrderAmountInBase);
    }

    function clob_setTickSize(uint256 tickSize) public asActor {
        clob.setTickSize(tickSize);
    }

    function clob_transferOwnership(address newOwner) public asActor {
        clob.transferOwnership(newOwner);
    }
}