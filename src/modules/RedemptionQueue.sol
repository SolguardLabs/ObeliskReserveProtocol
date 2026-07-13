// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ObeliskAccess } from "../access/ObeliskAccess.sol";
import { IObeliskUSD, IRedemptionSettlement } from "../interfaces/IObelisk.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";
import { IERC20 } from "../interfaces/IObelisk.sol";
import { QueueStats, RedemptionTicket, TicketStatus } from "../types/ObeliskTypes.sol";

contract RedemptionQueue is ObeliskAccess {
    using SafeTransferLib for IERC20;

    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    IObeliskUSD public immutable stablecoin;
    IRedemptionSettlement public settlement;

    uint48 public executionDelay;
    uint256 public nextTicketId = 1;
    uint256 public pendingTickets;
    uint256 public pendingStable;
    uint256 public executedStable;
    uint256 public cancelledStable;
    uint256 public expiredStable;
    bool public queuePaused;

    mapping(uint256 id => RedemptionTicket ticket) private _tickets;
    mapping(address account => uint256 amount) public accountPendingStable;

    error QueueInvalidSettlement();
    error QueueInvalidAmount();
    error QueueInvalidReceiver();
    error QueueInvalidDeadline(uint48 deadline);
    error QueuePaused();
    error QueueUnknownTicket(uint256 id);
    error QueueNotRequester(uint256 id, address caller);
    error QueueNotPending(uint256 id);
    error QueueDelayActive(uint256 id, uint48 executableAt);
    error QueueExpired(uint256 id, uint48 deadline);
    error QueueNotExpired(uint256 id, uint48 deadline);
    error QueueTooManyItems();

    event SettlementUpdated(address indexed settlement);
    event ExecutionDelayUpdated(uint48 previousDelay, uint48 newDelay);
    event QueuePauseSet(bool paused);
    event RedemptionRequested(
        uint256 indexed id,
        address indexed requester,
        address indexed asset,
        uint256 stableAmount,
        address receiver
    );
    event RedemptionExecuted(uint256 indexed id, address indexed receiver, uint256 assetOut);
    event RedemptionCancelled(uint256 indexed id, address indexed requester);
    event RedemptionExpired(uint256 indexed id, address indexed requester);

    constructor(
        address initialAdmin,
        IObeliskUSD stablecoin_,
        IRedemptionSettlement settlement_,
        uint48 executionDelay_
    ) ObeliskAccess(initialAdmin) {
        stablecoin = stablecoin_;
        settlement = settlement_;
        executionDelay = executionDelay_;
    }

    function setSettlement(IRedemptionSettlement newSettlement)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (address(newSettlement) == address(0)) revert QueueInvalidSettlement();
        settlement = newSettlement;
        emit SettlementUpdated(address(newSettlement));
    }

    function setExecutionDelay(uint48 newDelay) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint48 previous = executionDelay;
        executionDelay = newDelay;
        emit ExecutionDelayUpdated(previous, newDelay);
    }

    function setPaused(bool paused) external onlyRole(GUARDIAN_ROLE) {
        queuePaused = paused;
        emit QueuePauseSet(paused);
    }

    function requestRedemption(
        address asset,
        uint256 stableAmount,
        uint256 minOut,
        address receiver,
        uint48 deadline
    ) external returns (uint256 id) {
        if (queuePaused) revert QueuePaused();
        if (stableAmount == 0) revert QueueInvalidAmount();
        if (receiver == address(0)) revert QueueInvalidReceiver();
        uint48 executableAt = uint48(block.timestamp) + executionDelay;
        if (deadline <= executableAt) revert QueueInvalidDeadline(deadline);

        IERC20(address(stablecoin)).safeTransferFrom(msg.sender, address(this), stableAmount);
        stablecoin.burn(stableAmount);

        id = nextTicketId++;
        RedemptionTicket storage stored = _tickets[id];
        stored.id = id;
        stored.requester = msg.sender;
        stored.receiver = receiver;
        stored.asset = asset;
        stored.stableAmount = stableAmount;
        stored.minOut = minOut;
        stored.createdAt = uint48(block.timestamp);
        stored.executableAt = executableAt;
        stored.deadline = deadline;
        stored.status = TicketStatus.Pending;

        pendingTickets += 1;
        pendingStable += stableAmount;
        accountPendingStable[msg.sender] += stableAmount;
        emit RedemptionRequested(id, msg.sender, asset, stableAmount, receiver);
    }

    function executeRedemption(uint256 id) public returns (uint256 assetOut) {
        RedemptionTicket storage stored = _requireTicket(id);
        _requirePending(stored);
        if (block.timestamp < stored.executableAt) {
            revert QueueDelayActive(id, stored.executableAt);
        }
        if (block.timestamp > stored.deadline) revert QueueExpired(id, stored.deadline);

        stored.status = TicketStatus.Executed;
        pendingTickets -= 1;
        pendingStable -= stored.stableAmount;
        accountPendingStable[stored.requester] -= stored.stableAmount;
        executedStable += stored.stableAmount;

        assetOut = settlement.fulfillRedemption(
            stored.asset, stored.stableAmount, stored.receiver, stored.minOut
        );
        stored.assetOut = assetOut;
        emit RedemptionExecuted(id, stored.receiver, assetOut);
    }

    function executeBatch(uint256[] calldata ids, uint256 maxItems)
        external
        onlyRole(KEEPER_ROLE)
        returns (uint256 processed)
    {
        if (maxItems > ids.length) revert QueueTooManyItems();
        for (uint256 i = 0; i < maxItems; ++i) {
            executeRedemption(ids[i]);
            processed += 1;
        }
    }

    function cancelRedemption(uint256 id) external {
        RedemptionTicket storage stored = _requireTicket(id);
        _requirePending(stored);
        if (stored.requester != msg.sender) revert QueueNotRequester(id, msg.sender);

        stored.status = TicketStatus.Cancelled;
        pendingTickets -= 1;
        pendingStable -= stored.stableAmount;
        accountPendingStable[msg.sender] -= stored.stableAmount;
        cancelledStable += stored.stableAmount;
        stablecoin.mint(stored.requester, stored.stableAmount);
        emit RedemptionCancelled(id, msg.sender);
    }

    function expireRedemption(uint256 id) external {
        RedemptionTicket storage stored = _requireTicket(id);
        _requirePending(stored);
        if (block.timestamp <= stored.deadline) revert QueueNotExpired(id, stored.deadline);

        stored.status = TicketStatus.Expired;
        pendingTickets -= 1;
        pendingStable -= stored.stableAmount;
        accountPendingStable[stored.requester] -= stored.stableAmount;
        expiredStable += stored.stableAmount;
        stablecoin.mint(stored.requester, stored.stableAmount);
        emit RedemptionExpired(id, stored.requester);
    }

    function ticket(uint256 id) external view returns (RedemptionTicket memory) {
        return _requireTicket(id);
    }

    function queueStats() external view returns (QueueStats memory stats) {
        stats = QueueStats({
            nextTicketId: nextTicketId,
            pendingTickets: pendingTickets,
            pendingStable: pendingStable,
            executedStable: executedStable,
            cancelledStable: cancelledStable,
            expiredStable: expiredStable,
            executionDelay: executionDelay
        });
    }

    function _requireTicket(uint256 id) internal view returns (RedemptionTicket storage stored) {
        stored = _tickets[id];
        if (stored.status == TicketStatus.None) revert QueueUnknownTicket(id);
    }

    function _requirePending(RedemptionTicket storage stored) internal view {
        if (stored.status != TicketStatus.Pending) revert QueueNotPending(stored.id);
    }
}
