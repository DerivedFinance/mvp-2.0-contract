// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./BinaryMarketData.sol";

contract BinaryMarket is
    BinaryMarketData,
    Ownable,
    ERC1155,
    ERC1155Burnable,
    ERC1155Holder,
    ReentrancyGuard
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;

    Counters.Counter private _questionIds;

    constructor(IERC20 _token) ERC1155("https://derived.fi/images/logo.png") {
        token = _token;
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

    // ------------------- OWNER PUBLIC -------------------

    function createQuestion(
        string memory _title,
        string memory _meta,
        string memory _category,
        uint256 _resolveTime,
        uint256 _initialLiquidity,
        uint8 _fee
    ) external onlyOwner {
        require(_initialLiquidity > 0, "Invalid initial funding amount");
        require(_fee >= 0 && _fee < 100, "Invalid trade fee rate");
        require(_resolveTime > block.timestamp, "Invalid resolve time");

        // Transfer token token
        token.transferFrom(msg.sender, address(this), _initialLiquidity);

        Question memory question;
        question.meta = _meta;
        question.resolveTime = _resolveTime;
        question.initialLiquidity = _initialLiquidity;
        question.fee = _fee;
        question.slot = 2;
        questions.push(question);

        Market storage market = markets[_questionIds.current()];
        market.slot1 = _initialLiquidity;
        market.slot2 = _initialLiquidity;
        market.volume = _initialLiquidity;

        emit QuestionCreated(
            _title,
            _meta,
            _category,
            _questionIds.current(),
            _resolveTime,
            _initialLiquidity,
            _fee
        );

        _questionIds.increment();
    }

    function resolveQuestion(uint256 _questionId, uint8 _slot)
        external
        onlyOwner
        onlyQuestion(_questionId)
        onlyUnResolved(_questionId)
    {
        require(_slot < 2, "Invalid Answer");
        require(questions[_questionId].resolveTime <= block.timestamp);

        Question storage question = questions[_questionId];
        question.slot = _slot;

        uint256 fee = tradeFees[_questionId];
        require(fee > 0, "No Fee");

        uint256 amount = fee.add(question.initialLiquidity);
        token.safeTransfer(msg.sender, amount);
        tradeFees[_questionId] = 0;

        Market storage market = markets[_questionId];
        uint256 tradeVolume = getTradeVolume(_questionId);
        if (_slot == 0) {
            uint256 slot1 = market.slot1.sub(question.initialLiquidity);
            if (slot1 == 0) {
                market.reward = 0;
            } else {
                market.reward = tradeVolume.mul(10**18).div(slot1);
            }
        } else {
            uint256 slot2 = market.slot2.sub(question.initialLiquidity);
            if (slot2 == 0) {
                market.reward = 0;
            } else {
                market.reward = tradeVolume.mul(10**18).div(slot2);
            }
        }

        emit QuestionResolved(_questionId, _slot);
    }

    // ========== EMERGENCY WITHDRAWAL OF FUNDS ============
    function recoverFunds(uint256 _questionId) external nonReentrant onlyOwner {
        uint256 amount = getClaimableReward(_questionId);
        require(amount > 0, "No Emergency Claimable Reward");

        token.safeTransfer(msg.sender, amount);
        markets[_questionId].reward = 0;

        emit RecoveredFunds(amount, msg.sender);
    }

    // ------------------- PUBLIC -------------------

    function buy(
        uint256 _questionId,
        uint256 _amount,
        uint8 _slot
    )
        external
        nonReentrant
        onlyQuestion(_questionId)
        onlyUnResolved(_questionId)
    {
        require(_slot < 2, "Invalid slot");
        require(_amount > 0, "Invalid Trade Amount");
        require(
            questions[_questionId].resolveTime >= block.timestamp,
            "Option already expired"
        );

        uint256 fee = getFee(_questionId, _amount);
        tradeFees[_questionId] = tradeFees[_questionId].add(fee);

        uint256 payAmount = _amount.sub(fee);
        token.safeTransferFrom(msg.sender, address(this), _amount);

        uint256[2] memory prices = getPrices(_questionId);
        uint256[2] memory slotIds = getSlotIds(_questionId);
        uint256 sharesAmount = payAmount.div(prices[_slot]).mul(10**18);

        _mint(msg.sender, slotIds[_slot], sharesAmount, "");

        Market storage market = markets[_questionId];
        market.volume = market.volume.add(payAmount);
        if (_slot == 0) {
            market.slot1 = market.slot1.add(sharesAmount);
        } else {
            market.slot2 = market.slot2.add(sharesAmount);
        }

        uint256[2] memory updatedPrices = getPrices(_questionId);
        emit Trade(
            _questionId,
            updatedPrices[0],
            updatedPrices[1],
            _amount,
            sharesAmount,
            _slot,
            uint8(0),
            msg.sender
        );
    }

    function sell(
        uint256 _questionId,
        uint256 _amount,
        uint8 _slot
    )
        external
        nonReentrant
        onlyQuestion(_questionId)
        onlyUnResolved(_questionId)
        returns (uint256 payAmount)
    {
        require(_slot < 2, "Invalid slot");
        require(_amount > 0, "Invalid Trade Amount");
        require(
            questions[_questionId].resolveTime >= block.timestamp,
            "Option already expired"
        );

        uint256[2] memory slotIds = getSlotIds(_questionId);
        require(
            balanceOf(msg.sender, slotIds[_slot]) >= _amount,
            "Insufficient Amount"
        );
        require(
            _amount <= getSharesMaxSell(_questionId, _slot),
            "Insufficient liquidity"
        );

        Market storage market = markets[_questionId];
        uint256[2] memory prices = getPrices(_questionId);
        uint256 tokenAmount = prices[_slot].mul(_amount).div(10**18);
        uint256 fee = getFee(_questionId, tokenAmount);
        payAmount = tokenAmount.sub(fee);

        _burn(msg.sender, slotIds[_slot], _amount);

        tradeFees[_questionId] = tradeFees[_questionId].add(fee);
        token.safeTransfer(msg.sender, payAmount);

        market.volume = market.volume.add(tokenAmount); //volume should increase on buy and sell both
        if (_slot == 0) {
            market.slot1 = market.slot1.sub(_amount);
        } else {
            market.slot2 = market.slot2.sub(_amount);
        }

        uint256[2] memory updatedPrices = getPrices(_questionId);
        emit Trade(
            _questionId,
            updatedPrices[0],
            updatedPrices[1],
            _amount,
            payAmount,
            _slot,
            uint8(1),
            msg.sender
        );
    }

    function claim(uint256 _questionId)
        external
        nonReentrant
        onlyQuestion(_questionId)
        onlyResolved(_questionId)
    {
        uint256 slot = questions[_questionId].slot;
        uint256[2] memory slotIds = getSlotIds(_questionId);
        uint256 amount = getClaimableReward(_questionId);
        require(amount > 0, "No Claimable Reward");

        uint256 balance = balanceOf(msg.sender, slotIds[slot]);
        require(balance > 0, "No Balance");

        _burn(msg.sender, slotIds[slot], balance);
        token.safeTransfer(msg.sender, amount);
    }

    // ------------------- GETTERS -------------------

    function getTotalQuestions() public view returns (uint256) {
        return _questionIds.current();
    }

    function getShares(uint256 _questionId) public view returns (uint256) {
        Market memory market = markets[_questionId];
        return market.slot1.add(market.slot2);
    }

    function getPrices(uint256 _questionId)
        public
        view
        returns (uint256[2] memory)
    {
        uint256 shares = getShares(_questionId);
        if (shares == 0) {
            return [uint256(5).mul(10**17), uint256(5).mul(10**17)];
        }

        Market memory market = markets[_questionId];
        return [
            market.slot1.mul(10**18).div(shares),
            market.slot2.mul(10**18).div(shares)
        ];
    }

    function getSlotIds(uint256 _questionId)
        public
        pure
        returns (uint256[2] memory)
    {
        return [_questionId * 2, _questionId * 2 + 1];
    }

    function getFee(uint256 _questionId, uint256 _amount)
        public
        view
        returns (uint256)
    {
        Question memory question = questions[_questionId];
        return _amount.mul(question.fee).div(100);
    }

    function getClaimableReward(uint256 _questionId)
        public
        view
        returns (uint256)
    {
        Market memory market = markets[_questionId];
        uint256 slot = questions[_questionId].slot;
        uint256[2] memory slotIds = getSlotIds(_questionId);
        uint256 balance = balanceOf(msg.sender, slotIds[slot]);
        uint256 amount = balance.mul(market.reward).div(10**18);
        return amount;
    }

    function getMarketVolume(uint256 _questionId)
        public
        view
        returns (uint256)
    {
        return markets[_questionId].volume;
    }

    function getTradeVolume(uint256 _questionId) public view returns (uint256) {
        return
            getMarketVolume(_questionId).sub(
                questions[_questionId].initialLiquidity
            );
    }

    function getSharesMaxSell(uint256 _questionId, uint8 _slot)
        public
        view
        returns (uint256)
    {
        uint256[2] memory prices = getPrices(_questionId);
        uint256 volume = getTradeVolume(_questionId);
        return volume.mul(10**18).div(prices[_slot]);
    }

    function getQuestionsLength() public view returns (uint256) {
        return questions.length;
    }

    // ------------------- MODIFIERS -------------------

    modifier onlyQuestion(uint256 id) {
        require(id < getTotalQuestions(), "Invalid Question");
        _;
    }

    modifier onlyResolved(uint256 id) {
        require(questions[id].slot != 3, "Not resolved question");
        _;
    }

    modifier onlyUnResolved(uint256 id) {
        require(questions[id].slot == 2, "Already resolved question");
        _;
    }
}
