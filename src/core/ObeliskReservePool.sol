// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ObeliskAccess } from "../access/ObeliskAccess.sol";
import { DebtBook } from "./DebtBook.sol";
import { ReserveRegistry } from "./ReserveRegistry.sol";
import { BackstopPool } from "../pools/BackstopPool.sol";
import { LiquidityBuckets } from "../pools/LiquidityBuckets.sol";
import { IERC20, IObeliskUSD, IRedemptionSettlement } from "../interfaces/IObelisk.sol";
import { PercentageMath } from "../libraries/PercentageMath.sol";
import { ReserveMath } from "../libraries/ReserveMath.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";
import { Bucket, AssetConfig, PositionView, SolvencySnapshot } from "../types/ObeliskTypes.sol";

contract ObeliskReservePool is ObeliskAccess, IRedemptionSettlement {
    using PercentageMath for uint256;
    using SafeTransferLib for IERC20;

    bytes32 public constant REDEMPTION_ROLE = keccak256("REDEMPTION_ROLE");
    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");
    bytes32 public constant RECAPITALIZER_ROLE = keccak256("RECAPITALIZER_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    IObeliskUSD public immutable stablecoin;
    ReserveRegistry public immutable registry;
    DebtBook public immutable debtBook;
    LiquidityBuckets public immutable buckets;

    BackstopPool public backstopPool;
    address public treasury;
    uint16 public reserveTargetBps;
    uint16 public mintFeeBps;
    bool public mintingPaused;

    mapping(address asset => uint256 amount) public issuedByAsset;
    uint256 public cumulativeMinted;
    uint256 public cumulativeBurned;
    uint256 public cumulativeRedeemed;
    uint256 public cumulativeRecapitalized;

    error ReservePoolInvalidAddress();
    error ReservePoolInvalidAmount();
    error ReservePoolInvalidReceiver();
    error ReservePoolMintingPaused();
    error ReservePoolBelowMinimumMint(uint256 requested, uint256 minimum);
    error ReservePoolIssuanceCapExceeded(address asset, uint256 requested, uint256 cap);
    error ReservePoolDepositCapExceeded(address asset, uint256 requested, uint256 cap);
    error ReservePoolPositionUnhealthy(uint256 id, uint256 debt, uint256 maxDebt);
    error ReservePoolCoverageTooLow(uint256 ratioBps, uint256 targetBps);
    error ReservePoolSlippage(uint256 actual, uint256 minimum);
    error ReservePoolBackstopMissing();
    error ReservePoolInvalidPolicy();

    event PositionCreated(
        uint256 indexed id,
        address indexed owner,
        address indexed asset,
        uint256 collateralAmount,
        uint256 minted
    );
    event CollateralAdded(uint256 indexed id, address indexed asset, uint256 amount);
    event CollateralWithdrawn(
        uint256 indexed id, address indexed asset, address indexed receiver, uint256 amount
    );
    event StableMinted(uint256 indexed id, address indexed receiver, uint256 amount, uint256 fee);
    event StableBurned(uint256 indexed id, address indexed payer, uint256 amount);
    event RedemptionFulfilled(
        address indexed asset, address indexed receiver, uint256 stableAmount, uint256 assetOut
    );
    event Recapitalized(
        address indexed asset, uint256 amount, uint256 backstopSharesBurned, address indexed caller
    );
    event ReservePolicyUpdated(uint16 reserveTargetBps, uint16 mintFeeBps);
    event TreasuryUpdated(address indexed treasury);
    event BackstopUpdated(address indexed backstop);
    event MintingPaused(bool paused);

    constructor(
        address initialAdmin,
        IObeliskUSD stablecoin_,
        ReserveRegistry registry_,
        DebtBook debtBook_,
        LiquidityBuckets buckets_,
        address treasury_
    ) ObeliskAccess(initialAdmin) {
        if (
            address(stablecoin_) == address(0) || address(registry_) == address(0)
                || address(debtBook_) == address(0) || address(buckets_) == address(0)
                || treasury_ == address(0)
        ) revert ReservePoolInvalidAddress();

        stablecoin = stablecoin_;
        registry = registry_;
        debtBook = debtBook_;
        buckets = buckets_;
        treasury = treasury_;
        reserveTargetBps = 12_500;
    }

    function setBackstopPool(BackstopPool newBackstop) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(newBackstop) == address(0)) revert ReservePoolInvalidAddress();
        backstopPool = newBackstop;
        emit BackstopUpdated(address(newBackstop));
    }

    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTreasury == address(0)) revert ReservePoolInvalidAddress();
        treasury = newTreasury;
        emit TreasuryUpdated(newTreasury);
    }

    function setReservePolicy(uint16 newReserveTargetBps, uint16 newMintFeeBps)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (newReserveTargetBps < 10_000 || newReserveTargetBps > 25_000 || newMintFeeBps > 1000) {
            revert ReservePoolInvalidPolicy();
        }
        reserveTargetBps = newReserveTargetBps;
        mintFeeBps = newMintFeeBps;
        emit ReservePolicyUpdated(newReserveTargetBps, newMintFeeBps);
    }

    function setMintingPaused(bool paused) external onlyRole(GUARDIAN_ROLE) {
        mintingPaused = paused;
        emit MintingPaused(paused);
    }

    function openPosition(
        address asset,
        uint256 collateralAmount,
        uint256 mintAmount,
        address receiver
    ) external returns (uint256 id) {
        if (receiver == address(0)) revert ReservePoolInvalidReceiver();
        AssetConfig memory config = registry.requireEnabled(asset);
        _receiveCollateral(asset, collateralAmount, config);

        id = debtBook.openPosition(msg.sender, asset);
        debtBook.increaseCollateral(id, collateralAmount);
        if (mintAmount != 0) _mintAgainstPosition(id, mintAmount, receiver, config);

        emit PositionCreated(id, msg.sender, asset, collateralAmount, mintAmount);
    }

    function addCollateral(uint256 id, uint256 amount) external {
        debtBook.requirePositionOwner(id, msg.sender);
        address asset = debtBook.positionAsset(id);
        AssetConfig memory config = registry.requireEnabled(asset);
        _receiveCollateral(asset, amount, config);
        debtBook.increaseCollateral(id, amount);
        emit CollateralAdded(id, asset, amount);
    }

    function withdrawCollateral(uint256 id, uint256 amount, address receiver) external {
        if (receiver == address(0)) revert ReservePoolInvalidReceiver();
        if (amount == 0) revert ReservePoolInvalidAmount();
        debtBook.requirePositionOwner(id, msg.sender);

        address asset = debtBook.positionAsset(id);
        AssetConfig memory config = registry.requireEnabled(asset);
        debtBook.decreaseCollateral(id, amount);
        _assertPositionHealthy(id, config);

        buckets.consume(asset, amount);
        IERC20(asset).safeTransfer(receiver, amount);
        emit CollateralWithdrawn(id, asset, receiver, amount);
    }

    function mintStable(uint256 id, uint256 amount, address receiver) external {
        if (receiver == address(0)) revert ReservePoolInvalidReceiver();
        debtBook.requirePositionOwner(id, msg.sender);
        address asset = debtBook.positionAsset(id);
        AssetConfig memory config = registry.requireEnabled(asset);
        _mintAgainstPosition(id, amount, receiver, config);
    }

    function burnStable(uint256 id, uint256 amount) external returns (uint256 burned) {
        debtBook.requirePositionOwner(id, msg.sender);
        uint256 debt = debtBook.debtOf(id);
        burned = amount == type(uint256).max ? debt : amount;
        if (burned == 0) revert ReservePoolInvalidAmount();

        IERC20(address(stablecoin)).safeTransferFrom(msg.sender, address(this), burned);
        stablecoin.burn(burned);
        debtBook.decreaseDebt(id, burned);

        address asset = debtBook.positionAsset(id);
        unchecked {
            issuedByAsset[asset] -= burned;
        }
        cumulativeBurned += burned;
        emit StableBurned(id, msg.sender, burned);
    }

    function closePosition(uint256 id, address receiver) external {
        if (receiver == address(0)) revert ReservePoolInvalidReceiver();
        debtBook.requirePositionOwner(id, msg.sender);
        DebtBook.Position memory position = debtBook.position(id);
        if (position.debt != 0) revert ReservePoolPositionUnhealthy(id, position.debt, 0);

        uint256 collateral = position.collateralAmount;
        if (collateral != 0) {
            debtBook.decreaseCollateral(id, collateral);
            buckets.consume(position.asset, collateral);
            IERC20(position.asset).safeTransfer(receiver, collateral);
        }
        debtBook.closePosition(id);
        emit CollateralWithdrawn(id, position.asset, receiver, collateral);
    }

    function fulfillRedemption(
        address asset,
        uint256 stableAmount,
        address receiver,
        uint256 minOut
    ) external onlyRole(REDEMPTION_ROLE) returns (uint256 assetOut) {
        if (receiver == address(0)) revert ReservePoolInvalidReceiver();
        if (stableAmount == 0) revert ReservePoolInvalidAmount();

        AssetConfig memory config = registry.requireEnabled(asset);
        (uint256 netValue,) = ReserveMath.applyFee(stableAmount, config.redemptionFeeBps);
        assetOut = registry.amountForValue(asset, netValue);
        if (assetOut < minOut) revert ReservePoolSlippage(assetOut, minOut);

        buckets.consume(asset, assetOut);
        IERC20(asset).safeTransfer(receiver, assetOut);
        cumulativeRedeemed += stableAmount;
        emit RedemptionFulfilled(asset, receiver, stableAmount, assetOut);
    }

    function recapitalize(address asset, uint256 amount)
        external
        onlyRole(RECAPITALIZER_ROLE)
        returns (uint256 sharesBurned)
    {
        if (address(backstopPool) == address(0)) {
            revert ReservePoolBackstopMissing();
        }
        registry.requireEnabled(asset);
        sharesBurned = backstopPool.provide(asset, amount, address(this));
        buckets.credit(asset, Bucket.Backstop, amount);
        cumulativeRecapitalized += amount;
        emit Recapitalized(asset, amount, sharesBurned, msg.sender);
    }

    function rebalanceBuckets(address asset, Bucket fromBucket, Bucket toBucket, uint256 amount)
        external
        onlyRole(ALLOCATOR_ROLE)
    {
        registry.requireEnabled(asset);
        buckets.rebalance(asset, fromBucket, toBucket, amount);
    }

    function totalReserveValue() public view returns (uint256 value) {
        uint256 count = registry.assetCount();
        for (uint256 i = 0; i < count; ++i) {
            address asset = registry.assetAt(i);
            uint256 amount = buckets.total(asset);
            if (amount != 0) value += registry.valueOf(asset, amount);
        }
    }

    function visibleReserveRatioBps() public view returns (uint256) {
        uint256 activeSupply = stablecoin.totalSupply();
        if (activeSupply == 0) return type(uint256).max;
        return PercentageMath.ratioBps(totalReserveValue(), activeSupply);
    }

    function positionHealthBps(uint256 id) public view returns (uint256) {
        DebtBook.Position memory position = debtBook.position(id);
        if (position.debt == 0) return type(uint256).max;
        uint256 value = registry.valueOf(position.asset, position.collateralAmount);
        return PercentageMath.ratioBps(value, position.debt);
    }

    function maxMintable(uint256 id) public view returns (uint256) {
        DebtBook.Position memory position = debtBook.position(id);
        AssetConfig memory config = registry.configOf(position.asset);
        uint256 value = registry.valueOf(position.asset, position.collateralAmount);
        uint256 maxDebt = ReserveMath.maxDebtFromCollateral(value, config.mintLtvBps);
        if (maxDebt <= position.debt) return 0;
        return maxDebt - position.debt;
    }

    function previewRedemption(address asset, uint256 stableAmount)
        external
        view
        returns (uint256 assetOut, uint256 feeValue)
    {
        AssetConfig memory config = registry.configOf(asset);
        uint256 netValue;
        (netValue, feeValue) = ReserveMath.applyFee(stableAmount, config.redemptionFeeBps);
        assetOut = registry.amountForValue(asset, netValue);
    }

    function positionView(uint256 id) external view returns (PositionView memory result) {
        DebtBook.Position memory position = debtBook.position(id);
        AssetConfig memory config = registry.configOf(position.asset);
        uint256 value = registry.valueOf(position.asset, position.collateralAmount);
        uint256 maxDebt = ReserveMath.maxDebtFromCollateral(value, config.mintLtvBps);
        uint256 health =
            position.debt == 0 ? type(uint256).max : PercentageMath.ratioBps(value, position.debt);
        result = PositionView({
            id: id,
            owner: position.owner,
            asset: position.asset,
            collateralAmount: position.collateralAmount,
            collateralValue: value,
            debt: position.debt,
            maxDebt: maxDebt,
            healthBps: health,
            active: position.active
        });
    }

    function solvencySnapshot() external view returns (SolvencySnapshot memory snapshot) {
        uint256 activeSupply = stablecoin.totalSupply();
        uint256 reserveValue = totalReserveValue();
        uint256 ratio = activeSupply == 0
            ? type(uint256).max
            : PercentageMath.ratioBps(reserveValue, activeSupply);
        snapshot = SolvencySnapshot({
            activeSupply: activeSupply,
            reserveValue: reserveValue,
            reserveRatioBps: ratio,
            targetRatioBps: reserveTargetBps,
            totalDebt: debtBook.totalDebt(),
            totalCollateralValue: totalCollateralValue(),
            mintingAllowed: !mintingPaused && ratio >= reserveTargetBps
        });
    }

    function totalCollateralValue() public view returns (uint256 value) {
        uint256 count = registry.assetCount();
        for (uint256 i = 0; i < count; ++i) {
            address asset = registry.assetAt(i);
            uint256 amount = debtBook.totalCollateralOfAsset(asset);
            if (amount != 0) value += registry.valueOf(asset, amount);
        }
    }

    function _receiveCollateral(address asset, uint256 amount, AssetConfig memory config) internal {
        if (amount == 0) revert ReservePoolInvalidAmount();
        uint256 currentReserves = buckets.total(asset);
        if (currentReserves + amount > config.depositCap) {
            revert ReservePoolDepositCapExceeded(asset, currentReserves + amount, config.depositCap);
        }

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        (uint256 immediate, uint256 deferred, uint256 strategic, uint256 backstop) =
            ReserveMath.splitByWeights(amount, config.bucketWeightsBps);
        buckets.creditSplit(asset, immediate, deferred, strategic, backstop);
    }

    function _mintAgainstPosition(
        uint256 id,
        uint256 amount,
        address receiver,
        AssetConfig memory config
    ) internal {
        if (mintingPaused) revert ReservePoolMintingPaused();
        if (amount == 0) revert ReservePoolInvalidAmount();
        if (amount < config.minMint) revert ReservePoolBelowMinimumMint(amount, config.minMint);

        DebtBook.Position memory position = debtBook.position(id);
        uint256 fee = amount.percentMulDown(mintFeeBps);
        uint256 debtIncrease = amount + fee;
        uint256 newDebt = position.debt + debtIncrease;
        uint256 newIssued = issuedByAsset[position.asset] + debtIncrease;
        if (newIssued > config.issuanceCap) {
            revert ReservePoolIssuanceCapExceeded(position.asset, newIssued, config.issuanceCap);
        }

        uint256 collateralValue = registry.valueOf(position.asset, position.collateralAmount);
        uint256 maxDebt = ReserveMath.maxDebtFromCollateral(collateralValue, config.mintLtvBps);
        if (newDebt > maxDebt) revert ReservePoolPositionUnhealthy(id, newDebt, maxDebt);
        _assertVisibleCoverage(debtIncrease);

        debtBook.increaseDebt(id, debtIncrease);
        issuedByAsset[position.asset] = newIssued;
        stablecoin.mint(receiver, amount);
        if (fee != 0) stablecoin.mint(treasury, fee);
        cumulativeMinted += debtIncrease;
        emit StableMinted(id, receiver, amount, fee);
    }

    function _assertPositionHealthy(uint256 id, AssetConfig memory config) internal view {
        DebtBook.Position memory position = debtBook.position(id);
        if (position.debt == 0) return;
        uint256 value = registry.valueOf(position.asset, position.collateralAmount);
        uint256 maxDebt = ReserveMath.maxDebtFromCollateral(value, config.mintLtvBps);
        if (position.debt > maxDebt) {
            revert ReservePoolPositionUnhealthy(id, position.debt, maxDebt);
        }
    }

    function _assertVisibleCoverage(uint256 supplyIncrease) internal view {
        uint256 activeSupplyAfter = stablecoin.totalSupply() + supplyIncrease;
        if (activeSupplyAfter == 0) return;
        uint256 ratio = PercentageMath.ratioBps(totalReserveValue(), activeSupplyAfter);
        if (ratio < reserveTargetBps) revert ReservePoolCoverageTooLow(ratio, reserveTargetBps);
    }
}
