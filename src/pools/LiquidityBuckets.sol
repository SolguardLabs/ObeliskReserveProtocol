// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ObeliskAccess } from "../access/ObeliskAccess.sol";
import { Bucket, BucketState } from "../types/ObeliskTypes.sol";

contract LiquidityBuckets is ObeliskAccess {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint16 internal constant BPS = 10_000;

    mapping(address asset => BucketState state) private _states;

    error BucketsInvalidAsset();
    error BucketsInvalidAmount();
    error BucketsInsufficientLiquidity(address asset, uint256 available, uint256 requested);
    error BucketsInvalidWeights();

    event BucketTargetsSet(
        address indexed asset, uint16 immediate, uint16 deferred, uint16 strategic, uint16 backstop
    );
    event BucketCredited(address indexed asset, Bucket indexed bucket, uint256 amount);
    event BucketDebited(address indexed asset, Bucket indexed bucket, uint256 amount);
    event BucketsConsumed(
        address indexed asset,
        uint256 requested,
        uint256 immediate,
        uint256 deferred,
        uint256 strategic,
        uint256 backstop
    );
    event BucketsRebalanced(
        address indexed asset, Bucket indexed fromBucket, Bucket indexed toBucket, uint256 amount
    );

    constructor(address initialAdmin) ObeliskAccess(initialAdmin) { }

    function setTargets(
        address asset,
        uint16 immediate,
        uint16 deferred,
        uint16 strategic,
        uint16 backstop
    ) external onlyRole(OPERATOR_ROLE) {
        if (asset == address(0)) revert BucketsInvalidAsset();
        if (uint256(immediate) + deferred + strategic + backstop != BPS) {
            revert BucketsInvalidWeights();
        }

        BucketState storage state = _states[asset];
        state.targetImmediateBps = immediate;
        state.targetDeferredBps = deferred;
        state.targetStrategicBps = strategic;
        state.targetBackstopBps = backstop;
        state.lastRebalancedAt = uint48(block.timestamp);
        emit BucketTargetsSet(asset, immediate, deferred, strategic, backstop);
    }

    function credit(address asset, Bucket bucket, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        if (asset == address(0)) revert BucketsInvalidAsset();
        if (amount == 0) revert BucketsInvalidAmount();
        _increase(_states[asset], bucket, amount);
        emit BucketCredited(asset, bucket, amount);
    }

    function creditSplit(
        address asset,
        uint256 immediate,
        uint256 deferred,
        uint256 strategic,
        uint256 backstop
    ) external onlyRole(OPERATOR_ROLE) {
        if (asset == address(0)) revert BucketsInvalidAsset();
        uint256 totalAmount = immediate + deferred + strategic + backstop;
        if (totalAmount == 0) revert BucketsInvalidAmount();

        BucketState storage state = _states[asset];
        if (immediate != 0) {
            state.immediate += immediate;
            emit BucketCredited(asset, Bucket.Immediate, immediate);
        }
        if (deferred != 0) {
            state.deferred += deferred;
            emit BucketCredited(asset, Bucket.Deferred, deferred);
        }
        if (strategic != 0) {
            state.strategic += strategic;
            emit BucketCredited(asset, Bucket.Strategic, strategic);
        }
        if (backstop != 0) {
            state.backstop += backstop;
            emit BucketCredited(asset, Bucket.Backstop, backstop);
        }
    }

    function debit(address asset, Bucket bucket, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        if (amount == 0) revert BucketsInvalidAmount();
        BucketState storage state = _states[asset];
        uint256 available = _bucketBalance(state, bucket);
        if (available < amount) revert BucketsInsufficientLiquidity(asset, available, amount);
        _decrease(state, bucket, amount);
        emit BucketDebited(asset, bucket, amount);
    }

    function consume(address asset, uint256 amount)
        external
        onlyRole(OPERATOR_ROLE)
        returns (uint256 immediate, uint256 deferred, uint256 strategic, uint256 backstop)
    {
        if (amount == 0) revert BucketsInvalidAmount();
        BucketState storage state = _states[asset];
        uint256 available = _total(state);
        if (available < amount) revert BucketsInsufficientLiquidity(asset, available, amount);

        uint256 remaining = amount;
        if (remaining != 0 && state.immediate != 0) {
            immediate = _take(state.immediate, remaining);
            state.immediate -= immediate;
            remaining -= immediate;
        }
        if (remaining != 0 && state.deferred != 0) {
            deferred = _take(state.deferred, remaining);
            state.deferred -= deferred;
            remaining -= deferred;
        }
        if (remaining != 0 && state.strategic != 0) {
            strategic = _take(state.strategic, remaining);
            state.strategic -= strategic;
            remaining -= strategic;
        }
        if (remaining != 0 && state.backstop != 0) {
            backstop = remaining;
            state.backstop -= backstop;
        }

        emit BucketsConsumed(asset, amount, immediate, deferred, strategic, backstop);
    }

    function rebalance(address asset, Bucket fromBucket, Bucket toBucket, uint256 amount)
        external
        onlyRole(OPERATOR_ROLE)
    {
        if (amount == 0) revert BucketsInvalidAmount();
        BucketState storage state = _states[asset];
        uint256 available = _bucketBalance(state, fromBucket);
        if (available < amount) revert BucketsInsufficientLiquidity(asset, available, amount);

        _decrease(state, fromBucket, amount);
        _increase(state, toBucket, amount);
        state.lastRebalancedAt = uint48(block.timestamp);
        emit BucketsRebalanced(asset, fromBucket, toBucket, amount);
    }

    function stateOf(address asset) external view returns (BucketState memory) {
        return _states[asset];
    }

    function bucketBalance(address asset, Bucket bucket) external view returns (uint256) {
        return _bucketBalance(_states[asset], bucket);
    }

    function total(address asset) public view returns (uint256) {
        return _total(_states[asset]);
    }

    function availableForRedemption(address asset) external view returns (uint256) {
        BucketState memory state = _states[asset];
        return state.immediate + state.deferred + state.strategic + state.backstop;
    }

    function targetAmount(address asset, Bucket bucket) external view returns (uint256) {
        BucketState memory state = _states[asset];
        uint256 balance = _total(state);
        if (bucket == Bucket.Immediate) return balance * state.targetImmediateBps / BPS;
        if (bucket == Bucket.Deferred) return balance * state.targetDeferredBps / BPS;
        if (bucket == Bucket.Strategic) return balance * state.targetStrategicBps / BPS;
        return balance * state.targetBackstopBps / BPS;
    }

    function utilizationBps(address asset, Bucket bucket) external view returns (uint256) {
        BucketState memory state = _states[asset];
        uint256 balance = _total(state);
        if (balance == 0) return 0;
        return _bucketBalance(state, bucket) * BPS / balance;
    }

    function _increase(BucketState storage state, Bucket bucket, uint256 amount) internal {
        if (bucket == Bucket.Immediate) state.immediate += amount;
        else if (bucket == Bucket.Deferred) state.deferred += amount;
        else if (bucket == Bucket.Strategic) state.strategic += amount;
        else state.backstop += amount;
    }

    function _decrease(BucketState storage state, Bucket bucket, uint256 amount) internal {
        if (bucket == Bucket.Immediate) state.immediate -= amount;
        else if (bucket == Bucket.Deferred) state.deferred -= amount;
        else if (bucket == Bucket.Strategic) state.strategic -= amount;
        else state.backstop -= amount;
    }

    function _bucketBalance(BucketState memory state, Bucket bucket)
        internal
        pure
        returns (uint256)
    {
        if (bucket == Bucket.Immediate) return state.immediate;
        if (bucket == Bucket.Deferred) return state.deferred;
        if (bucket == Bucket.Strategic) return state.strategic;
        return state.backstop;
    }

    function _total(BucketState memory state) internal pure returns (uint256) {
        return state.immediate + state.deferred + state.strategic + state.backstop;
    }

    function _take(uint256 available, uint256 requested) internal pure returns (uint256) {
        return available < requested ? available : requested;
    }
}
