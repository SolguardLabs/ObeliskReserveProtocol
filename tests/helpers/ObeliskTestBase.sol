// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";

import { DebtBook } from "../../src/core/DebtBook.sol";
import { ObeliskReservePool } from "../../src/core/ObeliskReservePool.sol";
import { ReserveRegistry } from "../../src/core/ReserveRegistry.sol";
import { ObeliskLens } from "../../src/lens/ObeliskLens.sol";
import { RedemptionQueue } from "../../src/modules/RedemptionQueue.sol";
import { ReserveOracle } from "../../src/oracle/ReserveOracle.sol";
import { BackstopPool } from "../../src/pools/BackstopPool.sol";
import { LiquidityBuckets } from "../../src/pools/LiquidityBuckets.sol";
import { ObeliskUSD } from "../../src/token/ObeliskUSD.sol";
import { AssetConfig } from "../../src/types/ObeliskTypes.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

abstract contract ObeliskTestBase is Test {
    bytes32 internal constant USDC_ORACLE_ID = keccak256("USDC/USD");
    uint256 internal constant USDC_PRICE = 1e18;
    uint256 internal constant USER_USDC = 5_000_000 * 1e6;
    uint256 internal constant LP_USDC = 2_000_000 * 1e6;
    uint48 internal constant REDEMPTION_DELAY = 1 days;

    address internal alice;
    address internal bob;
    address internal carol;
    address internal keeper;
    address internal treasury;
    address internal lp;

    MockERC20 internal usdc;
    ObeliskUSD internal stablecoin;
    ReserveOracle internal oracle;
    ReserveRegistry internal registry;
    DebtBook internal debtBook;
    LiquidityBuckets internal buckets;
    BackstopPool internal backstop;
    ObeliskReservePool internal reservePool;
    RedemptionQueue internal queue;
    ObeliskLens internal lens;

    function setUp() public virtual {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");
        keeper = makeAddr("keeper");
        treasury = makeAddr("treasury");
        lp = makeAddr("lp");

        usdc = new MockERC20("Reserve USD Coin", "rUSDC", 6);
        stablecoin = new ObeliskUSD(address(this));

        oracle = new ReserveOracle(address(this));
        oracle.grantRole(oracle.REPORTER_ROLE(), address(this));
        oracle.grantRole(oracle.GUARDIAN_ROLE(), address(this));
        oracle.configureFeed(USDC_ORACLE_ID, 3 days, 0.95e18, 1.05e18);
        oracle.reportPrice(USDC_ORACLE_ID, USDC_PRICE);

        registry = new ReserveRegistry(address(this), oracle);
        registry.grantRole(registry.RISK_ROLE(), address(this));
        registry.registerAsset(address(usdc), _usdcConfig());

        debtBook = new DebtBook(address(this));
        buckets = new LiquidityBuckets(address(this));
        backstop = new BackstopPool(address(this));
        reservePool = new ObeliskReservePool(
            address(this), stablecoin, registry, debtBook, buckets, treasury
        );
        queue = new RedemptionQueue(address(this), stablecoin, reservePool, REDEMPTION_DELAY);
        lens = new ObeliskLens(reservePool, registry, debtBook, buckets, queue);

        stablecoin.grantRole(stablecoin.MINTER_ROLE(), address(reservePool));
        stablecoin.grantRole(stablecoin.MINTER_ROLE(), address(queue));
        debtBook.grantRole(debtBook.POOL_ROLE(), address(reservePool));
        buckets.grantRole(buckets.OPERATOR_ROLE(), address(reservePool));
        buckets.grantRole(buckets.OPERATOR_ROLE(), address(this));
        reservePool.grantRole(reservePool.REDEMPTION_ROLE(), address(queue));
        reservePool.grantRole(reservePool.RECAPITALIZER_ROLE(), address(this));
        reservePool.grantRole(reservePool.GUARDIAN_ROLE(), address(this));
        reservePool.grantRole(reservePool.ALLOCATOR_ROLE(), address(this));
        reservePool.setBackstopPool(backstop);

        backstop.grantRole(backstop.ASSET_MANAGER_ROLE(), address(this));
        backstop.grantRole(backstop.RESERVE_POOL_ROLE(), address(reservePool));
        backstop.setAssetEnabled(address(usdc), true);

        queue.grantRole(queue.KEEPER_ROLE(), keeper);
        queue.grantRole(queue.GUARDIAN_ROLE(), address(this));
        buckets.setTargets(address(usdc), 5500, 2500, 1500, 500);

        _prepareUser(alice);
        _prepareUser(bob);
        _prepareUser(carol);
        usdc.mint(lp, LP_USDC);
        vm.prank(lp);
        usdc.approve(address(backstop), type(uint256).max);
    }

    function _usdcConfig() internal pure returns (AssetConfig memory config) {
        config = AssetConfig({
            enabled: true,
            decimals: 6,
            oracleId: USDC_ORACLE_ID,
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

    function _prepareUser(address account) internal {
        usdc.mint(account, USER_USDC);
        vm.startPrank(account);
        usdc.approve(address(reservePool), type(uint256).max);
        stablecoin.approve(address(reservePool), type(uint256).max);
        stablecoin.approve(address(queue), type(uint256).max);
        vm.stopPrank();
    }

    function _open(address account, uint256 collateralAmount, uint256 mintAmount)
        internal
        returns (uint256 id)
    {
        vm.prank(account);
        id = reservePool.openPosition(address(usdc), collateralAmount, mintAmount, account);
    }

    function _request(
        address account,
        uint256 stableAmount,
        uint256 minOut,
        address receiver,
        uint48 lifetime
    ) internal returns (uint256 id) {
        vm.prank(account);
        id = queue.requestRedemption(
            address(usdc), stableAmount, minOut, receiver, uint48(block.timestamp) + lifetime
        );
    }
}
