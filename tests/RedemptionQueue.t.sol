// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ObeliskTestBase } from "./helpers/ObeliskTestBase.sol";
import { QueueStats, RedemptionTicket, TicketStatus } from "../src/types/ObeliskTypes.sol";

contract RedemptionQueueTest is ObeliskTestBase {
    function testQueuedRedemptionExecutesAfterDelay() public {
        _open(alice, 1_000_000 * 1e6, 400_000 ether);
        uint256 bobBefore = usdc.balanceOf(bob);

        uint256 id = _request(alice, 100_000 ether, 99_000 * 1e6, bob, 3 days);
        assertEq(stablecoin.totalSupply(), 300_000 ether);
        assertEq(queue.pendingStable(), 100_000 ether);

        vm.expectRevert();
        queue.executeRedemption(id);

        vm.warp(block.timestamp + REDEMPTION_DELAY);
        uint256 assetOut = queue.executeRedemption(id);

        RedemptionTicket memory ticket = queue.ticket(id);
        assertEq(uint256(ticket.status), uint256(TicketStatus.Executed));
        assertEq(ticket.assetOut, assetOut);
        assertEq(queue.pendingStable(), 0);
        assertEq(usdc.balanceOf(bob), bobBefore + assetOut);
        assertEq(assetOut, 99_800 * 1e6);
    }

    function testRequesterCanCancelPendingRedemption() public {
        _open(alice, 500_000 * 1e6, 200_000 ether);
        uint256 id = _request(alice, 50_000 ether, 0, alice, 3 days);
        assertEq(stablecoin.totalSupply(), 150_000 ether);

        vm.prank(alice);
        queue.cancelRedemption(id);

        RedemptionTicket memory ticket = queue.ticket(id);
        assertEq(uint256(ticket.status), uint256(TicketStatus.Cancelled));
        assertEq(stablecoin.balanceOf(alice), 200_000 ether);
        assertEq(stablecoin.totalSupply(), 200_000 ether);
        assertEq(queue.pendingStable(), 0);
    }

    function testExpiredTicketRefundsStablecoin() public {
        _open(alice, 500_000 * 1e6, 200_000 ether);
        uint256 id = _request(alice, 25_000 ether, 0, alice, 2 days);
        vm.warp(block.timestamp + 2 days + 1);

        queue.expireRedemption(id);

        RedemptionTicket memory ticket = queue.ticket(id);
        assertEq(uint256(ticket.status), uint256(TicketStatus.Expired));
        assertEq(stablecoin.balanceOf(alice), 200_000 ether);
        assertEq(queue.pendingStable(), 0);
    }

    function testKeeperProcessesBatch() public {
        _open(alice, 2_000_000 * 1e6, 800_000 ether);
        uint256 first = _request(alice, 100_000 ether, 99_000 * 1e6, alice, 3 days);
        uint256 second = _request(alice, 50_000 ether, 49_000 * 1e6, bob, 3 days);
        uint256[] memory ids = new uint256[](2);
        ids[0] = first;
        ids[1] = second;

        vm.warp(block.timestamp + REDEMPTION_DELAY);
        vm.prank(keeper);
        uint256 processed = queue.executeBatch(ids, 2);

        assertEq(processed, 2);
        assertEq(queue.pendingTickets(), 0);
        assertEq(queue.executedStable(), 150_000 ether);
    }

    function testQueueStatsTrackLifecycle() public {
        _open(alice, 1_000_000 * 1e6, 300_000 ether);
        _request(alice, 30_000 ether, 0, alice, 3 days);

        QueueStats memory stats = queue.queueStats();
        assertEq(stats.nextTicketId, 2);
        assertEq(stats.pendingTickets, 1);
        assertEq(stats.pendingStable, 30_000 ether);
        assertEq(stats.executionDelay, REDEMPTION_DELAY);
    }
}
