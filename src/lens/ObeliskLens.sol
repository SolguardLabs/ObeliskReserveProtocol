// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { DebtBook } from "../core/DebtBook.sol";
import { ObeliskReservePool } from "../core/ObeliskReservePool.sol";
import { ReserveRegistry } from "../core/ReserveRegistry.sol";
import { LiquidityBuckets } from "../pools/LiquidityBuckets.sol";
import { RedemptionQueue } from "../modules/RedemptionQueue.sol";
import {
    AssetRiskSnapshot,
    BucketState,
    PositionView,
    QueueStats,
    SolvencySnapshot
} from "../types/ObeliskTypes.sol";

contract ObeliskLens {
    ObeliskReservePool public immutable reservePool;
    ReserveRegistry public immutable registry;
    DebtBook public immutable debtBook;
    LiquidityBuckets public immutable buckets;
    RedemptionQueue public immutable queue;

    constructor(
        ObeliskReservePool reservePool_,
        ReserveRegistry registry_,
        DebtBook debtBook_,
        LiquidityBuckets buckets_,
        RedemptionQueue queue_
    ) {
        reservePool = reservePool_;
        registry = registry_;
        debtBook = debtBook_;
        buckets = buckets_;
        queue = queue_;
    }

    function protocolSnapshot() external view returns (SolvencySnapshot memory) {
        return reservePool.solvencySnapshot();
    }

    function assetSnapshots() external view returns (AssetRiskSnapshot[] memory snapshots) {
        uint256 count = registry.assetCount();
        snapshots = new AssetRiskSnapshot[](count);
        for (uint256 i = 0; i < count; ++i) {
            address asset = registry.assetAt(i);
            snapshots[i] = registry.snapshot(asset, buckets.total(asset));
        }
    }

    function assetSnapshot(address asset) external view returns (AssetRiskSnapshot memory) {
        return registry.snapshot(asset, buckets.total(asset));
    }

    function bucketState(address asset) external view returns (BucketState memory) {
        return buckets.stateOf(asset);
    }

    function position(uint256 id) external view returns (PositionView memory) {
        return reservePool.positionView(id);
    }

    function positionsOf(address owner) external view returns (PositionView[] memory views_) {
        uint256[] memory ids = debtBook.positionsOf(owner);
        views_ = new PositionView[](ids.length);
        for (uint256 i = 0; i < ids.length; ++i) {
            views_[i] = reservePool.positionView(ids[i]);
        }
    }

    function queueStats() external view returns (QueueStats memory) {
        return queue.queueStats();
    }

    function previewAccount(address owner)
        external
        view
        returns (
            uint256 positionCount,
            uint256 totalCollateralValue,
            uint256 totalDebt,
            uint256 weakestHealthBps
        )
    {
        uint256[] memory ids = debtBook.positionsOf(owner);
        positionCount = ids.length;
        weakestHealthBps = type(uint256).max;
        for (uint256 i = 0; i < ids.length; ++i) {
            PositionView memory view_ = reservePool.positionView(ids[i]);
            totalCollateralValue += view_.collateralValue;
            totalDebt += view_.debt;
            if (view_.healthBps < weakestHealthBps) weakestHealthBps = view_.healthBps;
        }
        if (ids.length == 0) weakestHealthBps = 0;
    }

    function reserveComposition(address asset)
        external
        view
        returns (
            uint256 immediate,
            uint256 deferred_,
            uint256 strategic,
            uint256 backstop,
            uint256 total
        )
    {
        BucketState memory state = buckets.stateOf(asset);
        immediate = state.immediate;
        deferred_ = state.deferred;
        strategic = state.strategic;
        backstop = state.backstop;
        total = immediate + deferred_ + strategic + backstop;
    }
}
