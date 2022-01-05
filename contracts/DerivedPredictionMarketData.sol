// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract DerivedPredictionMarketData {
    struct Question {
        address collateral;
        address maker;
        address resolver;
        string title;
        uint256 questionId;
        uint256 resolveTime;
        uint256 funding;
        uint256 fee;
        uint256 slotIndex;
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
        address indexed collateral,
        address indexed maker,
        address indexed resolver,
        string title,
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
        uint256 short
    );

    // Generate Hashed QuestionID
    function generateQuestionId(
        address _collateral,
        address _maker,
        string memory _title
    ) public view returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        _collateral,
                        _maker,
                        _title,
                        block.timestamp
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
