// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ObeliskTestBase } from "./helpers/ObeliskTestBase.sol";
import { ObeliskReservePool } from "../src/core/ObeliskReservePool.sol";
import { SolvencySnapshot, PositionView } from "../src/types/ObeliskTypes.sol";

contract MintBurnTest is ObeliskTestBase {
    function testOpenPositionMintsAgainstReserveCollateral() public {
        uint256 id = _open(alice, 1_000_000 * 1e6, 500_000 ether);

        PositionView memory view_ = reservePool.positionView(id);
        assertEq(view_.owner, alice);
        assertEq(view_.asset, address(usdc));
        assertEq(view_.collateralAmount, 1_000_000 * 1e6);
        assertEq(view_.debt, 500_000 ether);
        assertEq(stablecoin.balanceOf(alice), 500_000 ether);
        assertEq(stablecoin.totalSupply(), 500_000 ether);
        assertEq(reservePool.visibleReserveRatioBps(), 20_000);
    }

    function testBurnDebtAndWithdrawCollateral() public {
        uint256 id = _open(alice, 1_000_000 * 1e6, 500_000 ether);

        vm.prank(alice);
        uint256 burned = reservePool.burnStable(id, 200_000 ether);
        assertEq(burned, 200_000 ether);
        assertEq(stablecoin.totalSupply(), 300_000 ether);
        assertEq(debtBook.debtOf(id), 300_000 ether);

        uint256 balanceBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        reservePool.withdrawCollateral(id, 100_000 * 1e6, alice);

        assertEq(usdc.balanceOf(alice), balanceBefore + 100_000 * 1e6);
        assertEq(debtBook.collateralOf(id), 900_000 * 1e6);
        assertGt(reservePool.positionHealthBps(id), 20_000);
    }

    function testMintingRespectsPositionCapacity() public {
        uint256 id = _open(alice, 100_000 * 1e6, 50_000 ether);

        vm.expectRevert();
        vm.prank(alice);
        reservePool.mintStable(id, 50_000 ether, alice);
    }

    function testGuardianCanPauseMinting() public {
        uint256 id = _open(alice, 500_000 * 1e6, 100_000 ether);
        reservePool.setMintingPaused(true);

        vm.expectRevert(ObeliskReservePool.ReservePoolMintingPaused.selector);
        vm.prank(alice);
        reservePool.mintStable(id, 10_000 ether, alice);

        reservePool.setMintingPaused(false);
        vm.prank(alice);
        reservePool.mintStable(id, 10_000 ether, alice);
        assertEq(stablecoin.balanceOf(alice), 110_000 ether);
    }

    function testLensReturnsProtocolSnapshot() public {
        _open(alice, 1_000_000 * 1e6, 400_000 ether);

        SolvencySnapshot memory snapshot = lens.protocolSnapshot();
        assertEq(snapshot.activeSupply, 400_000 ether);
        assertEq(snapshot.reserveValue, 1_000_000 ether);
        assertEq(snapshot.reserveRatioBps, 25_000);
        assertTrue(snapshot.mintingAllowed);
    }
}
