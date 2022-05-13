// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BinaryMarketData {
    struct Question {
        string meta;
        uint256 resolveTime;
        uint256 initialLiquidity;
        uint8 fee;
        uint8 slot;
        bool isPaused;
    }

    struct Market {
        uint256 slot1;
        uint256 slot2;
        uint256 volume;
        uint256 reward;
    }

    Question[] public questions;

    /**
     * @notice Market Data
     * @dev questionId => market data
     */
    mapping(uint256 => Market) public markets;

    mapping(uint256 => uint256) public tradeFees;

    IERC20 public token;

    event QuestionCreated(
        string title,
        string meta,
        string category,
        uint256 questionId,
        uint256 resolveTime,
        uint256 initialLiquidity,
        uint8 fee
    );

    event QuestionResolved(uint256 questionId, uint8 slot);

    event Trade(
        uint256 questionId,
        uint256 slot1,
        uint256 slot2,
        uint256 tokensAmount,
        uint256 sharesAmount,
        uint8 slot,
        uint8 trade,
        address trader
    );

    event TradePaused(uint256 questionId);
}
