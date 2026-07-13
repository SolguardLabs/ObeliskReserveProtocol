// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ObeliskAccess } from "../access/ObeliskAccess.sol";

contract ReserveAccounting is ObeliskAccess {
    bytes32 public constant RECORDER_ROLE = keccak256("RECORDER_ROLE");

    struct EpochTotals {
        uint256 collateralIn;
        uint256 collateralOut;
        uint256 stableMinted;
        uint256 stableBurned;
        uint256 redemptionsProcessed;
        uint256 recapitalized;
        uint256 feesAccrued;
        uint48 openedAt;
        uint48 closedAt;
    }

    struct AccountActivity {
        uint256 collateralIn;
        uint256 collateralOut;
        uint256 stableMinted;
        uint256 stableBurned;
        uint256 redemptionsRequested;
        uint256 redemptionsProcessed;
        uint48 lastActivityAt;
    }

    uint256 public currentEpoch = 1;
    mapping(uint256 epoch => EpochTotals totals) private _epochs;
    mapping(address account => AccountActivity activity) private _accounts;
    mapping(address asset => uint256 amount) public lifetimeCollateralIn;
    mapping(address asset => uint256 amount) public lifetimeCollateralOut;

    event EpochOpened(uint256 indexed epoch, uint48 openedAt);
    event EpochClosed(uint256 indexed epoch, uint48 closedAt);
    event CollateralRecorded(
        uint256 indexed epoch,
        address indexed account,
        address indexed asset,
        uint256 amount,
        bool inbound
    );
    event StableRecorded(
        uint256 indexed epoch, address indexed account, uint256 amount, bool minted
    );
    event RedemptionRecorded(
        uint256 indexed epoch, address indexed account, uint256 requested, uint256 processed
    );
    event RecapitalizationRecorded(uint256 indexed epoch, address indexed asset, uint256 amount);
    event FeeRecorded(uint256 indexed epoch, address indexed asset, uint256 amount);

    error AccountingEpochClosed(uint256 epoch);
    error AccountingInvalidAmount();

    constructor(address initialAdmin) ObeliskAccess(initialAdmin) {
        _epochs[currentEpoch].openedAt = uint48(block.timestamp);
        emit EpochOpened(currentEpoch, uint48(block.timestamp));
    }

    function recordCollateral(address account, address asset, uint256 amount, bool inbound)
        external
        onlyRole(RECORDER_ROLE)
    {
        if (amount == 0) revert AccountingInvalidAmount();
        EpochTotals storage epoch = _activeEpoch();
        AccountActivity storage activity = _accounts[account];
        if (inbound) {
            epoch.collateralIn += amount;
            activity.collateralIn += amount;
            lifetimeCollateralIn[asset] += amount;
        } else {
            epoch.collateralOut += amount;
            activity.collateralOut += amount;
            lifetimeCollateralOut[asset] += amount;
        }
        activity.lastActivityAt = uint48(block.timestamp);
        emit CollateralRecorded(currentEpoch, account, asset, amount, inbound);
    }

    function recordStable(address account, uint256 amount, bool minted)
        external
        onlyRole(RECORDER_ROLE)
    {
        if (amount == 0) revert AccountingInvalidAmount();
        EpochTotals storage epoch = _activeEpoch();
        AccountActivity storage activity = _accounts[account];
        if (minted) {
            epoch.stableMinted += amount;
            activity.stableMinted += amount;
        } else {
            epoch.stableBurned += amount;
            activity.stableBurned += amount;
        }
        activity.lastActivityAt = uint48(block.timestamp);
        emit StableRecorded(currentEpoch, account, amount, minted);
    }

    function recordRedemption(address account, uint256 requested, uint256 processed)
        external
        onlyRole(RECORDER_ROLE)
    {
        if (requested == 0 && processed == 0) revert AccountingInvalidAmount();
        EpochTotals storage epoch = _activeEpoch();
        AccountActivity storage activity = _accounts[account];
        activity.redemptionsRequested += requested;
        activity.redemptionsProcessed += processed;
        epoch.redemptionsProcessed += processed;
        activity.lastActivityAt = uint48(block.timestamp);
        emit RedemptionRecorded(currentEpoch, account, requested, processed);
    }

    function recordRecapitalization(address asset, uint256 amount)
        external
        onlyRole(RECORDER_ROLE)
    {
        if (amount == 0) revert AccountingInvalidAmount();
        _activeEpoch().recapitalized += amount;
        emit RecapitalizationRecorded(currentEpoch, asset, amount);
    }

    function recordFee(address asset, uint256 amount) external onlyRole(RECORDER_ROLE) {
        if (amount == 0) revert AccountingInvalidAmount();
        _activeEpoch().feesAccrued += amount;
        emit FeeRecorded(currentEpoch, asset, amount);
    }

    function closeEpoch() external onlyRole(RECORDER_ROLE) returns (uint256 nextEpoch) {
        EpochTotals storage epoch = _activeEpoch();
        epoch.closedAt = uint48(block.timestamp);
        emit EpochClosed(currentEpoch, epoch.closedAt);
        currentEpoch += 1;
        nextEpoch = currentEpoch;
        _epochs[nextEpoch].openedAt = uint48(block.timestamp);
        emit EpochOpened(nextEpoch, uint48(block.timestamp));
    }

    function epochTotals(uint256 epoch) external view returns (EpochTotals memory) {
        return _epochs[epoch];
    }

    function accountActivity(address account) external view returns (AccountActivity memory) {
        return _accounts[account];
    }

    function _activeEpoch() internal view returns (EpochTotals storage epoch) {
        epoch = _epochs[currentEpoch];
        if (epoch.closedAt != 0) revert AccountingEpochClosed(currentEpoch);
    }
}
