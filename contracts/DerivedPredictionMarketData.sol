// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract DerivedPredictionMarketData {
    struct Question {
        address token;
        address maker;
        address resolver;
        string meta;
        uint256 questionId;
        uint256 resolveTime;
        uint256 funding;
        uint256 fee;
        uint256 slotIndex;
        uint256 strikePrice;
        bool resolved;
    }

    struct MarketData {
        uint256 long; // LONG shares amount
        uint256 short; // SHORT shares amount
        uint256 lpVolume; // ERC20 liquidity volume
        uint256 tradeVolume; // ERC20 trade volume
    }

    uint256 public totalQuestions;
    /**
     * @notice Questions data
     * @dev questionId => question data
     */
    mapping(uint256 => Question) public questions;

    /**
     * @notice Trade fee for question makers
     * @dev questionId => fee
     */
    mapping(uint256 => uint256) public tradeFees;

    /**
     * @notice Market Data
     * @dev questionId => market data
     */
    mapping(uint256 => MarketData) public markets;

    // Events
    event QuestionCreated(
        address indexed maker,
        address indexed resolver,
        string meta,
        uint256 questionId,
        uint256 resolveTime,
        uint256 funding,
        uint256 fee,
        uint256 long,
        uint256 short
    );
    event QuestionResolved(uint256 questionId, uint256 slotIndex);
    event Trade(
        uint256 questionId,
        uint256 long,
        uint256 short,
        uint256 lpVolume,
        uint256 tradeVolume
    );

    // Generate Hashed QuestionID
    function generateQuestionId(
        address _maker,
        string memory _meta
    ) public pure returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        _maker,
                        _meta
                    )
                )
            );
    }

    // Generate Hashed AnswerID from QuestionID
    function generateAnswerId(uint256 _questionId, uint256 _slotIndex)
        public
        pure
        returns (uint256)
    {
        return uint256(keccak256(abi.encodePacked(_questionId, _slotIndex)));
    }
}
