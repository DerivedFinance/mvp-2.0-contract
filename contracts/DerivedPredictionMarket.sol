// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./DerivedPredictionMarketData.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract DerivedPredictionMarket is
    DerivedPredictionMarketData,
    ERC1155,
    ERC1155Burnable,
    ERC1155Holder,
    Ownable,
    ReentrancyGuard
{
    using SafeMath for uint256;

    IERC20 public collateral;

    constructor(IERC20 _collateral)
        ERC1155("https://derived.fi/images/logo.png")
    {
        collateral = _collateral;

        setApprovalForAll(address(this), true);
    }

    /**
     * @dev See {IERC1155-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155, ERC1155Receiver)
        returns (bool)
    {
        return
            interfaceId == type(IERC1155Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
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
        string memory _title,
        string memory _meta,
        string memory _category,
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
        question.title = _title;
        question.meta = _meta;
        question.category = _category;
        question.questionId = questionId;
        question.resolveTime = _resolveTime;
        question.funding = _funding;
        question.fee = _fee;

        // Create market data
        MarketData storage market = markets[questionId];
        
        // Consider initial Liquidity for LP Volume
        market.long = _funding;
        market.short = _funding;
        market.lpVolume = _funding;

        totalQuestions = totalQuestions.add(1);

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
            question.title,
            question.meta,
            question.category,
            question.questionId,
            question.resolveTime,
            question.funding,
            question.fee,
            prices[0],
            prices[1]
        );
    }

    // Invoked only by owner in case of any issues to pause the BO
    function pauseTrade(uint256 _questionId)
        external
        onlyOwner
        _checkQuestion(_questionId)
        _checkUnResolvedQuestion(_questionId)
        _onlyUnpaused(_questionId)
    {
        marketStatus[_questionId] = true;
        emit TradePaused(_questionId);
    }

    function unpauseTrade(uint256 _questionId)
        external
        onlyOwner
        _checkQuestion(_questionId)
        _checkUnResolvedQuestion(_questionId)
        _onlyPaused(_questionId)
    {
        marketStatus[_questionId] = false;
        emit TradeUnpaused(_questionId);
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

        // Redeem the trade fee from the contract. Assume at least one trade will be done on the contract
        redeemTradeFee(_questionId);

        // Emit question resolved event
        emit QuestionResolved(_questionId, _slotIndex);
    }

    // Function to let the user claim the rewards
    function redeemRewards(uint256 _questionId)
        public
        nonReentrant
        _checkQuestion(_questionId)
        _checkResolvedQuestion(_questionId)
    {
        uint256 slotIndex = questions[_questionId].slotIndex;
        uint256 answerId = generateAnswerId(_questionId, slotIndex);
        uint256 balance = balanceOf(msg.sender, answerId);
        uint256 total;

        MarketData storage market = markets[_questionId];

        if (slotIndex == 0) {
            total = market.long;
        } else {
            total = market.short;
        }

        require(balance > 0, "Not available to redeem");
        _burn(msg.sender, answerId, balance);

        uint256 amount = (market.lpVolume.mul(balance)).div(total);
        bool _sent = collateral.transfer(msg.sender, amount);
        require(_sent,"Rewards not sent");

        market.lpVolume = market.lpVolume.sub(amount);
        if (slotIndex == 0) {
            market.long = market.long.sub(balance);
        } else {
            market.short = market.short.sub(balance);
        }
    }

    // Function to redeem the trade fee
    function redeemTradeFee(uint256 _questionId)
        public
        nonReentrant
        _onlyQuestionMaker(_questionId)
        _checkAvailableTradeFee(_questionId)
    {
        // Transfer the trade fee to the admin wallet
        bool _sent = collateral.transfer(msg.sender, tradeFees[_questionId]);
        require(_sent,"Trade Fee not sent");
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
        nonReentrant
        _checkQuestion(_questionId)
        _checkUnResolvedQuestion(_questionId)
        _onlyUnpaused(_questionId)
    {
        require(_amount > 0, "Invalid buy amount");
        require(_slotIndex < 2, "Invalid answer");

        uint256 amount = _addTradeFee(_questionId, _amount);
        //svderived changes to transfer full amount (share price + trading fee) from user's wallet
        //collatebral.transferFrom(msg.sender, address(this), amount);
        collateral.transferFrom(msg.sender, address(this), _amount);

        MarketData storage market = markets[_questionId];
        market.lpVolume = market.lpVolume.add(amount);

        _mintShares(_questionId, amount, _slotIndex, msg.sender);

        uint256[2] memory prices = getAnswerPrices(_questionId);

        emit Trade(
            "BUY",
            _questionId,
            _slotIndex,
            prices[0],
            prices[1],
            market.lpVolume,
            market.tradeVolume,
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
        nonReentrant
        _checkQuestion(_questionId)
        _checkUnResolvedQuestion(_questionId)
        _onlyUnpaused(_questionId)
    {
        require(_amount > 0, "Invalid sell amount");
        require(_slotIndex < 2, "Invalid answer");

        uint256 amount = _burnShares(_questionId, _amount, _slotIndex);
        uint256[2] memory prices = getAnswerPrices(_questionId);
        MarketData memory market = markets[_questionId];

        emit Trade(
            "SELL",
            _questionId,
            _slotIndex,
            prices[0],
            prices[1],
            market.lpVolume,
            market.tradeVolume,
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
        amount = (_collateralAmount.mul(1e18)).div(prices[_slotIndex]);

        _mint(_spender, answerId, amount, "");

        MarketData storage market = markets[_questionId];
        if (_slotIndex == 0) {
            market.long = market.long.add(amount);
        } else {
            market.short = market.short.add(amount);
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
        collateralAmount = (_amount.mul(prices[_slotIndex])).div(1e18);
        collateralAmount = _addTradeFee(_questionId, collateralAmount);

        MarketData storage market = markets[_questionId];
         // Reduce the long / short side after sell
        if (_slotIndex == 0) {
            market.long = market.long.sub(collateralAmount);
        } else {
            market.short = market.short.sub(collateralAmount);
        }

        // Subtract the amount sold to the LP volume and add to trade volume 
        market.lpVolume = market.lpVolume.sub(collateralAmount);
        market.tradeVolume = market.tradeVolume.add(collateralAmount);
        bool _sent = collateral.transfer(msg.sender, collateralAmount);
        require(_sent,"Burn transfer failed");
    }

    // Function to calculate the trade fee and return the amount
    function _addTradeFee(uint256 _questionId, uint256 _amount)
        private
        returns (uint256 fee)
    {
        fee = (_amount.mul(uint256(100).sub(questions[_questionId].fee))).div(100);
        tradeFees[_questionId] = tradeFees[_questionId].add(_amount).sub(fee);
    }

    // View Functions
    function getVolume(uint256 _questionId)
        public
        view
        _checkQuestion(_questionId)
        returns (uint256)
    {
        return markets[_questionId].long.add(markets[_questionId].short);
    }

    // Function to check if question is resolved or not - Returns boolean value 
    function getQuestionStatus(uint256 _questionId)
        public
        view
        _checkQuestion(_questionId)
        returns (bool)
    {
        return questions[_questionId].resolved;
    }

    // function to get price on each side 
    function getAnswerPrices(uint256 _questionId)
        public
        view
        _checkQuestion(_questionId)
        returns (uint256[2] memory)
    {
        uint256 volume = getVolume(_questionId);
        if (volume == 0) {
            return [uint256(0), uint256(0)];
        }

        return [
            (markets[_questionId].long.mul(1e18)).div(volume), // LONG
            (markets[_questionId].short.mul(1e18)).div(volume) // SHORT
        ];
    }

    function getrewards(uint256 _questionId)
    public
    view
    returns(uint256)
    {
        uint256 slotIndex = questions[_questionId].slotIndex;
        uint256 answerId = generateAnswerId(_questionId, slotIndex);
        uint256 balance = balanceOf(msg.sender, answerId);
        uint256 total;

        MarketData storage market = markets[_questionId];

        // Get total long / short volume 
        if (slotIndex == 0) {
            total = market.long;
        } else {
            total = market.short;
        }

        uint256 amount = (market.lpVolume.mul(balance)).div(total);
        return amount; 

    }

        // EMERGENCY WITHDRAWAL OF FUNDS
    function recoverFunds(uint256 _questionId) 
    external onlyOwner {
        MarketData storage market = markets[_questionId];
        bool _sent = collateral.transfer(msg.sender, market.lpVolume);
        require(_sent, "Emergency Withdraw failed");
        emit RecoveredFunds(market.lpVolume);
        market.lpVolume = 0;
    }

    

    /* ============ MODIFIERS ============ */

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

    modifier _onlyPaused(uint256 _questionId) {
        require(marketStatus[_questionId], "Question is not paused");
        _;
    }

    modifier _onlyUnpaused(uint256 _questionId) {
        require(!marketStatus[_questionId], "Question is paused");
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

}
