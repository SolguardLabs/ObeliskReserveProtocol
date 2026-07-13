// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ObeliskAccess } from "../access/ObeliskAccess.sol";
import { IReserveOracle } from "../interfaces/IObelisk.sol";

contract ReserveOracle is ObeliskAccess, IReserveOracle {
    struct Feed {
        uint256 price;
        uint256 minPrice;
        uint256 maxPrice;
        uint48 updatedAt;
        uint48 heartbeat;
        bool enabled;
    }

    bytes32 public constant REPORTER_ROLE = keccak256("REPORTER_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    mapping(bytes32 id => Feed feed) private _feeds;

    error OracleFeedDisabled(bytes32 id);
    error OracleFeedStale(bytes32 id, uint48 updatedAt, uint48 heartbeat);
    error OraclePriceOutOfBounds(bytes32 id, uint256 price);
    error OracleBadHeartbeat();
    error OracleBadBounds();

    event FeedConfigured(bytes32 indexed id, uint48 heartbeat, uint256 minPrice, uint256 maxPrice);
    event FeedStatusChanged(bytes32 indexed id, bool enabled);
    event PriceReported(bytes32 indexed id, uint256 price, uint48 timestamp);

    constructor(address initialAdmin) ObeliskAccess(initialAdmin) { }

    function configureFeed(bytes32 id, uint48 heartbeat, uint256 minPrice, uint256 maxPrice)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (heartbeat == 0) revert OracleBadHeartbeat();
        if (minPrice == 0 || minPrice >= maxPrice) revert OracleBadBounds();

        Feed storage feed = _feeds[id];
        feed.heartbeat = heartbeat;
        feed.minPrice = minPrice;
        feed.maxPrice = maxPrice;
        feed.enabled = true;
        emit FeedConfigured(id, heartbeat, minPrice, maxPrice);
    }

    function setFeedStatus(bytes32 id, bool enabled) external onlyRole(GUARDIAN_ROLE) {
        _feeds[id].enabled = enabled;
        emit FeedStatusChanged(id, enabled);
    }

    function reportPrice(bytes32 id, uint256 price) external onlyRole(REPORTER_ROLE) {
        Feed storage feed = _feeds[id];
        if (!feed.enabled) revert OracleFeedDisabled(id);
        if (price < feed.minPrice || price > feed.maxPrice) {
            revert OraclePriceOutOfBounds(id, price);
        }

        feed.price = price;
        feed.updatedAt = uint48(block.timestamp);
        emit PriceReported(id, price, uint48(block.timestamp));
    }

    function getPrice(bytes32 id) external view returns (uint256 price) {
        Feed memory feed = _feeds[id];
        if (!feed.enabled) revert OracleFeedDisabled(id);
        if (feed.price < feed.minPrice || feed.price > feed.maxPrice) {
            revert OraclePriceOutOfBounds(id, feed.price);
        }
        if (block.timestamp > uint256(feed.updatedAt) + feed.heartbeat) {
            revert OracleFeedStale(id, feed.updatedAt, feed.heartbeat);
        }
        return feed.price;
    }

    function peekPrice(bytes32 id)
        external
        view
        returns (uint256 price, uint48 updatedAt, bool valid)
    {
        Feed memory feed = _feeds[id];
        bool inBounds = feed.price >= feed.minPrice && feed.price <= feed.maxPrice;
        bool fresh = block.timestamp <= uint256(feed.updatedAt) + feed.heartbeat;
        return (feed.price, feed.updatedAt, feed.enabled && inBounds && fresh);
    }

    function feedConfig(bytes32 id)
        external
        view
        returns (uint48 heartbeat, uint256 minPrice, uint256 maxPrice, bool enabled)
    {
        Feed memory feed = _feeds[id];
        return (feed.heartbeat, feed.minPrice, feed.maxPrice, feed.enabled);
    }
}
