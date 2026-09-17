// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AntiBondingCurve.sol";
import "../src/MockUSDC.sol";

contract BasicTest is Test {
    MockUSDC usdc;
    AntiBondingCurve curve;

    address alice = address(0xA11CE);

    function setUp() public {
        usdc = new MockUSDC();

        curve = new AntiBondingCurve(
            usdc,
            1e18,       // initial price = 1
            45e12,      // slope
            0.10e18,    // floor = 0.10
            20000e18,   // max curve supply
            100,        // 1% fee
            5000        // 50% of fees to growth reserve
        );

        usdc.faucet(
            alice,
            100000e18
        );

        vm.prank(alice);

        usdc.approve(
            address(curve),
            type(uint256).max
        );
    }

    function testBuyMakesPriceFall() public {
        uint256 beforePrice =
            curve.price();

        vm.prank(alice);

        curve.buy(
            1000e18,
            type(uint256).max
        );

        uint256 afterPrice =
            curve.price();

        assertLt(
            afterPrice,
            beforePrice
        );
    }

    function testSellMakesPriceRise() public {
        vm.prank(alice);

        curve.buy(
            1000e18,
            type(uint256).max
        );

        uint256 beforePrice =
            curve.price();

        vm.prank(alice);

        curve.sell(
            500e18,
            0
        );

        uint256 afterPrice =
            curve.price();

        assertGt(
            afterPrice,
            beforePrice
        );
    }
}
