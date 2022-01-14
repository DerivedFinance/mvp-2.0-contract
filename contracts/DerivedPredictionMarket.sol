// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./DerivedPredictionMarketData.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DerivedPredictionMarket is
    DerivedPredictionMarketData,
    ERC1155,
    ERC1155Burnable,
    ERC1155Holder,
    Ownable
{
    IERC20 public collateral;

    constructor(IERC20 _collateral) ERC1155("https://derived.fi/images/logo.png") {
        collateral = _collateral;

        setApprovalForAll(address(this), true);
    }

    modifier _checkQuestion(uint256 _questionId) {
        require(
            questions[_questionId].maker != address(0),
            "Invalid questionId"
        );
        _;
    }

    modifier _onlyResolver(uint256 _questionId) {
        require(
            questions[_questionId].resolver == msg.sender,
            "Invalid question resolver"
        );
        _;
    }

    modifier _onlyQuestionMaker(uint256 _questionId) {
        require(
            questions[_questionId].maker == msg.sender,
            "Invalid question maker"
        );
        _;
    }

    modifier _checkAvailableTradeFee(uint256 _questionId) {
        require(tradeFees[_questionId] > 0, "Not available trade fee");
        _;
    }

    modifier _checkResolvedQuestion(uint256 _questionId) {
        require(questions[_questionId].resolved, "Unresolved question");
        _;
    }

    modifier _checkUnResolvedQuestion(uint256 _questionId) {
        require(!questions[_questionId].resolved, "Resolved question");
        _;
    }

    modifier _canResolve(uint256 _questionId) {
        require(questions[_questionId].resolveTime <= block.timestamp);
        _;
    }

    /**
     * @dev See {IERC1155-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155, ERC1155Receiver) returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @notice Create question
     * @param _resolver question resolver
     * @param _meta question meta data uri
     * @param _resolveTime question resolve time
     * @param _funding initial funding
     * @param _fee trade fee
     */
    function createQuestion(
        address _resolver,
        string memory _meta,
        uint256 _resolveTime,
        uint256 _funding,
        uint256 _fee
    ) external onlyOwner returns (uint256 questionId) {
        require(_funding > 0, "Invalid initial funding amount");
        require(_fee < 100, "Invalid trade fee rate");
        require(_resolveTime > block.timestamp, "Invalid resolve time");

        // Transfer collateral token
        collateral.transferFrom(msg.sender, address(this), _funding);

        questionId = generateQuestionId(msg.sender, _meta);

        // Create question
        Question storage question = questions[questionId];
        question.maker = msg.sender;
        question.resolver = _resolver;
        question.meta = _meta;
        question.questionId = questionId;
        question.resolveTime = _resolveTime;
        question.funding = _funding;
        question.fee = _fee;

        // Create market data
        MarketData storage market = markets[questionId];
        market.long = _funding;
        market.short = _funding;
        market.lpVolume = _funding;

        totalQuestions ++;

        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        for (uint256 i = 0; i < 2; i++) {
            ids[i] = generateAnswerId(questionId, i);
            amounts[i] = _funding;
        }

        _mintBatch(address(this), ids, amounts, "");

        uint256[2] memory prices = getAnswerPrices(questionId);

        emit QuestionCreated(
            question.maker,
            question.resolver,
            question.meta,
            question.questionId,
            question.resolveTime,
            question.funding,
            question.fee,
            prices[0],
            prices[1]
        );
    }

    function resolveQuestion(uint256 _questionId, uint256 _slotIndex)
        external
        onlyOwner
        _checkQuestion(_questionId)
        _checkUnResolvedQuestion(_questionId)
        _canResolve(_questionId)
    {
        require(_slotIndex < 2, "Invalid answer");

        Question storage question = questions[_questionId];
        question.resolved = true;
        question.slotIndex = _slotIndex;

        emit QuestionResolved(_questionId, _slotIndex);
    }

    function redeemRewards(uint256 _questionId)
        external
        _checkQuestion(_questionId)
        _checkResolvedQuestion(_questionId)
    {
        uint256 slotIndex = questions[_questionId].slotIndex;
        uint256 answerId = generateAnswerId(_questionId, slotIndex);
        uint256 balance = balanceOf(msg.sender, answerId);
        uint256 total;

        if (slotIndex == 0) {
            total = markets[_questionId].long;
        } else {
            total = markets[_questionId].short;
        }

        require(balance > 0, "Not available to redeem");
        _burn(msg.sender, answerId, balance);

        uint256 amount = markets[_questionId].lpVolume * balance / total;
        collateral.transfer(msg.sender, amount);

        markets[_questionId].lpVolume -= amount;
        if (slotIndex == 0) {
            markets[_questionId].long -= balance;
        } else {
            markets[_questionId].short -= balance;
        }
    }

    function redeemTradeFee(uint256 _questionId)
        external
        _onlyQuestionMaker(_questionId)
        _checkAvailableTradeFee(_questionId)
    {
        collateral.transfer(
            msg.sender,
            tradeFees[_questionId]
        );
        tradeFees[_questionId] = 0;
    }

    /**
     * @notice Buy Shares
     * @param _questionId questionId
     * @param _amount collateral token amount
     * @param _slotIndex [LONG, SHORT] index
     */
    function buy(
        uint256 _questionId,
        uint256 _amount,
        uint256 _slotIndex
    )
        external
        _checkQuestion(_questionId)
        _checkUnResolvedQuestion(_questionId)
    {
        require(_amount > 0, "Invalid buy amount");
        require(_slotIndex < 2, "Invalid answer");

        uint256 amount = _addTradeFee(_questionId, _amount);
        collateral.transferFrom(
            msg.sender,
            address(this),
            amount
        );
        markets[_questionId].lpVolume += amount;
        markets[_questionId].tradeVolume += amount;

        _mintShares(_questionId, amount, _slotIndex, msg.sender);

        uint256[2] memory prices = getAnswerPrices(_questionId);

        emit Trade(
            "BUY",
            _questionId,
            prices[0],
            prices[1],
            markets[_questionId].lpVolume,
            markets[_questionId].tradeVolume,
            amount
        );
    }

    /**
     * @notice Sell Shares
     * @param _questionId questionId
     * @param _amount shares amount
     * @param _slotIndex [LONG, SHORT] index
     */
    function sell(
        uint256 _questionId,
        uint256 _amount,
        uint256 _slotIndex
    )
        external
        _checkQuestion(_questionId)
        _checkUnResolvedQuestion(_questionId)
    {
        require(_amount > 0, "Invalid sell amount");
        require(_slotIndex < 2, "Invalid answer");

        uint256 amount = _burnShares(_questionId, _amount, _slotIndex);

        uint256[2] memory prices = getAnswerPrices(_questionId);

        emit Trade(
            "SELL",
            _questionId,
            prices[0],
            prices[1],
            markets[_questionId].lpVolume,
            markets[_questionId].tradeVolume,
            amount
        );
    }

    function _mintShares(
        uint256 _questionId,
        uint256 _collateralAmount,
        uint256 _slotIndex,
        address _spender
    ) private returns (uint256 amount) {
        uint256[2] memory prices = getAnswerPrices(_questionId);
        uint256 answerId = generateAnswerId(_questionId, _slotIndex);
        amount = _collateralAmount / prices[_slotIndex] * 1e18;

        _mint(_spender, answerId, amount, "");

        if (_slotIndex == 0) {
            markets[_questionId].long += amount;
        } else {
            markets[_questionId].short += amount;
        }
    }

    function _burnShares(
        uint256 _questionId,
        uint256 _amount,
        uint256 _slotIndex
    ) private returns (uint256 collateralAmount) {
        uint256 answerId = generateAnswerId(_questionId, _slotIndex);
        require(balanceOf(msg.sender, answerId) >= _amount, "Overflow amount");
        _burn(msg.sender, answerId, _amount);

        uint256[2] memory prices = getAnswerPrices(_questionId);
        collateralAmount = (_amount * prices[_slotIndex]) / 1e18;
        collateralAmount = _addTradeFee(_questionId, collateralAmount);

        markets[_questionId].lpVolume -= collateralAmount;
        markets[_questionId].tradeVolume += collateralAmount;
        collateral.transfer(
            msg.sender,
            collateralAmount
        );
    }

    function _addTradeFee(uint256 _questionId, uint256 _amount)
        private
        returns (uint256 fee)
    {
        fee = (_amount * (100 - questions[_questionId].fee)) / 100;
        tradeFees[_questionId] += _amount - fee;
    }

    // View Functions
    function getVolume(uint256 _questionId)
        public
        view
        _checkQuestion(_questionId)
        returns (uint256)
    {
        return markets[_questionId].long + markets[_questionId].short;
    }

    function getQuestionStatus(uint256 _questionId)
        public
        view
        _checkQuestion(_questionId)
        returns (bool)
    {
        return questions[_questionId].resolved;
    }

    function getAnswerPrices(uint256 _questionId)
        public
        view
        _checkQuestion(_questionId)
        returns (uint256[2] memory)
    {
        return [
            (markets[_questionId].long * 1e18) / getVolume(_questionId), // LONG
            (markets[_questionId].short * 1e18) / getVolume(_questionId) // SHORT
        ];
    }
}
