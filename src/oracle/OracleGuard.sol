// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ObeliskAccess } from "../access/ObeliskAccess.sol";
import { IReserveOracle } from "../interfaces/IObelisk.sol";

contract OracleGuard is ObeliskAccess {
    bytes32 public constant POLICY_ROLE = keccak256("POLICY_ROLE");
    bytes32 public constant OBSERVER_ROLE = keccak256("OBSERVER_ROLE");

    struct GuardPolicy {
        uint16 lowerBoundBps;
        uint16 upperBoundBps;
        uint16 maxDeviationBps;
        uint48 cooldown;
        bool enabled;
    }

    struct Observation {
        uint256 price;
        uint48 observedAt;
        bool accepted;
    }

    struct GuardReport {
        bytes32 oracleId;
        uint256 currentPrice;
        uint256 previousPrice;
        uint256 deviationBps;
        uint48 observedAt;
        bool accepted;
        bool withinBounds;
        bool withinDeviation;
    }

    IReserveOracle public immutable oracle;
    mapping(bytes32 oracleId => GuardPolicy policy) private _policies;
    mapping(bytes32 oracleId => Observation observation) private _observations;

    event GuardPolicySet(bytes32 indexed oracleId, GuardPolicy policy);
    event ObservationAccepted(bytes32 indexed oracleId, uint256 price, uint256 deviationBps);
    event ObservationRejected(bytes32 indexed oracleId, uint256 price, uint256 deviationBps);

    error OracleGuardInvalidPolicy();
    error OracleGuardPolicyDisabled(bytes32 oracleId);
    error OracleGuardCooldown(bytes32 oracleId, uint48 nextObservationAt);
    error OracleGuardOutOfBounds(bytes32 oracleId, uint256 price);
    error OracleGuardDeviation(bytes32 oracleId, uint256 deviationBps);

    constructor(address initialAdmin, IReserveOracle oracle_) ObeliskAccess(initialAdmin) {
        oracle = oracle_;
    }

    function setPolicy(bytes32 oracleId, GuardPolicy calldata policy)
        external
        onlyRole(POLICY_ROLE)
    {
        if (
            policy.lowerBoundBps > 10_000 || policy.upperBoundBps < 10_000
                || policy.maxDeviationBps > 10_000 || policy.lowerBoundBps >= policy.upperBoundBps
        ) revert OracleGuardInvalidPolicy();
        _policies[oracleId] = policy;
        emit GuardPolicySet(oracleId, policy);
    }

    function observe(bytes32 oracleId)
        external
        onlyRole(OBSERVER_ROLE)
        returns (GuardReport memory)
    {
        GuardPolicy memory policy = _requirePolicy(oracleId);
        Observation memory previous = _observations[oracleId];
        if (
            previous.observedAt != 0
                && block.timestamp < uint256(previous.observedAt) + policy.cooldown
        ) {
            revert OracleGuardCooldown(
                oracleId, uint48(uint256(previous.observedAt) + policy.cooldown)
            );
        }

        uint256 price = oracle.getPrice(oracleId);
        GuardReport memory report = _buildReport(oracleId, policy, previous.price, price);
        if (!report.withinBounds) revert OracleGuardOutOfBounds(oracleId, price);
        if (!report.withinDeviation) revert OracleGuardDeviation(oracleId, report.deviationBps);

        _observations[oracleId] =
            Observation({ price: price, observedAt: uint48(block.timestamp), accepted: true });
        emit ObservationAccepted(oracleId, price, report.deviationBps);
        return report;
    }

    function preview(bytes32 oracleId) external view returns (GuardReport memory) {
        GuardPolicy memory policy = _requirePolicy(oracleId);
        Observation memory previous = _observations[oracleId];
        uint256 price = oracle.getPrice(oracleId);
        return _buildReport(oracleId, policy, previous.price, price);
    }

    function policyOf(bytes32 oracleId) external view returns (GuardPolicy memory) {
        return _policies[oracleId];
    }

    function lastObservation(bytes32 oracleId) external view returns (Observation memory) {
        return _observations[oracleId];
    }

    function canObserve(bytes32 oracleId) external view returns (bool) {
        GuardPolicy memory policy = _policies[oracleId];
        if (!policy.enabled) return false;
        Observation memory previous = _observations[oracleId];
        return previous.observedAt == 0
            || block.timestamp >= uint256(previous.observedAt) + policy.cooldown;
    }

    function nextObservationAt(bytes32 oracleId) external view returns (uint48) {
        GuardPolicy memory policy = _requirePolicy(oracleId);
        Observation memory previous = _observations[oracleId];
        if (previous.observedAt == 0) return uint48(block.timestamp);
        return uint48(uint256(previous.observedAt) + policy.cooldown);
    }

    function isObservationFresh(bytes32 oracleId, uint48 maxAge) external view returns (bool) {
        Observation memory previous = _observations[oracleId];
        if (previous.observedAt == 0 || !previous.accepted) return false;
        return block.timestamp <= uint256(previous.observedAt) + maxAge;
    }

    function guardStatus(bytes32 oracleId)
        external
        view
        returns (bool enabled, bool observed, uint48 observedAt, uint256 lastPrice)
    {
        GuardPolicy memory policy = _policies[oracleId];
        Observation memory previous = _observations[oracleId];
        return (policy.enabled, previous.observedAt != 0, previous.observedAt, previous.price);
    }

    function deviationBps(uint256 previousPrice, uint256 currentPrice)
        public
        pure
        returns (uint256)
    {
        if (previousPrice == 0 || currentPrice == 0) return 0;
        uint256 diff = previousPrice > currentPrice
            ? previousPrice - currentPrice
            : currentPrice - previousPrice;
        return diff * 10_000 / previousPrice;
    }

    function boundedPrice(uint256 anchorPrice, uint16 lowerBoundBps, uint16 upperBoundBps)
        public
        pure
        returns (uint256 lower, uint256 upper)
    {
        lower = anchorPrice * lowerBoundBps / 10_000;
        upper = anchorPrice * upperBoundBps / 10_000;
    }

    function _buildReport(
        bytes32 oracleId,
        GuardPolicy memory policy,
        uint256 previousPrice,
        uint256 currentPrice
    ) internal view returns (GuardReport memory report) {
        uint256 deviation = deviationBps(previousPrice, currentPrice);
        bool withinDeviation = previousPrice == 0 || deviation <= policy.maxDeviationBps;
        bool withinBounds = true;
        if (previousPrice != 0) {
            (uint256 lower, uint256 upper) =
                boundedPrice(previousPrice, policy.lowerBoundBps, policy.upperBoundBps);
            withinBounds = currentPrice >= lower && currentPrice <= upper;
        }
        report = GuardReport({
            oracleId: oracleId,
            currentPrice: currentPrice,
            previousPrice: previousPrice,
            deviationBps: deviation,
            observedAt: uint48(block.timestamp),
            accepted: withinBounds && withinDeviation,
            withinBounds: withinBounds,
            withinDeviation: withinDeviation
        });
    }

    function _requirePolicy(bytes32 oracleId) internal view returns (GuardPolicy memory policy) {
        policy = _policies[oracleId];
        if (!policy.enabled) revert OracleGuardPolicyDisabled(oracleId);
    }
}
