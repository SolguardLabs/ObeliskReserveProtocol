// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { PercentageMath } from "./PercentageMath.sol";
import { WadMath } from "./WadMath.sol";

library ReserveMath {
    using PercentageMath for uint256;

    uint256 internal constant WAD = 1e18;

    error ReserveMathZeroPrice();
    error ReserveMathZeroRatio();

    function assetValue(uint256 amount, uint8 decimals, uint256 priceWad)
        internal
        pure
        returns (uint256)
    {
        if (priceWad == 0) revert ReserveMathZeroPrice();
        return WadMath.toWad(amount, decimals) * priceWad / WAD;
    }

    function assetAmount(uint256 valueWad, uint8 decimals, uint256 priceWad)
        internal
        pure
        returns (uint256)
    {
        if (priceWad == 0) revert ReserveMathZeroPrice();
        uint256 amountWad = valueWad * WAD / priceWad;
        return WadMath.fromWad(amountWad, decimals);
    }

    function assetAmountUp(uint256 valueWad, uint8 decimals, uint256 priceWad)
        internal
        pure
        returns (uint256)
    {
        if (priceWad == 0) revert ReserveMathZeroPrice();
        uint256 amountWad = valueWad == 0 ? 0 : (valueWad * WAD + priceWad - 1) / priceWad;
        if (decimals == 18) return amountWad;
        if (decimals < 18) {
            uint256 scalar = 10 ** (18 - decimals);
            return amountWad == 0 ? 0 : (amountWad + scalar - 1) / scalar;
        }
        return amountWad * (10 ** (decimals - 18));
    }

    function maxDebtFromCollateral(uint256 collateralValue, uint256 mintLtvBps)
        internal
        pure
        returns (uint256)
    {
        return collateralValue.percentMulDown(mintLtvBps);
    }

    function requiredCollateralValue(uint256 debt, uint256 ltvBps) internal pure returns (uint256) {
        if (ltvBps == 0) revert ReserveMathZeroRatio();
        return debt.percentDiv(ltvBps);
    }

    function collateralRatioBps(uint256 collateralValue, uint256 debt)
        internal
        pure
        returns (uint256)
    {
        return PercentageMath.ratioBps(collateralValue, debt);
    }

    function applyFee(uint256 value, uint256 feeBps)
        internal
        pure
        returns (uint256 netValue, uint256 fee)
    {
        fee = value.percentMulDown(feeBps);
        netValue = value - fee;
    }

    function splitByWeights(uint256 amount, uint16[4] memory weights)
        internal
        pure
        returns (uint256 immediate, uint256 deferred, uint256 strategic, uint256 backstop)
    {
        uint256 totalWeight = uint256(weights[0]) + uint256(weights[1]) + uint256(weights[2])
            + uint256(weights[3]);
        if (totalWeight == 0) {
            immediate = amount;
            return (immediate, 0, 0, 0);
        }

        immediate = amount * weights[0] / totalWeight;
        deferred = amount * weights[1] / totalWeight;
        strategic = amount * weights[2] / totalWeight;
        backstop = amount - immediate - deferred - strategic;
    }

    function weightedAverageBps(uint256 a, uint256 weightA, uint256 b, uint256 weightB)
        internal
        pure
        returns (uint256)
    {
        uint256 total = weightA + weightB;
        if (total == 0) return 0;
        return (a * weightA + b * weightB) / total;
    }
}
