// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Bucket, BucketState } from "../types/ObeliskTypes.sol";

library BucketMath {
    uint256 internal constant BPS = 10_000;

    struct BucketTargets {
        uint256 immediate;
        uint256 deferred;
        uint256 strategic;
        uint256 backstop;
    }

    struct BucketImbalance {
        Bucket bucket;
        uint256 current;
        uint256 target;
        uint256 deficit;
        uint256 surplus;
    }

    struct RebalancePlan {
        Bucket fromBucket;
        Bucket toBucket;
        uint256 amount;
        bool needed;
    }

    error BucketMathInvalidWeights();

    function total(BucketState memory state) internal pure returns (uint256) {
        return state.immediate + state.deferred + state.strategic + state.backstop;
    }

    function validateTargets(BucketState memory state) internal pure {
        uint256 sum = uint256(state.targetImmediateBps) + uint256(state.targetDeferredBps)
            + uint256(state.targetStrategicBps) + uint256(state.targetBackstopBps);
        if (sum != BPS) revert BucketMathInvalidWeights();
    }

    function targets(BucketState memory state) internal pure returns (BucketTargets memory result) {
        validateTargets(state);
        uint256 balance = total(state);
        result.immediate = balance * state.targetImmediateBps / BPS;
        result.deferred = balance * state.targetDeferredBps / BPS;
        result.strategic = balance * state.targetStrategicBps / BPS;
        result.backstop = balance - result.immediate - result.deferred - result.strategic;
    }

    function imbalance(BucketState memory state)
        internal
        pure
        returns (BucketImbalance[4] memory rows)
    {
        BucketTargets memory target = targets(state);
        rows[0] = _row(Bucket.Immediate, state.immediate, target.immediate);
        rows[1] = _row(Bucket.Deferred, state.deferred, target.deferred);
        rows[2] = _row(Bucket.Strategic, state.strategic, target.strategic);
        rows[3] = _row(Bucket.Backstop, state.backstop, target.backstop);
    }

    function largestSurplus(BucketState memory state)
        internal
        pure
        returns (Bucket bucket, uint256 amount)
    {
        BucketImbalance[4] memory rows = imbalance(state);
        for (uint256 i = 0; i < rows.length; ++i) {
            if (rows[i].surplus > amount) {
                bucket = rows[i].bucket;
                amount = rows[i].surplus;
            }
        }
    }

    function largestDeficit(BucketState memory state)
        internal
        pure
        returns (Bucket bucket, uint256 amount)
    {
        BucketImbalance[4] memory rows = imbalance(state);
        for (uint256 i = 0; i < rows.length; ++i) {
            if (rows[i].deficit > amount) {
                bucket = rows[i].bucket;
                amount = rows[i].deficit;
            }
        }
    }

    function nextPlan(BucketState memory state) internal pure returns (RebalancePlan memory plan) {
        (Bucket fromBucket, uint256 surplus) = largestSurplus(state);
        (Bucket toBucket, uint256 deficit) = largestDeficit(state);
        if (surplus == 0 || deficit == 0) return plan;
        plan = RebalancePlan({
            fromBucket: fromBucket,
            toBucket: toBucket,
            amount: surplus < deficit ? surplus : deficit,
            needed: true
        });
    }

    function bucketShareBps(BucketState memory state, Bucket bucket)
        internal
        pure
        returns (uint256)
    {
        uint256 balance = total(state);
        if (balance == 0) return 0;
        if (bucket == Bucket.Immediate) return state.immediate * BPS / balance;
        if (bucket == Bucket.Deferred) return state.deferred * BPS / balance;
        if (bucket == Bucket.Strategic) return state.strategic * BPS / balance;
        return state.backstop * BPS / balance;
    }

    function _row(Bucket bucket, uint256 current, uint256 target)
        private
        pure
        returns (BucketImbalance memory row)
    {
        row.bucket = bucket;
        row.current = current;
        row.target = target;
        if (current < target) row.deficit = target - current;
        else row.surplus = current - target;
    }
}
