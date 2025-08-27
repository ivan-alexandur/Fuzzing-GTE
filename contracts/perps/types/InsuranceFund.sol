// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";

import {Constants} from "./Constants.sol";

struct InsuranceFund {
    uint256 balance;
}

using InsuranceFundLib for InsuranceFund global;

library InsuranceFundLib {
    using SafeTransferLib for address;

    address constant USDC = Constants.USDC;

    event InsuranceFundWithdrawal(address indexed account, uint256 amount);
    event InsuranceFundDeposit(address indexed account, uint256 amount);

    error InsufficientInsuranceFundBalance();

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               INSURANCE
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function pay(InsuranceFund storage self, uint256 amount) internal {
        if (amount == 0) return;
        self.balance += amount;
    }

    function claim(InsuranceFund storage self, uint256 amount) internal {
        if (amount == 0) return;
        if (self.balance < amount) revert InsufficientInsuranceFundBalance();
        self.balance -= amount;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                 ADMIN
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function withdraw(InsuranceFund storage self, uint256 amount) internal {
        if (self.balance < amount) revert InsufficientInsuranceFundBalance();
        self.balance -= amount;
        USDC.safeTransfer(msg.sender, amount);
        emit InsuranceFundWithdrawal(msg.sender, amount);
    }

    function deposit(InsuranceFund storage self, uint256 amount) internal {
        self.balance += amount;
        USDC.safeTransferFrom(msg.sender, address(this), amount);
        emit InsuranceFundDeposit(msg.sender, amount);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                GETTERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function getBalance(InsuranceFund storage self) internal view returns (uint256) {
        return self.balance;
    }
}
