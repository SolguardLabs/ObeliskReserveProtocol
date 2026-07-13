// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ObeliskAccess } from "../access/ObeliskAccess.sol";
import { IBackstopProvider, IERC20 } from "../interfaces/IObelisk.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";

contract BackstopPool is ObeliskAccess, IBackstopProvider {
    using SafeTransferLib for IERC20;

    bytes32 public constant RESERVE_POOL_ROLE = keccak256("RESERVE_POOL_ROLE");
    bytes32 public constant ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");

    mapping(address asset => bool enabled) public assetEnabled;
    mapping(address asset => uint256 shares) public totalShares;
    mapping(address asset => uint256 liquidity) public managedLiquidity;
    mapping(address asset => mapping(address account => uint256 shares)) public balanceOf;

    error BackstopAssetDisabled(address asset);
    error BackstopInvalidReceiver();
    error BackstopInvalidAmount();
    error BackstopInsufficientShares(uint256 available, uint256 requested);
    error BackstopInsufficientLiquidity(uint256 available, uint256 requested);

    event AssetEnabled(address indexed asset, bool enabled);
    event Deposited(address indexed asset, address indexed account, uint256 amount, uint256 shares);
    event Withdrawn(address indexed asset, address indexed account, uint256 amount, uint256 shares);
    event Provided(
        address indexed asset, address indexed receiver, uint256 amount, uint256 sharesBurned
    );

    constructor(address initialAdmin) ObeliskAccess(initialAdmin) { }

    function setAssetEnabled(address asset, bool enabled) external onlyRole(ASSET_MANAGER_ROLE) {
        assetEnabled[asset] = enabled;
        emit AssetEnabled(asset, enabled);
    }

    function deposit(address asset, uint256 amount, address receiver)
        external
        returns (uint256 shares)
    {
        if (!assetEnabled[asset]) revert BackstopAssetDisabled(asset);
        if (receiver == address(0)) revert BackstopInvalidReceiver();
        if (amount == 0) revert BackstopInvalidAmount();

        uint256 liquidityBefore = managedLiquidity[asset];
        uint256 supply = totalShares[asset];
        shares = supply == 0 || liquidityBefore == 0 ? amount : amount * supply / liquidityBefore;
        if (shares == 0) revert BackstopInvalidAmount();

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        managedLiquidity[asset] = liquidityBefore + amount;
        totalShares[asset] = supply + shares;
        balanceOf[asset][receiver] += shares;
        emit Deposited(asset, receiver, amount, shares);
    }

    function withdraw(address asset, uint256 shares, address receiver)
        external
        returns (uint256 amount)
    {
        if (receiver == address(0)) revert BackstopInvalidReceiver();
        if (shares == 0) revert BackstopInvalidAmount();

        uint256 userShares = balanceOf[asset][msg.sender];
        if (userShares < shares) revert BackstopInsufficientShares(userShares, shares);

        uint256 supply = totalShares[asset];
        amount = shares * managedLiquidity[asset] / supply;
        if (amount == 0) revert BackstopInvalidAmount();

        unchecked {
            balanceOf[asset][msg.sender] = userShares - shares;
            totalShares[asset] = supply - shares;
            managedLiquidity[asset] -= amount;
        }
        IERC20(asset).safeTransfer(receiver, amount);
        emit Withdrawn(asset, receiver, amount, shares);
    }

    function provide(address asset, uint256 amount, address receiver)
        external
        onlyRole(RESERVE_POOL_ROLE)
        returns (uint256 sharesBurned)
    {
        if (receiver == address(0)) revert BackstopInvalidReceiver();
        if (amount == 0) revert BackstopInvalidAmount();

        uint256 available = managedLiquidity[asset];
        if (available < amount) revert BackstopInsufficientLiquidity(available, amount);

        unchecked {
            managedLiquidity[asset] = available - amount;
        }
        IERC20(asset).safeTransfer(receiver, amount);
        emit Provided(asset, receiver, amount, sharesBurned);
    }

    function previewDeposit(address asset, uint256 amount) external view returns (uint256) {
        uint256 liquidity = managedLiquidity[asset];
        uint256 supply = totalShares[asset];
        return supply == 0 || liquidity == 0 ? amount : amount * supply / liquidity;
    }

    function previewWithdraw(address asset, uint256 shares) external view returns (uint256) {
        uint256 supply = totalShares[asset];
        if (supply == 0) return 0;
        return shares * managedLiquidity[asset] / supply;
    }
}
