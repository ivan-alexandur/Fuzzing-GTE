// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

import {MakerSettleData, TakerSettleData, LiquidateeSettleData} from "./Structs.sol";
import {Constants} from "./Constants.sol";

struct CollateralManager {
    mapping(address account => mapping(uint256 subaccount => int256)) margin;
    mapping(address account => uint256) freeCollateral; // collateral not tied to any subaccount
}

using CollateralManagerLib for CollateralManager global;

library CollateralManagerLib {
    using SafeTransferLib for address;
    using SafeCastLib for uint256;
    using FixedPointMathLib for *;

    address constant USDC = Constants.USDC;

    event Deposit(address indexed account, uint256 amount);
    event Withdraw(address indexed account, uint256 amount);

    error InsufficientBalance();
    error BadDebt();

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                           DEPOSIT / WITHDRAW
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function depositFreeCollateral(CollateralManager storage self, address from, address to, uint256 amount) internal {
        USDC.safeTransferFrom(from, address(this), amount);
        self.creditAccount(to, amount);
        emit Deposit(to, amount);
    }

    function withdrawFreeCollateral(CollateralManager storage self, address account, uint256 amount) internal {
        self.debitAccount(account, amount);
        USDC.safeTransfer(account, amount);
        emit Withdraw(account, amount);
    }

    function depositFromSpot(CollateralManager storage self, address account, uint256 amount) internal {
        self.creditAccount(account, amount);
        emit Deposit(account, amount);
    }

    function withdrawToSpot(CollateralManager storage self, address account, uint256 amount, address accountManager)
        internal
    {
        self.debitAccount(account, amount);
        USDC.safeTransfer(accountManager, amount);
        emit Withdraw(account, amount);
    }

    function settleMarginUpdate(
        CollateralManager storage self,
        address account,
        uint256 subaccount,
        int256 marginDelta,
        int256 fundingPayment
    ) internal returns (int256 remainingMargin) {
        remainingMargin = self.margin[account][subaccount] += marginDelta - fundingPayment;

        self.handleCollateralDelta(account, marginDelta);
    }

    function settleNewLeverage(
        CollateralManager storage self,
        address account,
        uint256 subaccount,
        int256 collateralDeltaFromBook,
        int256 newMargin,
        int256 fundingPayment
    ) internal returns (int256 collateralDelta) {
        int256 currentMargin = self.margin[account][subaccount] - fundingPayment;

        int256 collateralDeltaFromPosition = newMargin - currentMargin;

        collateralDelta = collateralDeltaFromPosition + collateralDeltaFromBook;

        self.handleCollateralDelta(account, collateralDelta);

        self.margin[account][subaccount] = newMargin;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                 TAKER
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function settleFill(
        CollateralManager storage self,
        address account,
        uint256 subaccount,
        int256 margin,
        int256 marginDelta
    ) internal {
        self.margin[account][subaccount] = margin;

        self.handleCollateralDelta(account, marginDelta);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               ACCOUNT
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function creditAccount(CollateralManager storage self, address account, uint256 amount) internal {
        self.freeCollateral[account] += amount;
    }

    function debitAccount(CollateralManager storage self, address account, uint256 amount) internal {
        if (self.freeCollateral[account] < amount) revert InsufficientBalance();
        self.freeCollateral[account] -= amount;
    }

    function handleCollateralDelta(CollateralManager storage self, address account, int256 collateralDelta) internal {
        if (collateralDelta > 0) self.debitAccount(account, collateralDelta.abs());
        else if (collateralDelta < 0) self.creditAccount(account, collateralDelta.abs());
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               GETTERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function getFreeCollateralBalance(CollateralManager storage self, address account)
        internal
        view
        returns (uint256)
    {
        return self.freeCollateral[account];
    }

    function getMarginBalance(CollateralManager storage self, address account, uint256 subaccount)
        internal
        view
        returns (int256)
    {
        return self.margin[account][subaccount];
    }
}
