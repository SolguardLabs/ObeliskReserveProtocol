// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ObeliskAccess } from "../access/ObeliskAccess.sol";
import { ObeliskReservePool } from "../core/ObeliskReservePool.sol";
import { RedemptionQueue } from "../modules/RedemptionQueue.sol";

contract KeeperRouter is ObeliskAccess {
    bytes32 public constant ROUTER_KEEPER_ROLE = keccak256("ROUTER_KEEPER_ROLE");

    ObeliskReservePool public immutable reservePool;
    RedemptionQueue public immutable queue;

    event BatchExecuted(address indexed keeper, uint256 processed);
    event RecapitalizationExecuted(
        address indexed keeper, address indexed asset, uint256 amount, uint256 shares
    );
    event GuardedRun(address indexed keeper, uint256 processed, uint256 recapitalizedAmount);

    error RouterNothingToDo();
    error RouterCallFailed(uint256 index, bytes reason);

    constructor(address admin, ObeliskReservePool reservePool_, RedemptionQueue queue_)
        ObeliskAccess(admin)
    {
        reservePool = reservePool_;
        queue = queue_;
    }

    function process(uint256[] calldata ticketIds, uint256 maxItems)
        external
        onlyRole(ROUTER_KEEPER_ROLE)
        returns (uint256 processed)
    {
        if (ticketIds.length == 0 || maxItems == 0) revert RouterNothingToDo();
        processed = queue.executeBatch(ticketIds, maxItems);
        emit BatchExecuted(msg.sender, processed);
    }

    function recapitalize(address asset, uint256 amount)
        external
        onlyRole(ROUTER_KEEPER_ROLE)
        returns (uint256 shares)
    {
        if (amount == 0) revert RouterNothingToDo();
        shares = reservePool.recapitalize(asset, amount);
        emit RecapitalizationExecuted(msg.sender, asset, amount, shares);
    }

    function guardedRun(
        uint256[] calldata ticketIds,
        uint256 maxItems,
        address recapAsset,
        uint256 recapAmount
    ) external onlyRole(ROUTER_KEEPER_ROLE) returns (uint256 processed, uint256 shares) {
        if (recapAmount != 0) shares = reservePool.recapitalize(recapAsset, recapAmount);
        if (ticketIds.length != 0 && maxItems != 0) {
            processed = queue.executeBatch(ticketIds, maxItems);
        }
        if (processed == 0 && shares == 0) revert RouterNothingToDo();
        emit GuardedRun(msg.sender, processed, recapAmount);
    }

    function multicall(bytes[] calldata calls)
        external
        onlyRole(ROUTER_KEEPER_ROLE)
        returns (bytes[] memory results)
    {
        if (calls.length == 0) revert RouterNothingToDo();
        results = new bytes[](calls.length);
        for (uint256 i = 0; i < calls.length; ++i) {
            (bool success, bytes memory result) = address(this).delegatecall(calls[i]);
            if (!success) revert RouterCallFailed(i, result);
            results[i] = result;
        }
    }
}
