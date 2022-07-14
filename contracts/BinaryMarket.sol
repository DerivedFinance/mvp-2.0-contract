// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./BinaryMarketData.sol";
import "./Owned.sol";
import "./Proxy.sol";

contract BinaryMarket is
    BinaryMarketData,
    Initializable,
    OwnableUpgradeable,
    ERC1155Upgradeable,
    ERC1155BurnableUpgradeable,
    ERC1155HolderUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using CountersUpgradeable for CountersUpgradeable.Counter;
    bool public initialized;

    CountersUpgradeable.Counter private _questionIds;

    function initialize(address payable _token) external initializer {
        __Ownable_init();
        __ERC1155Holder_init();
        __ReentrancyGuard_init();

        token = IERC20Upgradeable(_token);
        setApprovalForAll(address(this), true);
    }

    /**
     * @dev See {IERC1155-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155Upgradeable, ERC1155ReceiverUpgradeable)
        returns (bool)
    {
        return
            interfaceId == type(IERC1155ReceiverUpgradeable).interfaceId ||
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
        market.liquidity = _initialLiquidity;

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
        uint256 tradeVolume = getLiquidityVolume(_questionId);
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
        Question storage question = questions[_questionId];
        require(!question.isPaused, "Already paused");

        uint256 amount = tradeFees[_questionId].add(
            getRewardVolume(_questionId)
        );
        require(amount > 0, "Not available funds");

        token.safeTransfer(msg.sender, amount);

        tradeFees[_questionId] = 0;
        question.isPaused = true;

        emit TradePaused(_questionId);
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

        require(!getQuestionStatus(_questionId), "Trade is not available");
        require(
            questions[_questionId].resolveTime >= block.timestamp,
            "Option already expired"
        );

        uint256 fee = getFee(_questionId, _amount);
        tradeFees[_questionId] = tradeFees[_questionId].add(fee);

        uint256 payAmount = _amount.sub(fee);
        token.safeTransferFrom(msg.sender, address(this), _amount);

        //uint256[2] memory prices = getPrices(_questionId);
        uint256[2] memory slotIds = getSlotIds(_questionId);
        uint256 sharesAmount;
        
        /*==== BV changes as per CPMM =====*/

        Market storage market = markets[_questionId];

        if (_slot == 0) { // Buy Yes or slot1
                
                uint256 sharesNo = market.slot2.add(payAmount);
                uint256 slotAmount = (market.slot1 * market.slot2)/(sharesNo);
                market.slot2 = sharesNo;
                sharesAmount = market.slot1.add(payAmount).sub(slotAmount);
                market.slot1 = slotAmount;

        } else { // Buy No or slot2

                uint256 sharesYes = market.slot1.add(payAmount);
                uint256 slotAmount = (market.slot1 * market.slot2)/(sharesYes);
                market.slot1 = sharesYes;
                sharesAmount = market.slot2.add(payAmount).sub(slotAmount);
                market.slot2 = slotAmount;
           
        }

        _mint(msg.sender, slotIds[_slot], sharesAmount, "");
        
        //Market storage market = markets[_questionId];
        market.volume = market.volume.add(payAmount);
        market.liquidity = market.liquidity.add(payAmount);
       /* 
       if (_slot == 0) {
            market.slot1 = market.slot1.add(sharesAmount);
        } else {
            market.slot2 = market.slot2.add(sharesAmount);
        }*/

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

        require(!getQuestionStatus(_questionId), "Trade is not available");
        require(
            questions[_questionId].resolveTime >= block.timestamp,
            "Option already expired"
        );

        uint256[2] memory slotIds = getSlotIds(_questionId);
        require(
            balanceOf(msg.sender, slotIds[_slot]) >= _amount,
            "Insufficient Amount"
        );
       /* require(
            _amount <= getSharesMaxSell(_questionId, _slot),
            "Insufficient liquidity"
        );*/

        Market storage market = markets[_questionId];
        
        
        if (_slot == 0) { //Sell Y or slot 1
                uint256 _newSlot1 = market.slot1.add(_amount);
                market.slot2 = _newSlot1.div(market.slot1);
                market.slot1 = _newSlot1;
            
        } else { // Sell No or slot 2
                uint256 _newSlot2 = market.slot2.add(_amount);
                market.slot1 = _newSlot2.div(market.slot2);
                market.slot2 = _newSlot2;

        }

        uint256[2] memory prices = getPrices(_questionId);
        uint256 tokenAmount = prices[_slot].mul(_amount).div(10**18);
        uint256 fee = getFee(_questionId, tokenAmount);
        payAmount = tokenAmount.sub(fee);

        _burn(msg.sender, slotIds[_slot], _amount);

        market.volume = market.volume.add(tokenAmount);
        market.liquidity = market.liquidity.sub(tokenAmount);
        tradeFees[_questionId] = tradeFees[_questionId].add(fee);

        token.safeTransfer(msg.sender, payAmount);

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

        Market storage market = markets[_questionId];
        market.liquidity = market.liquidity.sub(amount);

        _burn(msg.sender, slotIds[slot], balance);
        token.safeTransfer(msg.sender, amount);
    }

    // ------------------- GETTERS -------------------

    function getTotalQuestions() public view returns (uint256) {
        return _questionIds.current();
    }

    // returns total number of shares for a particular option
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
            market.slot2.mul(10**18).div(shares),
            market.slot1.mul(10**18).div(shares)
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

    function getTradeVolume(uint256 _questionId) public view returns (uint256) {
        return
            markets[_questionId].volume.sub(
                questions[_questionId].initialLiquidity
            );
    }

    function getLiquidityVolume(uint256 _questionId)
        public
        view
        returns (uint256)
    {
        return markets[_questionId].liquidity;
    }

    function getRewardVolume(uint256 _questionId)
        public
        view
        returns (uint256)
    {
        return
            getLiquidityVolume(_questionId).sub(
                questions[_questionId].initialLiquidity
            );
    }

    function getSharesMaxSell(uint256 _questionId, uint8 _slot)
        public
        view
        returns (uint256)
    {
        uint256[2] memory prices = getPrices(_questionId);
        uint256 volume = getRewardVolume(_questionId);
        return volume.mul(10**18).div(prices[_slot]);
    }

    function getQuestionsLength() public view returns (uint256) {
        return questions.length;
    }

    function getQuestionStatus(uint256 _questionId) public view returns (bool) {
        return questions[_questionId].isPaused;
    }

    // ------------------- MODIFIERS -------------------

    modifier onlyQuestion(uint256 id) {
        require(id < getTotalQuestions(), "Invalid Question");
        _;
    }

    modifier onlyResolved(uint256 id) {
        require(questions[id].slot < 2, "Not resolved question");
        _;
    }

    modifier onlyUnResolved(uint256 id) {
        require(questions[id].slot == 2, "Already resolved question");
        _;
    }
}
