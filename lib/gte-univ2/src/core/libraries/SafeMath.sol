pragma solidity 0.8.27;

// a library for performing overflow-safe math, courtesy of DappHub (https://github.com/dapphub/ds-math)

library SafeMath {
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        return x + y;
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        return x - y;
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        return x * y;
    }
}
