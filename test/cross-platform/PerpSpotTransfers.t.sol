// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {TestPlus} from "lib/solady/test/utils/TestPlus.sol";
import {ERC1967Factory} from "@solady/utils/ERC1967Factory.sol";
import {console} from "forge-std/console.sol";

import {PerpManager} from "contracts/perps/PerpManager.sol";
import {SpotOperatorRoles, PerpsOperatorRoles} from "contracts/utils/OperatorPanel.sol";
import {OperatorHelperLib} from "contracts/utils/types/OperatorHelperLib.sol";
import {AccountManager} from "contracts/account-manager/AccountManager.sol";
import {TestUSDC} from "../perps/mock/TestUSDC.sol";
import {CollateralManagerLib} from "contracts/perps/types/CollateralManager.sol";

contract PerpSpotTransfersTest is Test, TestPlus {
    struct Params {
        address user;
        address operator;
        uint256 amount;
    }

    PerpManager public perpManager;
    AccountManager public accountManager;
    ERC1967Factory internal factory;
    Params internal params;

    TestUSDC internal usdc = TestUSDC(0xE9b6e75C243B6100ffcb1c66e8f78F96FeeA727F);

    bytes32 internal constant ETH = bytes32("ETH");
    bytes32 internal constant GTE = bytes32("GTE");
    bytes32 internal constant BTC = bytes32("BTC");

    address internal admin = makeAddr("admin");

    uint16 internal constant MAKER_BASE_FEE_RATE = 1000;
    uint16 internal constant TAKER_BASE_FEE_RATE = 2000;

    uint16[] internal takerFees;
    uint16[] internal makerFees;

    function setUp() public {
        factory = new ERC1967Factory();

        deployCodeTo("TestUSDC.sol", 0xE9b6e75C243B6100ffcb1c66e8f78F96FeeA727F);

        takerFees.push(TAKER_BASE_FEE_RATE);
        makerFees.push(MAKER_BASE_FEE_RATE);

        bytes32 accountManagerSalt = bytes32(abi.encodePacked(address(this), bytes12(keccak256("ACCOUNT_MANAGER"))));
        bytes32 perpsManagerSalt = bytes32(abi.encodePacked(address(this), bytes12(keccak256("PERPS_MANAGER"))));

        address predictedAccountManager = factory.predictDeterministicAddress(accountManagerSalt);
        address predictedPerpsManager = factory.predictDeterministicAddress(perpsManagerSalt);

        address perpManagerLogic = address(new PerpManager(predictedAccountManager, address(0)));
        address accountManagerLogic = address(
            new AccountManager({
                _gteRouter: address(0),
                _clobManager: address(0),
                _operatorHub: address(0),
                _spotMakerFees: makerFees,
                _spotTakerFees: takerFees,
                _perpManager: predictedPerpsManager
            })
        );

        perpManager = PerpManager(factory.deployDeterministic(perpManagerLogic, admin, perpsManagerSalt));
        accountManager = AccountManager(
            factory.deployDeterministicAndCall(
                accountManagerLogic, admin, accountManagerSalt, abi.encodeCall(AccountManager.initialize, (admin))
            )
        );

        assertEq(address(perpManager), predictedPerpsManager, "perpManager deployed at wrong address");
        assertEq(address(accountManager), predictedAccountManager, "accountManager deployed at wrong address");
    }

    function test_depositFromPerpsToSpot(uint256) public {
        params.user = _randomNonZeroAddress();
        params.amount = _hem(_random(), 1e18, 1_000_000e18);

        _mintAndApproveTo(params.user, address(perpManager), params.amount);

        vm.startPrank(params.user);
        perpManager.deposit(params.user, params.amount);

        vm.expectEmit(true, true, true, true);
        emit AccountManager.AccountCredited(1, params.user, address(usdc), params.amount);
        accountManager.depositFromPerps(params.user, params.amount);
        vm.stopPrank();
    }

    function test_depositFromPerpsToSpot_fromOperator(uint256) public {
        params.user = _randomUniqueNonZeroAddress();
        params.operator = _randomUniqueNonZeroAddress();
        params.amount = _hem(_random(), 1e18, 1_000_000e18);

        _mintAndApproveTo(params.user, address(perpManager), params.amount);

        vm.startPrank(params.user);
        perpManager.deposit(params.user, params.amount);
        accountManager.approveOperator(
            params.user, params.operator, 1 << uint256(SpotOperatorRoles.PERP_TO_SPOT_DEPOSIT)
        );
        vm.stopPrank();

        vm.prank(params.operator);
        vm.expectEmit(true, true, true, true);
        emit AccountManager.AccountCredited(2, params.user, address(usdc), params.amount);
        accountManager.depositFromPerps(params.user, params.amount);
    }

    function test_depositFromPerpsToSpot_revert_NotOperator(uint256) public {
        params.user = _randomUniqueNonZeroAddress();
        params.operator = _randomUniqueNonZeroAddress();
        params.amount = _hem(_random(), 1e18, 1_000_000e18);

        _mintAndApproveTo(params.user, address(perpManager), params.amount);

        vm.prank(params.user);
        perpManager.deposit(params.user, params.amount);

        vm.prank(params.operator);
        vm.expectRevert(OperatorHelperLib.OperatorDoesNotHaveRole.selector);
        accountManager.depositFromPerps(params.user, params.amount);
    }

    function test_depositFromPerpsToSpot_revert_InsufficientBalance(uint256) public {
        params.user = _randomUniqueNonZeroAddress();
        params.amount = _hem(_random(), 1e18, 1_000_000e18);

        vm.prank(params.user);
        vm.expectRevert(CollateralManagerLib.InsufficientBalance.selector);
        accountManager.depositFromPerps(params.user, params.amount);
    }

    function test_withdrawToPerps_revert_NotPerpManager(uint256) public {
        params.user = _randomNonZeroAddress();
        params.amount = _hem(_random(), 1e18, 1_000_000e18);

        vm.prank(params.user);
        vm.expectRevert(AccountManager.NotPerpManager.selector);
        accountManager.withdrawToPerps(params.user, params.amount);
    }

    function test_depositFromSpotToPerps(uint256) public {
        params.user = _randomNonZeroAddress();
        params.amount = _hem(_random(), 1e18, 1_000_000e18);

        _mintAndApproveTo(params.user, address(accountManager), params.amount);

        vm.startPrank(params.user);
        accountManager.deposit(params.user, address(usdc), params.amount);

        vm.expectEmit(true, true, true, true);
        emit CollateralManagerLib.Deposit(params.user, params.amount);
        perpManager.depositFromSpot(params.user, params.amount);
        vm.stopPrank();
    }

    function test_depositFromSpotToPerps_fromOperator(uint256) public {
        params.user = _randomUniqueNonZeroAddress();
        params.operator = _randomUniqueNonZeroAddress();
        params.amount = _hem(_random(), 1e18, 1_000_000e18);

        _mintAndApproveTo(params.user, address(accountManager), params.amount);

        vm.startPrank(params.user);
        accountManager.deposit(params.user, address(usdc), params.amount);
        perpManager.approveOperator(params.user, params.operator, 1 << uint256(PerpsOperatorRoles.SPOT_TO_PERP_DEPOSIT));
        vm.stopPrank();

        vm.prank(params.operator);
        vm.expectEmit(true, true, true, true);
        emit CollateralManagerLib.Deposit(params.user, params.amount);
        perpManager.depositFromSpot(params.user, params.amount);
    }

    function test_depositFromSpotToPerps_revert_NotOperator(uint256) public {
        params.user = _randomUniqueNonZeroAddress();
        params.operator = _randomUniqueNonZeroAddress();
        params.amount = _hem(_random(), 1e18, 1_000_000e18);

        _mintAndApproveTo(params.user, address(accountManager), params.amount);

        vm.prank(params.user);
        accountManager.deposit(params.user, address(usdc), params.amount);

        vm.prank(params.operator);
        vm.expectRevert(OperatorHelperLib.OperatorDoesNotHaveRole.selector);
        perpManager.depositFromSpot(params.user, params.amount);
    }

    function test_depositFromSpotToPerps_revert_InsufficientBalance(uint256) public {
        params.user = _randomUniqueNonZeroAddress();
        params.amount = _hem(_random(), 1e18, 1_000_000e18);

        vm.prank(params.user);
        vm.expectRevert(AccountManager.BalanceInsufficient.selector);
        perpManager.depositFromSpot(params.user, params.amount);
    }

    function test_withdrawToSpot_revert_NotPerpManager(uint256) public {
        params.user = _randomNonZeroAddress();
        params.amount = _hem(_random(), 1e18, 1_000_000e18);

        vm.prank(params.user);
        vm.expectRevert(PerpManager.NotAccountManager.selector);
        perpManager.withdrawToSpot(params.user, params.amount);
    }

    function _mintAndApproveTo(address user, address to, uint256 amount) internal {
        vm.startPrank(user);
        usdc.mint(user, amount);
        usdc.approve(address(to), amount);
        vm.stopPrank();
    }
}
