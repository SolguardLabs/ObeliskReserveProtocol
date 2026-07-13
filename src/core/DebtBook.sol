// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ObeliskAccess } from "../access/ObeliskAccess.sol";
import { PositionView } from "../types/ObeliskTypes.sol";

contract DebtBook is ObeliskAccess {
    struct Position {
        address owner;
        address asset;
        uint256 collateralAmount;
        uint256 debt;
        uint48 openedAt;
        uint48 updatedAt;
        bool active;
    }

    bytes32 public constant POOL_ROLE = keccak256("POOL_ROLE");

    uint256 private _nextPositionId = 1;
    uint256 private _totalDebt;
    mapping(uint256 id => Position position) private _positions;
    mapping(address owner => uint256[] ids) private _ownerPositions;
    mapping(address asset => uint256 amount) private _totalCollateralByAsset;

    error DebtBookInvalidOwner();
    error DebtBookInvalidAsset();
    error DebtBookInvalidPosition(uint256 id);
    error DebtBookNotPositionOwner(uint256 id, address caller);
    error DebtBookInsufficientCollateral(uint256 available, uint256 requested);
    error DebtBookInsufficientDebt(uint256 available, uint256 requested);
    error DebtBookPositionOpen(uint256 id);

    event PositionOpened(
        uint256 indexed id, address indexed owner, address indexed asset, uint48 openedAt
    );
    event PositionClosed(uint256 indexed id, address indexed owner);
    event CollateralIncreased(uint256 indexed id, address indexed asset, uint256 amount);
    event CollateralDecreased(uint256 indexed id, address indexed asset, uint256 amount);
    event DebtIncreased(uint256 indexed id, uint256 amount, uint256 newDebt);
    event DebtDecreased(uint256 indexed id, uint256 amount, uint256 newDebt);

    constructor(address initialAdmin) ObeliskAccess(initialAdmin) { }

    function openPosition(address owner, address asset)
        external
        onlyRole(POOL_ROLE)
        returns (uint256 id)
    {
        if (owner == address(0)) revert DebtBookInvalidOwner();
        if (asset == address(0)) revert DebtBookInvalidAsset();

        id = _nextPositionId++;
        Position storage stored = _positions[id];
        stored.owner = owner;
        stored.asset = asset;
        stored.openedAt = uint48(block.timestamp);
        stored.updatedAt = uint48(block.timestamp);
        stored.active = true;
        _ownerPositions[owner].push(id);
        emit PositionOpened(id, owner, asset, uint48(block.timestamp));
    }

    function increaseCollateral(uint256 id, uint256 amount) external onlyRole(POOL_ROLE) {
        Position storage stored = _requirePosition(id);
        stored.collateralAmount += amount;
        stored.updatedAt = uint48(block.timestamp);
        _totalCollateralByAsset[stored.asset] += amount;
        emit CollateralIncreased(id, stored.asset, amount);
    }

    function decreaseCollateral(uint256 id, uint256 amount) external onlyRole(POOL_ROLE) {
        Position storage stored = _requirePosition(id);
        uint256 available = stored.collateralAmount;
        if (available < amount) revert DebtBookInsufficientCollateral(available, amount);

        unchecked {
            stored.collateralAmount = available - amount;
            _totalCollateralByAsset[stored.asset] -= amount;
        }
        stored.updatedAt = uint48(block.timestamp);
        emit CollateralDecreased(id, stored.asset, amount);
    }

    function increaseDebt(uint256 id, uint256 amount) external onlyRole(POOL_ROLE) {
        Position storage stored = _requirePosition(id);
        stored.debt += amount;
        stored.updatedAt = uint48(block.timestamp);
        _totalDebt += amount;
        emit DebtIncreased(id, amount, stored.debt);
    }

    function decreaseDebt(uint256 id, uint256 amount) external onlyRole(POOL_ROLE) {
        Position storage stored = _requirePosition(id);
        uint256 debt = stored.debt;
        if (amount > debt) amount = debt;

        unchecked {
            stored.debt = debt - amount;
            _totalDebt -= amount;
        }
        stored.updatedAt = uint48(block.timestamp);
        emit DebtDecreased(id, amount, stored.debt);
    }

    function closePosition(uint256 id) external onlyRole(POOL_ROLE) {
        Position storage stored = _requirePosition(id);
        if (stored.debt != 0 || stored.collateralAmount != 0) revert DebtBookPositionOpen(id);
        stored.active = false;
        stored.updatedAt = uint48(block.timestamp);
        emit PositionClosed(id, stored.owner);
    }

    function requirePositionOwner(uint256 id, address caller) external view {
        Position storage stored = _requirePosition(id);
        if (stored.owner != caller) revert DebtBookNotPositionOwner(id, caller);
    }

    function position(uint256 id) external view returns (Position memory) {
        return _requirePosition(id);
    }

    function positionOwner(uint256 id) external view returns (address) {
        return _requirePosition(id).owner;
    }

    function positionAsset(uint256 id) external view returns (address) {
        return _requirePosition(id).asset;
    }

    function collateralOf(uint256 id) external view returns (uint256) {
        return _requirePosition(id).collateralAmount;
    }

    function debtOf(uint256 id) external view returns (uint256) {
        return _requirePosition(id).debt;
    }

    function totalDebt() external view returns (uint256) {
        return _totalDebt;
    }

    function totalCollateralOfAsset(address asset) external view returns (uint256) {
        return _totalCollateralByAsset[asset];
    }

    function positionsOf(address owner) external view returns (uint256[] memory) {
        return _ownerPositions[owner];
    }

    function nextPositionId() external view returns (uint256) {
        return _nextPositionId;
    }

    function composePositionView(
        uint256 id,
        uint256 collateralValue,
        uint256 maxDebt,
        uint256 healthBps
    ) external view returns (PositionView memory result) {
        Position storage stored = _requirePosition(id);
        result = PositionView({
            id: id,
            owner: stored.owner,
            asset: stored.asset,
            collateralAmount: stored.collateralAmount,
            collateralValue: collateralValue,
            debt: stored.debt,
            maxDebt: maxDebt,
            healthBps: healthBps,
            active: stored.active
        });
    }

    function _requirePosition(uint256 id) internal view returns (Position storage stored) {
        stored = _positions[id];
        if (!stored.active) revert DebtBookInvalidPosition(id);
    }
}
