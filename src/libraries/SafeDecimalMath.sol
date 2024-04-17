// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

library SafeDecimalMath {
    uint256 private constant UNIT = 10 ** 18;

    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "division by zero");
        uint256 c = a * UNIT / b;
        return c;
    }

    function pow(uint256 base, uint256 exponent) internal pure returns (uint256) {
        if (exponent == 0) {
            return 1;
        }
        uint256 result = base;
        for (uint256 i = 1; i < exponent; i++) {
            result *= base;
        }
        return result;
    }
}
