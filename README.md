# GTE Perps and Launchpad audit details
- Total Prize Pool: $103,250 in USDC 
  - HM awards: up to $96,000 in USDC
    - If no valid Highs or Mediums are found, the HM pool is $0 
  - QA awards: $4,000 in USDC
  - Judge awards: $3,000 in USDC
  - Scout awards: $250 in USDC
- [Read our guidelines for more details](https://docs.code4rena.com/competitions)
- Starts August 28, 2025 20:00 UTC 
- Ends September 25, 2025 20:00 UTC

**❗ Important notes for wardens** 
1. A coded, runnable PoC is required for all High/Medium submissions to this audit. 
  - This repo includes a basic template to run the test suite.
  - PoCs must use the test suite provided in this repo.
  - Your submission will be marked as Insufficient if the POC is not runnable and working with the provided test suite.
  - Exception: PoC is optional (though recommended) for wardens with signal ≥ 0.68.
1. Judging phase risk adjustments (upgrades/downgrades):
  - High- or Medium-risk submissions downgraded by the judge to Low-risk (QA) will be ineligible for awards.
  - Upgrading a Low-risk finding from a QA report to a Medium- or High-risk finding is not supported.
  - As such, wardens are encouraged to select the appropriate risk level carefully during the submission phase.

## Automated Findings / Publicly Known Issues

The 4naly3er report can be found [here](https://github.com/code-423n4/2025-08-gte-perps/blob/main/4naly3er-report.md).

_Note for C4 wardens: Anything included in this `Automated Findings / Publicly Known Issues` section is considered a publicly known issue and is ineligible for awards._

- Vulnerabilities stemming from manipulating the Index Price (which would come from Oracles and other external off-chain sources) directly (tampering with the Oracle) or indirectly (market manipulation of the underlying asset) will not be considered valid findings for this audit; for all intents and purposes, the Index Price is considered valid.
However, mark price manipulation, as it is a platform-specific construct, are in scope.
Price _history_ manipulation (e.g. tampering historical prices that are already in the platform's storage, Index, Mark or otherwise) are in scope, too.

✅ SCOUTS: Please format the response above 👆 so its not a wall of text and its readable.

# Overview

[ ⭐️ SPONSORS: add info here ]

## Links

- **Previous audits:**  
  - ✅ SCOUTS: If there are multiple report links, please format them in a list.
- **Documentation:** https://docs.gte.xyz/home/
- **Website:** https://www.gte.xyz
- **X/Twitter:** https://x.com/GTE_XYZ
  
---

# Scope

*See [scope.txt](https://github.com/code-423n4/2025-08-gte-perps/blob/main/scope.txt)*

### Files in scope


| File   | Logic Contracts | Interfaces | nSLOC | Purpose | Libraries used |
| ------ | --------------- | ---------- | ----- | -----   | ------------ |
| /contracts/perps/GTL.sol | 1| **** | 199 | |@solady/tokens/ERC4626.sol<br>@solady/utils/EnumerableSetLib.sol<br>@solady/utils/DynamicArrayLib.sol<br>@solady/utils/SafeTransferLib.sol<br>@solady/utils/SafeCastLib.sol<br>@solady/utils/Initializable.sol<br>@solady/auth/OwnableRoles.sol<br>@solady/utils/FixedPointMathLib.sol|
| /contracts/perps/PerpManager.sol | 1| **** | 226 | |@solady/utils/FixedPointMathLib.sol<br>@solady/utils/DynamicArrayLib.sol<br>@solady/utils/SafeCastLib.sol|
| /contracts/perps/modules/AdminPanel.sol | 1| **** | 467 | |@solady/auth/OwnableRoles.sol<br>@solady/utils/FixedPointMathLib.sol<br>@solady/utils/SafeCastLib.sol<br>@solady/utils/Initializable.sol<br>@solady/utils/SignatureCheckerLib.sol|
| /contracts/perps/modules/LiquidatorPanel.sol | 1| **** | 536 | |@solady/auth/OwnableRoles.sol<br>@solady/utils/FixedPointMathLib.sol<br>@solady/utils/DynamicArrayLib.sol<br>@solady/utils/SafeCastLib.sol<br>@solady/utils/EnumerableSetLib.sol<br>@solady/utils/Initializable.sol<br>@solady/utils/SignatureCheckerLib.sol|
| /contracts/perps/modules/ViewPort.sol | 1| **** | 233 | |@solady/auth/OwnableRoles.sol<br>@solady/utils/EnumerableSetLib.sol<br>@solady/utils/DynamicArrayLib.sol<br>@solady/utils/SafeCastLib.sol|
| /contracts/perps/types/BackstopLiquidatorDataLib.sol | 1| **** | 62 | ||
| /contracts/perps/types/Book.sol | 1| **** | 339 | |@solady/utils/FixedPointMathLib.sol|
| /contracts/perps/types/CLOBLib.sol | 1| **** | 420 | |@solady/utils/FixedPointMathLib.sol<br>@solady/utils/SafeCastLib.sol<br>@solady/utils/DynamicArrayLib.sol|
| /contracts/perps/types/ClearingHouse.sol | 1| **** | 431 | |@solady/utils/EnumerableSetLib.sol<br>@solady/utils/DynamicArrayLib.sol<br>@solady/utils/FixedPointMathLib.sol<br>@solady/utils/SafeCastLib.sol|
| /contracts/perps/types/CollateralManager.sol | 1| **** | 72 | |@solady/utils/SafeTransferLib.sol<br>@solady/utils/SafeCastLib.sol<br>@solady/utils/FixedPointMathLib.sol|
| /contracts/perps/types/Constants.sol | 1| **** | 9 | ||
| /contracts/perps/types/Enums.sol | ****| **** | 35 | ||
| /contracts/perps/types/FeeManager.sol | 1| **** | 49 | |@solady/utils/FixedPointMathLib.sol<br>@solady/utils/SafeTransferLib.sol|
| /contracts/perps/types/FundingRateEngine.sol | 1| **** | 80 | |solady/utils/FixedPointMathLib.sol<br>solady/utils/SafeCastLib.sol|
| /contracts/perps/types/InsuranceFund.sol | 1| **** | 37 | |@solady/utils/SafeTransferLib.sol|
| /contracts/perps/types/Market.sol | 1| **** | 398 | |@solady/utils/DynamicArrayLib.sol<br>@solady/utils/FixedPointMathLib.sol<br>@solady/utils/SafeCastLib.sol|
| /contracts/perps/types/Order.sol | 2| **** | 69 | ||
| /contracts/perps/types/PackedFeeRatesLib.sol | 1| **** | 20 | ||
| /contracts/perps/types/Position.sol | 1| **** | 87 | |@solady/utils/FixedPointMathLib.sol<br>@solady/utils/SafeCastLib.sol|
| /contracts/perps/types/PriceHistory.sol | 1| **** | 66 | |@solady/utils/FixedPointMathLib.sol|
| /contracts/perps/types/StorageLib.sol | 1| **** | 121 | ||
| /contracts/perps/types/Structs.sol | ****| **** | 155 | ||
| /contracts/launchpad/BondingCurve.sol | 1| **** | 3 | ||
| /contracts/launchpad/BondingCurves/IBondingCurveMinimal.sol | ****| 1 | 4 | |@openzeppelin/interfaces/IERC165.sol|
| /contracts/launchpad/BondingCurves/SimpleBondingCurve.sol | 1| **** | 120 | |@openzeppelin/interfaces/IERC165.sol<br>@solady/auth/Ownable.sol|
| /contracts/launchpad/Distributor.sol | 1| **** | 123 | |@solady/auth/OwnableRoles.sol<br>@solady/utils/SafeCastLib.sol<br>@solady/utils/SafeTransferLib.sol|
| /contracts/launchpad/LaunchToken.sol | 1| **** | 90 | |@solady/tokens/ERC20.sol|
| /contracts/launchpad/Launchpad.sol | 1| **** | 356 | |@solady/utils/SafeTransferLib.sol<br>@openzeppelin/utils/introspection/ERC165Checker.sol<br>@solady/utils/Initializable.sol<br>@solady/auth/Ownable.sol<br>@solady/utils/ReentrancyGuard.sol<br>contracts/clob/ICLOBManager.sol<br>contracts/utils/OperatorPanel.sol<br>contracts/utils/types/OperatorHelperLib.sol<br>contracts/utils/interfaces/IOperatorPanel.sol<br>contracts/utils/types/EventNonce.sol|
| /contracts/launchpad/LaunchpadLPVault.sol | 1| **** | 17 | |@openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol|
| /contracts/launchpad/libraries/RewardsTracker.sol | 2| **** | 147 | ||
| /contracts/launchpad/uniswap/GTELaunchpadV2Pair.sol | 1| **** | 236 | |@gte-univ2-core/interfaces/IUniswapV2Pair.sol<br>@gte-univ2-core/UniswapV2ERC20.sol<br>@gte-univ2-core/libraries/Math.sol<br>@gte-univ2-core/libraries/UQ112x112.sol<br>@gte-univ2-core/interfaces/IERC20.sol<br>@gte-univ2-core/interfaces/IUniswapV2Factory.sol<br>@gte-univ2-core/interfaces/IUniswapV2Callee.sol|
| /contracts/launchpad/uniswap/GTELaunchpadV2PairFactory.sol | 1| **** | 47 | |@gte-univ2-core/interfaces/IUniswapV2Factory.sol|
| /contracts/launchpad/uniswap/interfaces/IGTELaunchpadV2Pair.sol | ****| 1 | 3 | ||
| /contracts/launchpad/uniswap/interfaces/IUniswapV2Router01.sol | ****| 1 | 3 | ||
| **Totals** | **31** | **3** | **5260** | | |

### Files out of scope

*See [out_of_scope.txt](https://github.com/code-423n4/2025-08-gte-perps/blob/main/out_of_scope.txt)*

| File         |
| ------------ |
| ./contracts/account-manager/AccountManager.sol |
| ./contracts/account-manager/IAccountManager.sol |
| ./contracts/clob/CLOB.sol |
| ./contracts/clob/CLOBManager.sol |
| ./contracts/clob/ICLOB.sol |
| ./contracts/clob/ICLOBManager.sol |
| ./contracts/clob/ILimitLens.sol |
| ./contracts/clob/types/Book.sol |
| ./contracts/clob/types/FeeData.sol |
| ./contracts/clob/types/Order.sol |
| ./contracts/clob/types/RedBlackTree.sol |
| ./contracts/clob/types/Roles.sol |
| ./contracts/clob/types/TransientMakerData.sol |
| ./contracts/launchpad/interfaces/IDistributor.sol |
| ./contracts/launchpad/interfaces/ILaunchpad.sol |
| ./contracts/launchpad/interfaces/IUniV2Factory.sol |
| ./contracts/launchpad/interfaces/IUniswapV2FactoryMinimal.sol |
| ./contracts/launchpad/interfaces/IUniswapV2Pair.sol |
| ./contracts/launchpad/interfaces/IUniswapV2RouterMinimal.sol |
| ./contracts/perps/interfaces/IGTL.sol |
| ./contracts/perps/interfaces/IPerpManager.sol |
| ./contracts/perps/interfaces/IViewPort.sol |
| ./contracts/router/GTERouter.sol |
| ./contracts/router/interfaces/IUniswapV2Router01.sol |
| ./contracts/utils/OperatorHub.sol |
| ./contracts/utils/OperatorPanel.sol |
| ./contracts/utils/interfaces/IOperatorHub.sol |
| ./contracts/utils/interfaces/IOperatorPanel.sol |
| ./contracts/utils/types/EventNonce.sol |
| ./contracts/utils/types/OperatorHelperLib.sol |
| ./script/ScriptProtector.s.sol |
| ./script/helpers/MockUSDC.s.sol |
| ./script/launchpad/Launchpad.s.sol |
| ./script/misc/CreatePerpMarket.s.sol |
| ./script/misc/DeployUniV2Pair.s.sol |
| ./script/perps/DeployPerpManager.s.sol |
| ./script/router_launchpad/RouterLaunchpad.s.sol |
| ./script/router_launchpad/RouterSimpleLaunchpad.s.sol |
| ./script/spot-clob/CLOBManager.s.sol |
| ./script/upgrades/UpgradeAccountManager.s.sol |
| ./script/upgrades/UpgradeBondingCurve.s.sol |
| ./script/upgrades/UpgradeCLOB.s.sol |
| ./script/upgrades/UpgradeCLOBManager.s.sol |
| ./script/upgrades/UpgradeGTL.s.sol |
| ./script/upgrades/UpgradeLaunchpad.s.sol |
| ./script/upgrades/UpgradeLaunchpadLPVault.s.sol |
| ./script/upgrades/UpgradePerpManager.s.sol |
| ./script/upgrades/UpgradeRouter.s.sol |
| ./test/c4-poc/PoC.t.sol |
| ./test/c4-poc/PoCTestBase.t.sol |
| ./test/clob/fuzz/auth/Auth.t.sol |
| ./test/clob/fuzz/clob/CLOBViews.t.sol |
| ./test/clob/fuzz/red-black-tree/RedBlackTree.t.sol |
| ./test/clob/mock/CLOBAnvilFuzzTrader.sol |
| ./test/clob/unit/clob/CLOBAmendIncrease.t.sol |
| ./test/clob/unit/clob/CLOBAmendNewPrice.t.sol |
| ./test/clob/unit/clob/CLOBAmendReduce.t.sol |
| ./test/clob/unit/clob/CLOBAmmendNewSide.t.sol |
| ./test/clob/unit/clob/CLOBCancel.t.sol |
| ./test/clob/unit/clob/CLOBFill.t.sol |
| ./test/clob/unit/clob/CLOBPost.t.sol |
| ./test/clob/unit/clob/CLOBViews.sol |
| ./test/clob/unit/red-black-tree/RedBlackTree.t.sol |
| ./test/clob/unit/types/TransientMakerData.t.sol |
| ./test/clob/utils/CLOBTestBase.sol |
| ./test/cross-platform/PerpSpotTransfers.t.sol |
| ./test/harnesses/ERC20Harness.sol |
| ./test/launchpad/Distributor.t.sol |
| ./test/launchpad/LaunchToken.t.sol |
| ./test/launchpad/Launchpad.t.sol |
| ./test/launchpad/RewardsTracker.t.sol |
| ./test/launchpad/SimpleBondingCurve.t.sol |
| ./test/launchpad/integration/UniV2Bytecode.t.sol |
| ./test/launchpad/uniswap/LaunchpadFeePair.t.sol |
| ./test/live-tests/DeployUniV2Pair.t.sol |
| ./test/live-tests/PerpSimulation.t.sol |
| ./test/live-tests/PostGraduateSwap.t.sol |
| ./test/live-tests/Simulation.t.sol |
| ./test/live-tests/SpotSimulation.t.sol |
| ./test/live-tests/UpgradeBondingCurve.t.sol |
| ./test/live-tests/UpgradeLaunchpad.t.sol |
| ./test/mocks/MockDistributor.sol |
| ./test/mocks/MockLaunchpad.sol |
| ./test/mocks/MockRewardsTracker.sol |
| ./test/mocks/MockTree.sol |
| ./test/mocks/MockUniV2Router.sol |
| ./test/mocks/TransientMakerDataHarness.sol |
| ./test/perps/PerpManagerTestBase.sol |
| ./test/perps/e2e/GTL.t.sol |
| ./test/perps/e2e/PerpAmendLimitOrder.t.sol |
| ./test/perps/e2e/PerpBackstopLiquidation.t.sol |
| ./test/perps/e2e/PerpDeleverage.t.sol |
| ./test/perps/e2e/PerpDelistClose.t.sol |
| ./test/perps/e2e/PerpLeverageUpdate.t.sol |
| ./test/perps/e2e/PerpMarginUpdate.t.sol |
| ./test/perps/e2e/PerpPostFillOrder_Close.t.sol |
| ./test/perps/e2e/PerpPostFillOrder_Decrease.t.sol |
| ./test/perps/e2e/PerpPostFillOrder_Increase.t.sol |
| ./test/perps/e2e/PerpPostFillOrder_Open.t.sol |
| ./test/perps/e2e/PerpPostFillOrder_ReverseOpen.t.sol |
| ./test/perps/e2e/PerpPostLimitOrder.t.sol |
| ./test/perps/e2e/PerpQuoter.t.sol |
| ./test/perps/e2e/PerpStandardLiquidation.t.sol |
| ./test/perps/fail/PerpAmendLimitOrderFail.t.sol |
| ./test/perps/fail/PerpPostLimitOrderFail.t.sol |
| ./test/perps/fail/PerpReduceOnlyCapFail.t.sol |
| ./test/perps/integration/AdminPanel.t.sol |
| ./test/perps/integration/AdminPanelConditionalOrders.t.sol |
| ./test/perps/integration/GTLSubaccountHook.t.sol |
| ./test/perps/integration/PerpCrossMargin.t.sol |
| ./test/perps/integration/PerpDivergenceCap.t.sol |
| ./test/perps/integration/PerpMiscGetters.t.sol |
| ./test/perps/integration/PerpOrderbookNotional.t.sol |
| ./test/perps/integration/PerpPlaceOrderMisc.t.sol |
| ./test/perps/integration/PerpProtatedMargin.t.sol |
| ./test/perps/integration/PerpRebalance.t.sol |
| ./test/perps/mock/BackstopLiquidatorDataHarness.sol |
| ./test/perps/mock/MockAdminPanel.t.sol |
| ./test/perps/mock/MockBackstopLiquidationSettlement.sol |
| ./test/perps/mock/MockPerpManager.sol |
| ./test/perps/mock/MockPriceHistory.sol |
| ./test/perps/mock/PerpAnvilFuzzMaker.sol |
| ./test/perps/mock/PerpAnvilFuzzTrader.sol |
| ./test/perps/mock/PerpFuzzTrader.t.sol |
| ./test/perps/mock/TestUSDC.sol |
| ./test/perps/unit/PerpBackstopLiquidationSettlement.t.sol |
| ./test/perps/unit/PerpBankruptcyPrice.t.sol |
| ./test/perps/unit/PerpManagerAccessControl.t.sol |
| ./test/perps/unit/PerpPositionUpdate.t.sol |
| ./test/perps/unit/PriceHistory.t.sol |
| ./test/perps/unit/types/BackstopLiquidatorDataLib.t.sol |
| ./test/router/RouterUnit.t.sol |
| ./test/router/utils/RouterTestBase.t.sol |
| ./test/utils/OperatorPanel.t.sol |
| Totals: 134 |


# Additional context

## Areas of concern (where to focus for bugs)
- Economical attacks (e.g. engaging large amounts of tokens to break the platform or profit from it) are considered a valid attack vector; we encourage Wardens to look out for ways to generate "bad debt", e.g. negative equity, in a way that would result in net-positive gains for the attacker, or make the platform illiquid. ADL (Auto-De-Leverage) abuses that result in monetary gains for the attacker, are of particular interest to us.

- The Orderbook should be able to process orders at all times; we invite the wardens to look for attacks that would result in a Denial Of Service (e.g. placing an order that cannot be cleared by the ClearingHouse), or that bypasses the limit of orders an User can place in one transaction.

- Any attack that would result in loss of funds for other users, themselves or the Platform's funds, making it illiquid, are of particular interest to us.

✅ SCOUTS: Please format the response above 👆 so its not a wall of text and its readable.

## Main invariants

We define the PerpManager's USDC balance as:
```
sum(all_users_free_collateral_balances[]) + sum(all_users_margin_balances[]) + insurance_Fund_Balance()
```

This should always be equal to the PerpManager's USDC Token balance.

✅ SCOUTS: Please format the response above 👆 so its not a wall of text and its readable.

## All trusted roles in the protocol

- `ADMIN_ROLE`, `LIQUIDATOR_ROLE` and `KEEPER_ROLE`  (in use mainly in the AdminPanel contract) is considered trusted.
- Users that give another user an `OPERATOR` role of any kind, consider that user trusted, too.

✅ SCOUTS: Please format the response above 👆 using the template below👇

| Role                                | Description                       |
| --------------------------------------- | ---------------------------- |
| Owner                          | Has superpowers                |
| Administrator                             | Can change fees                       |

✅ SCOUTS: Please format the response above 👆 so its not a wall of text and its readable.

## Running tests

pre-requisite: the latest version of `foundry` is required to run this project.
https://getfoundry.sh/introduction/installation

Once that is done,

```
$ git clone git@github.com:[Code4rena-repository].git

$ cd gte-contracts

$ forge install

$ forge build
```

✅ SCOUTS: Please format the response above 👆 using the template below👇

```bash
git clone https://github.com/code-423n4/2023-08-arbitrum
git submodule update --init --recursive
cd governance
foundryup
make install
make build
make sc-election-test
```
To run code coverage
```bash
make coverage
```

✅ SCOUTS: Add a screenshot of your terminal showing the test coverage

## Miscellaneous

Employees of GTE and employees' family members are ineligible to participate in this audit.

Code4rena's rules cannot be overridden by the contents of this README. In case of doubt, please check with C4 staff.
