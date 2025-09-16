// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

// Chimera deps
import {BaseSetup} from "@chimera/BaseSetup.sol";
import {vm} from "@chimera/Hevm.sol";

// Managers
import {ActorManager} from "@recon/ActorManager.sol";
import {AssetManager} from "@recon/AssetManager.sol";

// Helpers
import {Utils} from "@recon/Utils.sol";

// Your deps
import {CLOB} from "contracts/clob/CLOB.sol";
import {LiquidatorPanel} from "contracts/perps/modules/LiquidatorPanel.sol";
import {OperatorPanel} from "contracts/utils/OperatorPanel.sol";
import {PerpManager} from "contracts/perps/PerpManager.sol";

abstract contract Setup is BaseSetup, ActorManager, AssetManager, Utils {
    CLOB clob;
    LiquidatorPanel liquidatorPanel;
    OperatorPanel operatorPanel;
    PerpManager perpManager;

    /// === Setup === ///
    /// This contains all calls to be performed in the tester constructor, both for Echidna and Foundry
    function setup() internal virtual override {
        clob = new CLOB(); // TODO: Add parameters here
        liquidatorPanel = new LiquidatorPanel(); // TODO: Add parameters here
        operatorPanel = new OperatorPanel(); // TODO: Add parameters here
        perpManager = new PerpManager(); // TODO: Add parameters here
    }

    /// === MODIFIERS === ///
    /// Prank admin and actor

    modifier asAdmin() {
        vm.prank(address(this));
        _;
    }

    modifier asActor() {
        vm.prank(address(_getActor()));
        _;
    }
}
