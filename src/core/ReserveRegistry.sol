// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ObeliskAccess } from "../access/ObeliskAccess.sol";
import { IReserveOracle } from "../interfaces/IObelisk.sol";
import { PercentageMath } from "../libraries/PercentageMath.sol";
import { ReserveMath } from "../libraries/ReserveMath.sol";
import { AssetConfig, AssetRiskSnapshot } from "../types/ObeliskTypes.sol";

contract ReserveRegistry is ObeliskAccess {
    using PercentageMath for uint256;

    bytes32 public constant RISK_ROLE = keccak256("RISK_ROLE");

    IReserveOracle public immutable oracle;

    address[] private _assets;
    mapping(address asset => AssetConfig config) private _configs;
    mapping(address asset => bool listed) private _listed;

    error RegistryAssetNotListed(address asset);
    error RegistryAssetAlreadyListed(address asset);
    error RegistryAssetDisabled(address asset);
    error RegistryInvalidAsset();
    error RegistryInvalidDecimals(uint8 decimals);
    error RegistryInvalidRisk();
    error RegistryInvalidCaps();
    error RegistryInvalidWeights();

    event AssetRegistered(address indexed asset, bytes32 indexed oracleId);
    event AssetStatusSet(address indexed asset, bool enabled);
    event AssetRiskUpdated(
        address indexed asset,
        uint16 mintLtvBps,
        uint16 liquidationBps,
        uint16 redemptionFeeBps,
        uint16 reserveBufferBps
    );
    event AssetCapsUpdated(address indexed asset, uint256 depositCap, uint256 issuanceCap);
    event AssetWeightsUpdated(address indexed asset, uint16[4] bucketWeightsBps);

    constructor(address initialAdmin, IReserveOracle oracle_) ObeliskAccess(initialAdmin) {
        oracle = oracle_;
    }

    function registerAsset(address asset, AssetConfig calldata config)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (asset == address(0)) revert RegistryInvalidAsset();
        if (_listed[asset]) revert RegistryAssetAlreadyListed(asset);
        _validateConfig(config);

        _listed[asset] = true;
        _configs[asset] = config;
        _assets.push(asset);
        emit AssetRegistered(asset, config.oracleId);
    }

    function setAssetStatus(address asset, bool enabled) external onlyRole(RISK_ROLE) {
        _requireListed(asset);
        _configs[asset].enabled = enabled;
        emit AssetStatusSet(asset, enabled);
    }

    function updateRisk(
        address asset,
        uint16 mintLtvBps,
        uint16 liquidationBps,
        uint16 redemptionFeeBps,
        uint16 reserveBufferBps
    ) external onlyRole(RISK_ROLE) {
        _requireListed(asset);
        if (
            mintLtvBps == 0 || mintLtvBps >= liquidationBps || liquidationBps > 20_000
                || redemptionFeeBps > 2000 || reserveBufferBps > 10_000
        ) revert RegistryInvalidRisk();

        AssetConfig storage config = _configs[asset];
        config.mintLtvBps = mintLtvBps;
        config.liquidationBps = liquidationBps;
        config.redemptionFeeBps = redemptionFeeBps;
        config.reserveBufferBps = reserveBufferBps;
        emit AssetRiskUpdated(asset, mintLtvBps, liquidationBps, redemptionFeeBps, reserveBufferBps);
    }

    function updateCaps(address asset, uint256 depositCap, uint256 issuanceCap)
        external
        onlyRole(RISK_ROLE)
    {
        _requireListed(asset);
        if (depositCap == 0 || issuanceCap == 0) revert RegistryInvalidCaps();

        AssetConfig storage config = _configs[asset];
        config.depositCap = depositCap;
        config.issuanceCap = issuanceCap;
        emit AssetCapsUpdated(asset, depositCap, issuanceCap);
    }

    function updateBucketWeights(address asset, uint16[4] calldata weights)
        external
        onlyRole(RISK_ROLE)
    {
        _requireListed(asset);
        _validateWeights(weights);
        _configs[asset].bucketWeightsBps = weights;
        emit AssetWeightsUpdated(asset, weights);
    }

    function assetCount() external view returns (uint256) {
        return _assets.length;
    }

    function assetAt(uint256 index) external view returns (address) {
        return _assets[index];
    }

    function assets() external view returns (address[] memory) {
        return _assets;
    }

    function isListed(address asset) external view returns (bool) {
        return _listed[asset];
    }

    function isEnabled(address asset) external view returns (bool) {
        return _configs[asset].enabled;
    }

    function configOf(address asset) external view returns (AssetConfig memory) {
        _requireListed(asset);
        return _configs[asset];
    }

    function decimalsOf(address asset) external view returns (uint8) {
        _requireListed(asset);
        return _configs[asset].decimals;
    }

    function oracleIdOf(address asset) external view returns (bytes32) {
        _requireListed(asset);
        return _configs[asset].oracleId;
    }

    function mintLtvBpsOf(address asset) external view returns (uint16) {
        _requireListed(asset);
        return _configs[asset].mintLtvBps;
    }

    function liquidationBpsOf(address asset) external view returns (uint16) {
        _requireListed(asset);
        return _configs[asset].liquidationBps;
    }

    function redemptionFeeBpsOf(address asset) external view returns (uint16) {
        _requireListed(asset);
        return _configs[asset].redemptionFeeBps;
    }

    function minMintOf(address asset) external view returns (uint256) {
        _requireListed(asset);
        return _configs[asset].minMint;
    }

    function bucketWeightsOf(address asset) external view returns (uint16[4] memory) {
        _requireListed(asset);
        return _configs[asset].bucketWeightsBps;
    }

    function requireEnabled(address asset) external view returns (AssetConfig memory config) {
        _requireListed(asset);
        config = _configs[asset];
        if (!config.enabled) revert RegistryAssetDisabled(asset);
    }

    function priceOf(address asset) public view returns (uint256) {
        _requireListed(asset);
        return oracle.getPrice(_configs[asset].oracleId);
    }

    function valueOf(address asset, uint256 amount) public view returns (uint256) {
        AssetConfig memory config = _requireListed(asset);
        return ReserveMath.assetValue(amount, config.decimals, oracle.getPrice(config.oracleId));
    }

    function amountForValue(address asset, uint256 value) public view returns (uint256) {
        AssetConfig memory config = _requireListed(asset);
        return ReserveMath.assetAmount(value, config.decimals, oracle.getPrice(config.oracleId));
    }

    function amountForValueUp(address asset, uint256 value) public view returns (uint256) {
        AssetConfig memory config = _requireListed(asset);
        return ReserveMath.assetAmountUp(value, config.decimals, oracle.getPrice(config.oracleId));
    }

    function maxDebtFor(address asset, uint256 collateralAmount) external view returns (uint256) {
        AssetConfig memory config = _requireListed(asset);
        uint256 value = ReserveMath.assetValue(
            collateralAmount, config.decimals, oracle.getPrice(config.oracleId)
        );
        return ReserveMath.maxDebtFromCollateral(value, config.mintLtvBps);
    }

    function snapshot(address asset, uint256 reserveAmount)
        external
        view
        returns (AssetRiskSnapshot memory result)
    {
        AssetConfig memory config = _requireListed(asset);
        uint256 price = oracle.getPrice(config.oracleId);
        result = AssetRiskSnapshot({
            asset: asset,
            price: price,
            reserveAmount: reserveAmount,
            reserveValue: ReserveMath.assetValue(reserveAmount, config.decimals, price),
            issuanceCap: config.issuanceCap,
            depositCap: config.depositCap,
            mintLtvBps: config.mintLtvBps,
            redemptionFeeBps: config.redemptionFeeBps,
            enabled: config.enabled
        });
    }

    function _requireListed(address asset) internal view returns (AssetConfig memory config) {
        if (!_listed[asset]) revert RegistryAssetNotListed(asset);
        return _configs[asset];
    }

    function _validateConfig(AssetConfig calldata config) internal pure {
        if (config.decimals == 0 || config.decimals > 18) {
            revert RegistryInvalidDecimals(config.decimals);
        }
        if (
            config.mintLtvBps == 0 || config.mintLtvBps >= config.liquidationBps
                || config.liquidationBps > 20_000 || config.redemptionFeeBps > 2000
                || config.reserveBufferBps > 10_000
        ) revert RegistryInvalidRisk();
        if (config.depositCap == 0 || config.issuanceCap == 0) revert RegistryInvalidCaps();
        _validateWeights(config.bucketWeightsBps);
    }

    function _validateWeights(uint16[4] memory weights) internal pure {
        uint256 sum =
            uint256(weights[0]) + uint256(weights[1]) + uint256(weights[2]) + uint256(weights[3]);
        if (sum != 10_000) revert RegistryInvalidWeights();
    }
}
