// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library WadMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant HALF_WAD = 0.5e18;

    error WadDivisionByZero();

    function mulWadDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return x * y / WAD;
    }

    function mulWadUp(uint256 x, uint256 y) internal pure returns (uint256) {
        if (x == 0 || y == 0) return 0;
        return (x * y + WAD - 1) / WAD;
    }

    function divWadDown(uint256 x, uint256 y) internal pure returns (uint256) {
        if (y == 0) revert WadDivisionByZero();
        return x * WAD / y;
    }

    function divWadUp(uint256 x, uint256 y) internal pure returns (uint256) {
        if (y == 0) revert WadDivisionByZero();
        if (x == 0) return 0;
        return (x * WAD + y - 1) / y;
    }

    function toWad(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        if (decimals < 18) return amount * (10 ** (18 - decimals));
        return amount / (10 ** (decimals - 18));
    }

    function fromWad(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        if (decimals < 18) return amount / (10 ** (18 - decimals));
        return amount * (10 ** (decimals - 18));
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function sqrt(uint256 x) internal pure returns (uint256 z) {
        if (x == 0) return 0;
        uint256 y = x;
        z = 1;
        if (y >= 0x100000000000000000000000000000000) {
            y >>= 128;
            z <<= 64;
        }
        if (y >= 0x10000000000000000) {
            y >>= 64;
            z <<= 32;
        }
        if (y >= 0x100000000) {
            y >>= 32;
            z <<= 16;
        }
        if (y >= 0x10000) {
            y >>= 16;
            z <<= 8;
        }
        if (y >= 0x100) {
            y >>= 8;
            z <<= 4;
        }
        if (y >= 0x10) {
            y >>= 4;
            z <<= 2;
        }
        if (y >= 0x8) z <<= 1;

        z = (z + x / z) >> 1;
        z = (z + x / z) >> 1;
        z = (z + x / z) >> 1;
        z = (z + x / z) >> 1;
        z = (z + x / z) >> 1;
        z = (z + x / z) >> 1;
        z = (z + x / z) >> 1;
        uint256 roundedDown = x / z;
        return z < roundedDown ? z : roundedDown;
    }
}
