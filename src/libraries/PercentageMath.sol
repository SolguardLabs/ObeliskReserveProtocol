// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library PercentageMath {
    uint256 internal constant BPS = 10_000;
    uint256 internal constant HALF_BPS = 5000;

    error PercentageAboveOneHundredPercent(uint256 value);
    error PercentageDivisionByZero();

    function validateBps(uint256 value) internal pure {
        if (value > BPS) revert PercentageAboveOneHundredPercent(value);
    }

    function percentMul(uint256 value, uint256 bps) internal pure returns (uint256) {
        if (value == 0 || bps == 0) return 0;
        validateBps(bps);
        return (value * bps + HALF_BPS) / BPS;
    }

    function percentMulDown(uint256 value, uint256 bps) internal pure returns (uint256) {
        if (value == 0 || bps == 0) return 0;
        validateBps(bps);
        return value * bps / BPS;
    }

    function percentMulUp(uint256 value, uint256 bps) internal pure returns (uint256) {
        if (value == 0 || bps == 0) return 0;
        validateBps(bps);
        return (value * bps + BPS - 1) / BPS;
    }

    function percentDiv(uint256 value, uint256 bps) internal pure returns (uint256) {
        if (bps == 0) revert PercentageDivisionByZero();
        validateBps(bps);
        return (value * BPS + bps / 2) / bps;
    }

    function ratioBps(uint256 numerator, uint256 denominator) internal pure returns (uint256) {
        if (denominator == 0) return type(uint256).max;
        return numerator * BPS / denominator;
    }
}
