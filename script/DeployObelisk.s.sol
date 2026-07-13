// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";

import { DebtBook } from "../src/core/DebtBook.sol";
import { ObeliskReservePool } from "../src/core/ObeliskReservePool.sol";
import { ReserveRegistry } from "../src/core/ReserveRegistry.sol";
import { ObeliskLens } from "../src/lens/ObeliskLens.sol";
import { RedemptionQueue } from "../src/modules/RedemptionQueue.sol";
import { ReserveOracle } from "../src/oracle/ReserveOracle.sol";
import { BackstopPool } from "../src/pools/BackstopPool.sol";
import { LiquidityBuckets } from "../src/pools/LiquidityBuckets.sol";
import { ObeliskUSD } from "../src/token/ObeliskUSD.sol";
import { AssetConfig } from "../src/types/ObeliskTypes.sol";

contract DeployObelisk is Script {
    bytes32 internal constant RESERVE_ORACLE_ID = keccak256("RESERVE/USD");

    function run()
        external
        returns (
            ObeliskUSD stablecoin,
            ReserveOracle oracle,
            ReserveRegistry registry,
            DebtBook debtBook,
            LiquidityBuckets buckets,
            BackstopPool backstop,
            ObeliskReservePool reservePool,
            RedemptionQueue queue,
            ObeliskLens lens
        )
    {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(deployerKey);
        address treasury = vm.envOr("TREASURY", admin);
        address reserveAsset = vm.envAddress("RESERVE_ASSET");

        vm.startBroadcast(deployerKey);

        stablecoin = new ObeliskUSD(admin);
        oracle = new ReserveOracle(admin);
        registry = new ReserveRegistry(admin, oracle);
        debtBook = new DebtBook(admin);
        buckets = new LiquidityBuckets(admin);
        backstop = new BackstopPool(admin);
        reservePool =
            new ObeliskReservePool(admin, stablecoin, registry, debtBook, buckets, treasury);
        queue = new RedemptionQueue(admin, stablecoin, reservePool, 1 days);
        lens = new ObeliskLens(reservePool, registry, debtBook, buckets, queue);

        stablecoin.grantRole(stablecoin.MINTER_ROLE(), address(reservePool));
        stablecoin.grantRole(stablecoin.MINTER_ROLE(), address(queue));
        oracle.grantRole(oracle.REPORTER_ROLE(), admin);
        oracle.grantRole(oracle.GUARDIAN_ROLE(), admin);
        registry.grantRole(registry.RISK_ROLE(), admin);
        debtBook.grantRole(debtBook.POOL_ROLE(), address(reservePool));
        buckets.grantRole(buckets.OPERATOR_ROLE(), address(reservePool));
        buckets.grantRole(buckets.OPERATOR_ROLE(), admin);
        backstop.grantRole(backstop.ASSET_MANAGER_ROLE(), admin);
        backstop.grantRole(backstop.RESERVE_POOL_ROLE(), address(reservePool));
        reservePool.grantRole(reservePool.REDEMPTION_ROLE(), address(queue));
        reservePool.grantRole(reservePool.ALLOCATOR_ROLE(), admin);
        reservePool.grantRole(reservePool.RECAPITALIZER_ROLE(), admin);
        reservePool.grantRole(reservePool.GUARDIAN_ROLE(), admin);
        queue.grantRole(queue.KEEPER_ROLE(), admin);
        queue.grantRole(queue.GUARDIAN_ROLE(), admin);

        oracle.configureFeed(RESERVE_ORACLE_ID, 3 days, 0.95e18, 1.05e18);
        oracle.reportPrice(RESERVE_ORACLE_ID, 1e18);
        registry.registerAsset(reserveAsset, _reserveConfig());
        buckets.setTargets(reserveAsset, 5500, 2500, 1500, 500);
        backstop.setAssetEnabled(reserveAsset, true);
        reservePool.setBackstopPool(backstop);

        vm.stopBroadcast();
    }

    function _reserveConfig() internal pure returns (AssetConfig memory config) {
        config = AssetConfig({
            enabled: true,
            decimals: 6,
            oracleId: RESERVE_ORACLE_ID,
            mintLtvBps: 7500,
            liquidationBps: 8500,
            redemptionFeeBps: 20,
            reserveBufferBps: 1000,
            depositCap: 50_000_000 * 1e6,
            issuanceCap: 30_000_000 ether,
            minMint: 100 ether,
            bucketWeightsBps: [uint16(5500), uint16(2500), uint16(1500), uint16(500)]
        });
    }
}
