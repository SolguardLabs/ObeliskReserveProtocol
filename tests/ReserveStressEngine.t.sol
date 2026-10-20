// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { ReserveStressEngine } from "../src/analytics/ReserveStressEngine.sol";

contract ReserveStressEngineTest is Test {
    ReserveStressEngine internal engine;

    function setUp() public {
        engine = new ReserveStressEngine();
    }

    function testScenarioShowsHaircutAndTargetShortfall() public view {
        uint256[] memory values = new uint256[](2);
        values[0] = 600_000 ether;
        values[1] = 400_000 ether;
        uint16[] memory haircuts = new uint16[](2);
        haircuts[0] = 1000;
        haircuts[1] = 2500;

        ReserveStressEngine.Scenario memory result =
            engine.assess(values, haircuts, 600_000 ether, 15_000);
        assertEq(result.grossValue, 1_000_000 ether);
        assertEq(result.stressedValue, 840_000 ether);
        assertEq(result.stressedRatioBps, 14_000);
        assertEq(result.requiredAtTarget, 900_000 ether);
        assertEq(result.shortfallAtTarget, 60_000 ether);
        assertEq(result.concentrationBps, 5200);
    }

    function testWaterfallQuotesBucketOrderAndUnfilledAmount() public view {
        uint256[4] memory balances = [uint256(100), 50, 30, 20];
        (uint256[4] memory used, uint256 shortfall) = engine.quoteWaterfall(balances, 130);
        assertEq(used[0], 100);
        assertEq(used[1], 30);
        assertEq(used[2], 0);
        assertEq(shortfall, 0);

        (used, shortfall) = engine.quoteWaterfall(balances, 220);
        assertEq(used[0] + used[1] + used[2] + used[3], 200);
        assertEq(shortfall, 20);
    }

    function testInvalidScenarioInputsRevert() public {
        uint256[] memory values = new uint256[](1);
        values[0] = 1 ether;
        uint16[] memory haircuts = new uint16[](1);
        haircuts[0] = 10_001;
        vm.expectRevert(
            abi.encodeWithSelector(
                ReserveStressEngine.InvalidHaircut.selector, uint256(0), uint256(10_001)
            )
        );
        engine.assess(values, haircuts, 1 ether, 12_500);
    }
}
