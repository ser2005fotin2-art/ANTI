// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AntiToken} from "./AntiToken.sol";

/// @notice ANTI V0 — inverse-pressure bonding curve.
/// BUY  -> curveSupply increases -> price decreases.
/// SELL -> curveSupply decreases -> price increases.
///
/// WARNING: experimental prototype. Not production-ready.
contract AntiBondingCurve {
    using SafeERC20 for IERC20;

    uint256 public constant WAD = 1e18;

    IERC20 public immutable quoteToken;
    AntiToken public immutable anti;

    // Initial price of 1 ANTI, in quote-token units.
    uint256 public immutable initialPrice;

    // Price decrease per 1 ANTI of curveSupply.
    uint256 public immutable slope;

    // Absolute minimum price.
    uint256 public immutable floorPrice;

    // Maximum amount represented by the curve.
    uint256 public immutable maxCurveSupply;

    // Trading fee in basis points.
    // 100 = 1%.
    uint256 public immutable feeBps;

    // Percentage of fees retained in growthReserve.
    // 5000 = 50%.
    uint256 public immutable growthShareBps;

    uint256 public curveSupply;
    uint256 public growthReserve;

    error InvalidConfig();
    error BadAmount();
    error MaxSupply();
    error NotEnoughTokens();
    error Slippage();
    error InsufficientReserve();

    event Bought(
        address indexed user,
        uint256 amount,
        uint256 cost,
        uint256 fee
    );

    event Sold(
        address indexed user,
        uint256 amount,
        uint256 payout,
        uint256 fee
    );

    constructor(
        IERC20 quoteToken_,
        uint256 initialPrice_,
        uint256 slope_,
        uint256 floorPrice_,
        uint256 maxCurveSupply_,
        uint256 feeBps_,
        uint256 growthShareBps_
    ) {
        if (
            address(quoteToken_) == address(0) ||
            initialPrice_ == 0 ||
            floorPrice_ == 0 ||
            floorPrice_ > initialPrice_ ||
            maxCurveSupply_ == 0 ||
            feeBps_ > 1000 ||
            growthShareBps_ > 10000
        ) {
            revert InvalidConfig();
        }

        quoteToken = quoteToken_;
        initialPrice = initialPrice_;
        slope = slope_;
        floorPrice = floorPrice_;
        maxCurveSupply = maxCurveSupply_;
        feeBps = feeBps_;
        growthShareBps = growthShareBps_;

        anti = new AntiToken(address(this));
    }

    /// @notice Current marginal price.
    function price() public view returns (uint256) {
        return _priceAt(curveSupply);
    }

    /// @notice Cost of buying amount before fees.
    function buyCost(uint256 amount) public view returns (uint256) {
        if (amount == 0) {
            revert BadAmount();
        }

        if (curveSupply + amount > maxCurveSupply) {
            revert MaxSupply();
        }

        uint256 p0 = price();
        uint256 p1 = _priceAt(curveSupply + amount);

        // Integral of a linear curve = trapezoid.
        return (amount * (p0 + p1)) / (2 * WAD);
    }

    /// @notice Gross amount received from selling amount.
    function sellReturn(uint256 amount) public view returns (uint256) {
        if (amount == 0) {
            revert BadAmount();
        }

        if (amount > curveSupply) {
            revert NotEnoughTokens();
        }

        uint256 p0 = price();
        uint256 p1 = _priceAt(curveSupply - amount);

        return (amount * (p0 + p1)) / (2 * WAD);
    }

    /// @notice Buy ANTI using the quote token.
    function buy(
        uint256 amount,
        uint256 maxPayment
    ) external {
        uint256 cost = buyCost(amount);

        uint256 fee = (cost * feeBps) / 10000;
        uint256 total = cost + fee;

        if (total > maxPayment) {
            revert Slippage();
        }

        quoteToken.safeTransferFrom(
            msg.sender,
            address(this),
            total
        );

        growthReserve +=
            (fee * growthShareBps) /
            10000;

        curveSupply += amount;

        anti.mint(msg.sender, amount);

        emit Bought(
            msg.sender,
            amount,
            cost,
            fee
        );
    }

    /// @notice Sell ANTI back to the curve.
    function sell(
        uint256 amount,
        uint256 minPayout
    ) external {
        uint256 gross = sellReturn(amount);

        uint256 fee = (gross * feeBps) / 10000;
        uint256 payout = gross - fee;

        if (payout < minPayout) {
            revert Slippage();
        }

        if (
            quoteToken.balanceOf(address(this)) <
            payout
        ) {
            revert InsufficientReserve();
        }

        anti.burn(msg.sender, amount);

        curveSupply -= amount;

        growthReserve +=
            (fee * growthShareBps) /
            10000;

        quoteToken.safeTransfer(
            msg.sender,
            payout
        );

        emit Sold(
            msg.sender,
            amount,
            payout,
            fee
        );
    }

    function _priceAt(
        uint256 supply
    ) internal view returns (uint256) {
        uint256 drop = slope * supply;

        if (
            drop >=
            initialPrice - floorPrice
        ) {
            return floorPrice;
        }

        return initialPrice - drop;
    }
}
