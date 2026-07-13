// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ObeliskAccess } from "../access/ObeliskAccess.sol";

contract ParameterTimelock is ObeliskAccess {
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");

    struct Operation {
        address target;
        uint256 value;
        bytes data;
        bytes32 predecessor;
        bytes32 salt;
        uint48 readyAt;
        bool executed;
        bool cancelled;
    }

    uint48 public minDelay;
    mapping(bytes32 id => Operation operation) private _operations;

    event MinDelayUpdated(uint48 previousDelay, uint48 newDelay);
    event OperationScheduled(
        bytes32 indexed id,
        address indexed target,
        uint256 value,
        bytes32 predecessor,
        bytes32 salt,
        uint48 readyAt
    );
    event OperationCancelled(bytes32 indexed id);
    event OperationExecuted(bytes32 indexed id, address indexed target, uint256 value);

    error TimelockInvalidDelay();
    error TimelockInvalidTarget();
    error TimelockAlreadyScheduled(bytes32 id);
    error TimelockNotScheduled(bytes32 id);
    error TimelockNotReady(bytes32 id, uint48 readyAt);
    error TimelockPredecessorNotDone(bytes32 predecessor);
    error TimelockOperationFinalized(bytes32 id);
    error TimelockExecutionFailed(bytes32 id, bytes reason);

    constructor(address admin, uint48 minDelay_) ObeliskAccess(admin) {
        if (minDelay_ == 0) revert TimelockInvalidDelay();
        minDelay = minDelay_;
    }

    receive() external payable { }

    function updateDelay(uint48 newDelay) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newDelay == 0) revert TimelockInvalidDelay();
        uint48 previous = minDelay;
        minDelay = newDelay;
        emit MinDelayUpdated(previous, newDelay);
    }

    function schedule(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint48 delay
    ) external onlyRole(PROPOSER_ROLE) returns (bytes32 id) {
        if (target == address(0)) revert TimelockInvalidTarget();
        if (delay < minDelay) revert TimelockInvalidDelay();
        id = hashOperation(target, value, data, predecessor, salt);
        Operation storage stored = _operations[id];
        if (stored.readyAt != 0) revert TimelockAlreadyScheduled(id);
        stored.target = target;
        stored.value = value;
        stored.data = data;
        stored.predecessor = predecessor;
        stored.salt = salt;
        stored.readyAt = uint48(block.timestamp) + delay;
        emit OperationScheduled(id, target, value, predecessor, salt, stored.readyAt);
    }

    function cancel(bytes32 id) external onlyRole(CANCELLER_ROLE) {
        Operation storage stored = _requireScheduled(id);
        if (stored.executed || stored.cancelled) revert TimelockOperationFinalized(id);
        stored.cancelled = true;
        emit OperationCancelled(id);
    }

    function execute(bytes32 id)
        external
        payable
        onlyRole(EXECUTOR_ROLE)
        returns (bytes memory result)
    {
        Operation storage stored = _requireScheduled(id);
        if (stored.executed || stored.cancelled) revert TimelockOperationFinalized(id);
        if (block.timestamp < stored.readyAt) revert TimelockNotReady(id, stored.readyAt);
        if (stored.predecessor != bytes32(0) && !isDone(stored.predecessor)) {
            revert TimelockPredecessorNotDone(stored.predecessor);
        }

        stored.executed = true;
        (bool success, bytes memory data) = stored.target.call{ value: stored.value }(stored.data);
        if (!success) revert TimelockExecutionFailed(id, data);
        emit OperationExecuted(id, stored.target, stored.value);
        return data;
    }

    function hashOperation(
        address target,
        uint256 value,
        bytes memory data,
        bytes32 predecessor,
        bytes32 salt
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(target, value, keccak256(data), predecessor, salt));
    }

    function isOperation(bytes32 id) public view returns (bool) {
        return _operations[id].readyAt != 0;
    }

    function isPending(bytes32 id) external view returns (bool) {
        Operation storage stored = _operations[id];
        return stored.readyAt != 0 && !stored.executed && !stored.cancelled
            && block.timestamp < stored.readyAt;
    }

    function isReady(bytes32 id) external view returns (bool) {
        Operation storage stored = _operations[id];
        return stored.readyAt != 0 && !stored.executed && !stored.cancelled
            && block.timestamp >= stored.readyAt;
    }

    function isDone(bytes32 id) public view returns (bool) {
        return _operations[id].executed;
    }

    function operation(bytes32 id) external view returns (Operation memory) {
        return _requireScheduled(id);
    }

    function _requireScheduled(bytes32 id) internal view returns (Operation storage operation_) {
        operation_ = _operations[id];
        if (operation_.readyAt == 0) revert TimelockNotScheduled(id);
    }
}
