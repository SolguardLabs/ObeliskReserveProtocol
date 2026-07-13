// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ObeliskTestBase } from "./helpers/ObeliskTestBase.sol";
import { Bucket, BucketState } from "../src/types/ObeliskTypes.sol";

contract BackstopAndBucketsTest is ObeliskTestBase {
    function testBackstopRecapitalizesReserveBucket() public {
        vm.prank(lp);
        uint256 shares = backstop.deposit(address(usdc), 200_000 * 1e6, lp);
        assertEq(shares, 200_000 * 1e6);

        uint256 poolBalanceBefore = usdc.balanceOf(address(reservePool));
        uint256 burnedShares = reservePool.recapitalize(address(usdc), 50_000 * 1e6);

        assertEq(usdc.balanceOf(address(reservePool)), poolBalanceBefore + 50_000 * 1e6);
        assertEq(backstop.managedLiquidity(address(usdc)), 150_000 * 1e6);
        assertEq(backstop.totalShares(address(usdc)), 200_000 * 1e6);
        assertEq(burnedShares, 0);
        assertEq(buckets.bucketBalance(address(usdc), Bucket.Backstop), 50_000 * 1e6);
    }

    function testBucketSplitFollowsRegisteredWeights() public {
        _open(alice, 1_000_000 * 1e6, 300_000 ether);

        BucketState memory state = buckets.stateOf(address(usdc));
        assertEq(state.immediate, 550_000 * 1e6);
        assertEq(state.deferred, 250_000 * 1e6);
        assertEq(state.strategic, 150_000 * 1e6);
        assertEq(state.backstop, 50_000 * 1e6);
    }

    function testAllocatorCanRebalanceBuckets() public {
        _open(alice, 1_000_000 * 1e6, 300_000 ether);

        reservePool.rebalanceBuckets(
            address(usdc), Bucket.Strategic, Bucket.Immediate, 20_000 * 1e6
        );

        BucketState memory state = buckets.stateOf(address(usdc));
        assertEq(state.immediate, 570_000 * 1e6);
        assertEq(state.strategic, 130_000 * 1e6);
    }

    function testBackstopWithdrawReflectsProvidedLiquidity() public {
        vm.startPrank(lp);
        uint256 shares = backstop.deposit(address(usdc), 100_000 * 1e6, lp);
        vm.stopPrank();

        reservePool.recapitalize(address(usdc), 40_000 * 1e6);

        uint256 balanceBefore = usdc.balanceOf(lp);
        vm.prank(lp);
        uint256 withdrawn = backstop.withdraw(address(usdc), shares / 2, lp);

        assertEq(withdrawn, 30_000 * 1e6);
        assertEq(usdc.balanceOf(lp), balanceBefore + 30_000 * 1e6);
    }
}
