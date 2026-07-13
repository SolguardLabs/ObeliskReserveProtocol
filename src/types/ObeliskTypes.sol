// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

enum Bucket {
    Immediate,
    Deferred,
    Strategic,
    Backstop
}

enum TicketStatus {
    None,
    Pending,
    Executed,
    Cancelled,
    Expired
}

struct AssetConfig {
    bool enabled;
    uint8 decimals;
    bytes32 oracleId;
    uint16 mintLtvBps;
    uint16 liquidationBps;
    uint16 redemptionFeeBps;
    uint16 reserveBufferBps;
    uint256 depositCap;
    uint256 issuanceCap;
    uint256 minMint;
    uint16[4] bucketWeightsBps;
}

struct AssetRiskSnapshot {
    address asset;
    uint256 price;
    uint256 reserveAmount;
    uint256 reserveValue;
    uint256 issuanceCap;
    uint256 depositCap;
    uint16 mintLtvBps;
    uint16 redemptionFeeBps;
    bool enabled;
}

struct BucketState {
    uint256 immediate;
    uint256 deferred;
    uint256 strategic;
    uint256 backstop;
    uint16 targetImmediateBps;
    uint16 targetDeferredBps;
    uint16 targetStrategicBps;
    uint16 targetBackstopBps;
    uint48 lastRebalancedAt;
}

struct BucketDelta {
    Bucket bucket;
    uint256 beforeAmount;
    uint256 afterAmount;
}

struct PositionView {
    uint256 id;
    address owner;
    address asset;
    uint256 collateralAmount;
    uint256 collateralValue;
    uint256 debt;
    uint256 maxDebt;
    uint256 healthBps;
    bool active;
}

struct RedemptionTicket {
    uint256 id;
    address requester;
    address receiver;
    address asset;
    uint256 stableAmount;
    uint256 minOut;
    uint256 assetOut;
    uint48 createdAt;
    uint48 executableAt;
    uint48 deadline;
    TicketStatus status;
}

struct QueueStats {
    uint256 nextTicketId;
    uint256 pendingTickets;
    uint256 pendingStable;
    uint256 executedStable;
    uint256 cancelledStable;
    uint256 expiredStable;
    uint48 executionDelay;
}

struct SolvencySnapshot {
    uint256 activeSupply;
    uint256 reserveValue;
    uint256 reserveRatioBps;
    uint256 targetRatioBps;
    uint256 totalDebt;
    uint256 totalCollateralValue;
    bool mintingAllowed;
}

struct RecapitalizationReceipt {
    address asset;
    address provider;
    uint256 amount;
    uint256 sharesBurned;
    uint48 timestamp;
}
