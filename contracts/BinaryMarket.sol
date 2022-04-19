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

contract BinaryMarketData {
    struct Question {
        string meta;
        uint256 resolveTime;
        uint256 initialLiquidity;
        uint8 fee;
        uint8 slot;
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

    IERC20 public collateral;

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
}

contract BinaryMarket is
    BinaryMarketData,
    Ownable,
    ERC1155,
    ERC1155Burnable,
    ERC1155Holder
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;

    Counters.Counter private _questionIds;

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

    // ------------------- OWNER PUBLIC -------------------

    /**
     * @notice Create question
     * @param _meta question meta data uri
     * @param _resolveTime question resolve time
     * @param _initialLiquidity initial funding
     * @param _fee trade fee
     */
    function createQuestion(
        string memory _title,
        string memory _meta,
        string memory _category,
        uint256 _resolveTime,
        uint256 _initialLiquidity,
        uint8 _fee
    ) external onlyOwner {
        require(_initialLiquidity > 0, "Invalid initial funding amount");
        require(_fee > 0 && _fee < 100, "Invalid trade fee rate");
        require(_resolveTime > block.timestamp, "Invalid resolve time");

        // Transfer collateral token
        collateral.transferFrom(msg.sender, address(this), _initialLiquidity);

        Question memory question;
        question.meta = _meta;
        question.resolveTime = _resolveTime;
        question.initialLiquidity = _initialLiquidity;
        question.fee = _fee;
        question.slot = 3;
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

        collateral.safeTransfer(msg.sender, fee);

        Market storage market = markets[_questionId];
        uint256 reward = market.volume.sub(question.initialLiquidity);
        if (_slot == 0) {
            market.reward = reward.mul(10**18).div(market.slot1);
        } else {
            market.reward = reward.mul(10**18).div(market.slot2);
        }

        emit QuestionResolved(_questionId, _slot);
    }

    // ------------------- PUBLIC -------------------
    function buy(
        uint256 _questionId,
        uint256 _amount,
        uint8 _slot
    ) external onlyQuestion(_questionId) onlyUnResolved(_questionId) {
        require(_slot < 2, "Invalid slot");
        require(_amount > 0, "Invalid Trade Amount");

        uint256 fee = getFee(_questionId, _amount);
        tradeFees[_questionId] = tradeFees[_questionId].add(fee);

        uint256 payAmount = _amount.sub(fee);
        collateral.safeTransferFrom(msg.sender, address(this), _amount);

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
    }

    function sell(
        uint256 _questionId,
        uint256 _amount,
        uint8 _slot
    ) external onlyQuestion(_questionId) onlyUnResolved(_questionId) {
        require(_slot < 2, "Invalid slot");
        require(_amount > 0, "Invalid Trade Amount");

        uint256[2] memory slotIds = getSlotIds(_questionId);
        require(
            balanceOf(msg.sender, slotIds[_slot]) >= _amount,
            "Insufficient Amount"
        );

        Market storage market = markets[_questionId];
        Question memory question = questions[_questionId];
        uint256[2] memory prices = getPrices(_questionId);
        uint256 collateralAmount = prices[_slot].mul(_amount);
        uint256 fee = getFee(_questionId, collateralAmount);
        require(
            collateralAmount <= market.volume.sub(question.initialLiquidity),
            "Insufficient liquidity"
        );

        _burn(msg.sender, slotIds[_slot], _amount);

        tradeFees[_questionId] = tradeFees[_questionId].add(fee);
        collateral.safeTransfer(msg.sender, collateralAmount.sub(fee));

        market.volume = market.volume.sub(collateralAmount);
        if (_slot == 0) {
            market.slot1 = market.slot1.sub(_amount);
        } else {
            market.slot2 = market.slot2.sub(_amount);
        }
    }

    function claim(uint256 _questionId)
        external
        onlyQuestion(_questionId)
        onlyResolved(_questionId)
    {
        Market memory market = markets[_questionId];
        require(market.reward > 0, "No claimable reward");

        uint256 slot = questions[_questionId].slot;
        uint256[2] memory slotIds = getSlotIds(_questionId);
        uint256 balance = balanceOf(msg.sender, slotIds[slot]);
        
        require(balance > 0, "No balance");
        _burn(msg.sender, slotIds[slot], balance);

        uint256 amount = balance.mul(market.reward).div(10**18);
        collateral.safeTransfer(msg.sender, amount);
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
        require(questions[id].slot == 3, "Already resolved question");
        _;
    }
}