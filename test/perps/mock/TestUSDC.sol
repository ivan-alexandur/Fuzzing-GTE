// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {ERC20} from "@solady/tokens/ERC20.sol";

contract TestUSDC is ERC20 {
    function name() public pure override returns (string memory) {
        return "USD Coin";
    }

    function symbol() public pure override returns (string memory) {
        return "USDC";
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
