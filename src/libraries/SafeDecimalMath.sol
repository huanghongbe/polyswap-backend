// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

library SafeDecimalMath {
    uint256 private constant UNIT = 10 ** 18;

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeDecimalMath: addition overflow");
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeDecimalMath: subtraction overflow");
        uint256 c = a - b;
        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0;
        }
        uint256 c = a * b / UNIT;
        require(c >= a, "SafeDecimalMath: multiplication overflow");
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeDecimalMath: division by zero");
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
