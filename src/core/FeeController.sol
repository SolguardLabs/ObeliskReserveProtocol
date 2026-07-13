// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ObeliskAccess } from "../access/ObeliskAccess.sol";
import { PercentageMath } from "../libraries/PercentageMath.sol";

contract FeeController is ObeliskAccess {
    using PercentageMath for uint256;

    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

    struct FeeConfig {
        uint16 mintFeeBps;
        uint16 burnFeeBps;
        uint16 redemptionFeeBps;
        uint16 keeperShareBps;
        uint256 minimumFee;
        uint256 maximumFee;
        bool enabled;
    }

    struct FeeQuote {
        uint256 grossAmount;
        uint256 feeAmount;
        uint256 netAmount;
        uint256 keeperShare;
        uint256 treasuryShare;
    }

    mapping(address asset => FeeConfig config) private _configs;
    mapping(address asset => uint256 amount) public accruedTreasuryFees;
    mapping(address keeper => uint256 amount) public accruedKeeperFees;

    event FeeConfigSet(address indexed asset, FeeConfig config);
    event TreasuryFeesAccrued(address indexed asset, uint256 amount);
    event KeeperFeesAccrued(address indexed keeper, uint256 amount);
    event TreasuryFeesClaimed(address indexed asset, address indexed receiver, uint256 amount);
    event KeeperFeesClaimed(address indexed keeper, address indexed receiver, uint256 amount);

    error FeeInvalidAsset();
    error FeeInvalidConfig();
    error FeeNotEnabled(address asset);
    error FeeNothingToClaim();
    error FeeInvalidReceiver();

    constructor(address initialAdmin) ObeliskAccess(initialAdmin) { }

    function setFeeConfig(address asset, FeeConfig calldata config)
        external
        onlyRole(FEE_MANAGER_ROLE)
    {
        if (asset == address(0)) revert FeeInvalidAsset();
        if (
            config.mintFeeBps > 2000 || config.burnFeeBps > 2000 || config.redemptionFeeBps > 2000
                || config.keeperShareBps > 10_000
                || (config.maximumFee != 0 && config.minimumFee > config.maximumFee)
        ) revert FeeInvalidConfig();
        _configs[asset] = config;
        emit FeeConfigSet(asset, config);
    }

    function configOf(address asset) external view returns (FeeConfig memory) {
        return _configs[asset];
    }

    function quoteMint(address asset, uint256 amount) external view returns (FeeQuote memory) {
        FeeConfig memory config = _requireEnabled(asset);
        return _quote(amount, config.mintFeeBps, config);
    }

    function quoteBurn(address asset, uint256 amount) external view returns (FeeQuote memory) {
        FeeConfig memory config = _requireEnabled(asset);
        return _quote(amount, config.burnFeeBps, config);
    }

    function quoteRedemption(address asset, uint256 amount)
        external
        view
        returns (FeeQuote memory)
    {
        FeeConfig memory config = _requireEnabled(asset);
        return _quote(amount, config.redemptionFeeBps, config);
    }

    function accrue(address asset, address keeper, uint256 feeAmount)
        external
        onlyRole(FEE_MANAGER_ROLE)
        returns (uint256 treasuryShare, uint256 keeperShare)
    {
        FeeConfig memory config = _requireEnabled(asset);
        keeperShare = feeAmount.percentMulDown(config.keeperShareBps);
        treasuryShare = feeAmount - keeperShare;
        accruedTreasuryFees[asset] += treasuryShare;
        if (keeperShare != 0 && keeper != address(0)) accruedKeeperFees[keeper] += keeperShare;
        emit TreasuryFeesAccrued(asset, treasuryShare);
        if (keeperShare != 0 && keeper != address(0)) emit KeeperFeesAccrued(keeper, keeperShare);
    }

    function claimTreasuryFees(address asset, address receiver)
        external
        onlyRole(FEE_MANAGER_ROLE)
        returns (uint256 amount)
    {
        if (receiver == address(0)) revert FeeInvalidReceiver();
        amount = accruedTreasuryFees[asset];
        if (amount == 0) revert FeeNothingToClaim();
        delete accruedTreasuryFees[asset];
        emit TreasuryFeesClaimed(asset, receiver, amount);
    }

    function claimKeeperFees(address receiver) external returns (uint256 amount) {
        if (receiver == address(0)) revert FeeInvalidReceiver();
        amount = accruedKeeperFees[msg.sender];
        if (amount == 0) revert FeeNothingToClaim();
        delete accruedKeeperFees[msg.sender];
        emit KeeperFeesClaimed(msg.sender, receiver, amount);
    }

    function _requireEnabled(address asset) internal view returns (FeeConfig memory config) {
        config = _configs[asset];
        if (!config.enabled) revert FeeNotEnabled(asset);
    }

    function _quote(uint256 amount, uint256 feeBps, FeeConfig memory config)
        internal
        pure
        returns (FeeQuote memory quote)
    {
        uint256 feeAmount = amount.percentMulDown(feeBps);
        if (feeAmount < config.minimumFee && amount != 0) feeAmount = config.minimumFee;
        if (config.maximumFee != 0 && feeAmount > config.maximumFee) feeAmount = config.maximumFee;
        uint256 keeperShare = feeAmount.percentMulDown(config.keeperShareBps);
        quote = FeeQuote({
            grossAmount: amount,
            feeAmount: feeAmount,
            netAmount: amount > feeAmount ? amount - feeAmount : 0,
            keeperShare: keeperShare,
            treasuryShare: feeAmount - keeperShare
        });
    }
}
