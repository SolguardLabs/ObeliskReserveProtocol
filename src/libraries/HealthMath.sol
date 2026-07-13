// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library HealthMath {
    uint256 internal constant BPS = 10_000;

    enum HealthBand {
        Empty,
        Critical,
        Warning,
        Healthy,
        Surplus
    }

    struct HealthInput {
        uint256 reserveValue;
        uint256 supply;
        uint256 minimumRatioBps;
        uint256 targetRatioBps;
        uint256 surplusRatioBps;
    }

    struct HealthReport {
        uint256 ratioBps;
        uint256 requiredAtMinimum;
        uint256 requiredAtTarget;
        uint256 deficitToMinimum;
        uint256 deficitToTarget;
        uint256 surplusAboveTarget;
        HealthBand band;
    }

    error HealthInvalidRatio();

    function report(HealthInput memory input) internal pure returns (HealthReport memory out) {
        if (
            input.minimumRatioBps < BPS || input.targetRatioBps < input.minimumRatioBps
                || input.surplusRatioBps < input.targetRatioBps
        ) revert HealthInvalidRatio();

        out.ratioBps = ratio(input.reserveValue, input.supply);
        out.requiredAtMinimum = required(input.supply, input.minimumRatioBps);
        out.requiredAtTarget = required(input.supply, input.targetRatioBps);
        out.deficitToMinimum = deficit(input.reserveValue, out.requiredAtMinimum);
        out.deficitToTarget = deficit(input.reserveValue, out.requiredAtTarget);
        out.surplusAboveTarget = surplus(input.reserveValue, out.requiredAtTarget);
        out.band = classify(
            out.ratioBps, input.minimumRatioBps, input.targetRatioBps, input.surplusRatioBps
        );
    }

    function classify(
        uint256 ratioBps_,
        uint256 minimumRatioBps,
        uint256 targetRatioBps,
        uint256 surplusRatioBps
    ) internal pure returns (HealthBand) {
        if (ratioBps_ == 0) return HealthBand.Empty;
        if (ratioBps_ < minimumRatioBps) return HealthBand.Critical;
        if (ratioBps_ < targetRatioBps) return HealthBand.Warning;
        if (ratioBps_ < surplusRatioBps) return HealthBand.Healthy;
        return HealthBand.Surplus;
    }

    function required(uint256 supply, uint256 ratioBps_) internal pure returns (uint256) {
        return supply * ratioBps_ / BPS;
    }

    function ratio(uint256 value, uint256 supply) internal pure returns (uint256) {
        if (supply == 0) return value == 0 ? BPS : type(uint256).max;
        return value * BPS / supply;
    }

    function deficit(uint256 value, uint256 target) internal pure returns (uint256) {
        return value < target ? target - value : 0;
    }

    function surplus(uint256 value, uint256 target) internal pure returns (uint256) {
        return value > target ? value - target : 0;
    }

    function recapAmountForTarget(uint256 reserveValue, uint256 supply, uint256 targetRatioBps)
        internal
        pure
        returns (uint256)
    {
        uint256 target = required(supply, targetRatioBps);
        return deficit(reserveValue, target);
    }

    function maxRedeemableAgainstTarget(
        uint256 reserveValue,
        uint256 supply,
        uint256 targetRatioBps
    ) internal pure returns (uint256) {
        uint256 target = required(supply, targetRatioBps);
        return reserveValue > target ? reserveValue - target : 0;
    }

    function clampRatio(uint256 ratioBps_, uint256 floorBps, uint256 ceilingBps)
        internal
        pure
        returns (uint256)
    {
        if (ratioBps_ < floorBps) return floorBps;
        if (ratioBps_ > ceilingBps) return ceilingBps;
        return ratioBps_;
    }

    function weightedRatio(
        uint256 firstRatioBps,
        uint256 firstWeight,
        uint256 secondRatioBps,
        uint256 secondWeight
    ) internal pure returns (uint256) {
        uint256 totalWeight = firstWeight + secondWeight;
        if (totalWeight == 0) return 0;
        return (firstRatioBps * firstWeight + secondRatioBps * secondWeight) / totalWeight;
    }
}
