// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/Script.sol";

import {ERC1967Factory} from "@solady/utils/ERC1967Factory.sol";
import {PerpManager} from "contracts/perps/PerpManager.sol";
import {AdminPanel} from "contracts/perps/modules/AdminPanel.sol";

contract DeployPerpManagerScript is Script {
    ERC1967Factory factory;

    uint16 internal constant MAKER_BASE_FEE_RATE = 1000;
    uint16 internal constant TAKER_BASE_FEE_RATE = 2000;

    uint16[] internal takerFees;
    uint16[] internal makerFees;

    function run() external {
        address deployer = vm.envAddress("DEPLOYER");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        // address operatorHub = vm.envAddress("OPERATOR_HUB_TESTNET");
        // address spotAccountManager = vm.envAddress("SPOT_ACCOUNT_MANAGER_TESTNET");

        factory = ERC1967Factory(vm.envAddress("GTE_FACTORY_TESTNET"));

        takerFees.push(TAKER_BASE_FEE_RATE);
        makerFees.push(MAKER_BASE_FEE_RATE);

        vm.createSelectFork("testnet");
        vm.startBroadcast(deployerPrivateKey);

        address perpManagerLogic = address(new PerpManager(address(0), address(0)));

        (bool s, bytes memory d) = address(factory).call{gas: 8_000_000}(
            abi.encodeCall(
                ERC1967Factory.deployAndCall,
                (perpManagerLogic, deployer, abi.encodeCall(AdminPanel.initialize, (deployer, takerFees, makerFees)))
            )
        );

        vm.stopBroadcast();

        require(s, "deploy failed");

        PerpManager perpManager = abi.decode(d, (PerpManager));

        console.log("perp manager:", address(perpManager));
    }
}
