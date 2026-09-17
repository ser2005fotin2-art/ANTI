// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract AntiToken is ERC20 {
    address public immutable curve;
    error OnlyCurve();

    constructor(address curve_) ERC20("ANTI", "ANTI") {
        curve = curve_;
    }

    function mint(address to, uint256 amount) external {
        if (msg.sender != curve) revert OnlyCurve();
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        if (msg.sender != curve) revert OnlyCurve();
        _burn(from, amount);
    }
}
