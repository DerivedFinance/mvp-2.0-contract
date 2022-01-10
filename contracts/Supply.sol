// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SupplyData {
    // Starting tokens (80000000)
    uint256 public INITIAL_SUPPLY = 80000000 * 1e18;

    // Beginning annual inflation (120%)
    uint256 public ANNUAL_INFLATION = 120;

    // Week that % reduction in emmisions starts (52)
    uint256 public WEEK_START = 52;

    // Weekly emmisions reduction multiplier (0.986745700459466 * 1e18)
    uint256 public WEEK_REDUCTION_FACTOR = 98674570045946600;

    // Weekly emmisions reduction (1.33%)
    uint256 public WEEK_REDUCTION = 1325429954053400;

    // Fixed # or fixed % inflation Selector (0)
    uint256 public FINAL_EMISSION = 0;

    // Fixed absolute (#) ongoing inflation weekly (100,000)
    uint256 public FINAL_WEEKLY_EMISSION = 100000;

    // Fixed percentage (%) ongoing inflation (2%)
    uint256 public INFLATION_FIXED_PERCENTAGE = 2;

    // Week that ending annual inflation starts (260)
    uint256 public WEEK_INFLATION_END = 260;

    // Weeks between beginning and end inflation (208)
    uint256 public WEEK_DIFF = 208;

    // Mint period duration
    uint256 public MINT_PERIOD_DURATION = 1 weeks;
}

contract Supply is Ownable, SupplyData {
    // Collateral Tokens
    IERC20 public collateral;

    // Start Week
    uint256 public weekStart;

    // End Week
    uint256 public weekEnd;

    constructor(
        address _collateral,
        uint256 _weekStart,
        uint256 _weekEnd
    ) {
        collateral = IERC20(_collateral);
        weekStart = _weekStart;
        weekEnd = _weekEnd;
    }
}
