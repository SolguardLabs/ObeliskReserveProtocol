// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Pure portfolio scenarios for dashboards and operational planning.
contract ReserveStressEngine {
    uint256 internal constant BPS = 10_000;
    uint256 internal constant MAX_ASSETS = 32;

    error InvalidPortfolio();
    error InvalidTarget();
    error InvalidHaircut(uint256 index, uint256 haircutBps);

    struct Scenario {
        uint256 grossValue;
        uint256 stressedValue;
        uint256 stressedRatioBps;
        uint256 requiredAtTarget;
        uint256 shortfallAtTarget;
        uint256 concentrationBps;
    }

    function assess(
        uint256[] calldata values,
        uint16[] calldata haircutBps,
        uint256 supply,
        uint16 targetBps
    ) external pure returns (Scenario memory result) {
        if (values.length == 0 || values.length > MAX_ASSETS || values.length != haircutBps.length)
        {
            revert InvalidPortfolio();
        }
        if (targetBps < BPS || targetBps > 25_000) revert InvalidTarget();

        for (uint256 i; i < values.length; ++i) {
            if (haircutBps[i] > BPS) revert InvalidHaircut(i, haircutBps[i]);
            result.grossValue += values[i];
            result.stressedValue += values[i] * (BPS - haircutBps[i]) / BPS;
        }
        if (result.grossValue == 0) revert InvalidPortfolio();

        for (uint256 i; i < values.length; ++i) {
            uint256 weightBps = values[i] * BPS / result.grossValue;
            result.concentrationBps += weightBps * weightBps / BPS;
        }

        result.requiredAtTarget = supply * targetBps / BPS;
        if (result.stressedValue < result.requiredAtTarget) {
            result.shortfallAtTarget = result.requiredAtTarget - result.stressedValue;
        }
        result.stressedRatioBps =
            supply == 0 ? type(uint256).max : result.stressedValue * BPS / supply;
    }

    function quoteWaterfall(uint256[4] calldata balances, uint256 requested)
        external
        pure
        returns (uint256[4] memory useByBucket, uint256 shortfall)
    {
        uint256 remaining = requested;
        for (uint256 i; i < 4; ++i) {
            uint256 draw = remaining < balances[i] ? remaining : balances[i];
            useByBucket[i] = draw;
            remaining -= draw;
        }
        shortfall = remaining;
    }
}
