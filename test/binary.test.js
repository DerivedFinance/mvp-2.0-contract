const { ethers } = require("hardhat");
const { expect } = require("chai");
const { BigNumber } = require("ethers");

const MOCK_QUESTION_1 = [
  "Test question - 1",
  "",
  "crypto",
  parseInt(new Date().getTime() / 1000 + 1000, 10),
  ethers.utils.parseEther("1000").toString(),
  5,
];

describe("BinaryMarket", () => {
  let alice;
  let bob;
  let charlie;

  let binaryMarket;
  let derivedToken;

  let ownerAddr;
  let bobAddr;
  let charlieAddr;

  let question0;

  before(async () => {
    [alice, bob, charlie] = await ethers.getSigners();
    [ownerAddr, bobAddr, charlieAddr] = await Promise.all(
      [alice, bob, charlie].map((x) => x.getAddress())
    );

    console.log(
      "Total Supply: ",
      ethers.utils.parseEther("10000000000000").toString()
    );

    // Create testing DerivedToken to be used in asset pool
    const DerivedToken = await ethers.getContractFactory("DerivedToken");
    derivedToken = await DerivedToken.deploy(
      ethers.utils.parseEther("10000000000000").toString()
    );
    await derivedToken.deployed();

    // Create testing DerivedToken to be used in asset pool
    const BinaryMarket = await ethers.getContractFactory("BinaryMarket");
    binaryMarket = await BinaryMarket.deploy(derivedToken.address);
    await binaryMarket.deployed();

    await derivedToken.transfer(
      bobAddr,
      ethers.utils.parseEther("10000").toString()
    );
    await derivedToken.transfer(
      charlieAddr,
      ethers.utils.parseEther("20000").toString()
    );
  });

  it("Deployment", async () => {
    expect(await binaryMarket.owner()).to.be.equal(ownerAddr);
  });

  it("Should create question", async () => {
    const approve = await derivedToken.approve(
      binaryMarket.address,
      ethers.utils.parseEther("10000000000000").toString()
    );
    await approve.wait();

    const tx = await binaryMarket.createQuestion(...MOCK_QUESTION_1);
    await tx.wait();

    question0 = await binaryMarket.questions(0);

    expect(question0.resolveTime).to.equal(MOCK_QUESTION_1[3]);
    expect(question0.initialLiquidity).to.equal(MOCK_QUESTION_1[4]);
    expect(question0.fee).to.equal(MOCK_QUESTION_1[5]);
    expect(question0.slot).to.equal(2);
  });

  it("Should have correct prices", async () => {
    const prices = await binaryMarket.getPrices(0);
    expect(prices[0]).to.equal(ethers.utils.parseEther("0.5").toString());
    expect(prices[1]).to.equal(ethers.utils.parseEther("0.5").toString());
  });

  it("Should buy shares successfully", async () => {
    const approve = await derivedToken
      .connect(bob)
      .approve(
        binaryMarket.address,
        ethers.utils.parseEther("10000000000000").toString()
      );

    await approve.wait();

    const buy = await binaryMarket
      .connect(bob)
      .buy(0, ethers.utils.parseEther("50").toString(), 0);
    await buy.wait();

    const balances0 = parseFloat((50 * 0.95) / 0.5);
    expect(await binaryMarket.balanceOf(bobAddr, 0)).to.equal(
      ethers.utils.parseEther(`${balances0}`).toString()
    );

    const prices = await binaryMarket.getPrices(0);

    const prices0 = ethers.utils
      .parseEther(`${1000 + balances0}`)
      .mul(ethers.utils.parseEther("1"))
      .div(ethers.utils.parseEther(`${2000 + balances0}`))
      .toString();

    const prices1 = ethers.utils
      .parseEther(`1000`)
      .mul(ethers.utils.parseEther("1"))
      .div(ethers.utils.parseEther(`${2000 + balances0}`))
      .toString();

    expect(prices[0]).to.equal(prices0);
    expect(prices[1]).to.equal(prices1);
  });

  it("Should have correct market data", async () => {
    expect(await binaryMarket.getMarketVolume(0)).to.equal(
      ethers.utils
        .parseEther("1000")
        .add(ethers.utils.parseEther(`${parseFloat(50 * 0.95)}`))
        .toString()
    );

    expect(await binaryMarket.getShares(0)).to.equal(
      ethers.utils
        .parseEther("2000")
        .add(ethers.utils.parseEther(`${parseFloat((50 * 0.95) / 0.5)}`))
    );
  });

  it("Should have correct trade fee", async () => {
    expect(await binaryMarket.tradeFees(0)).to.equal(
      ethers.utils.parseEther(`${parseFloat(50 * 0.05)}`)
    );
  });

  it("Should get max sell shares amount", async () => {
    const sharesMaxSell = await binaryMarket.getSharesMaxSell(0, 0);
    const prices = await binaryMarket.getPrices(0);
    const volume = await binaryMarket.getTradeVolume(0);
    const expectedMaxShares = BigNumber.from(volume.toString())
      .mul(ethers.utils.parseEther("1"))
      .div(BigNumber.from(prices[0].toString()))
      .toString();

    expect(sharesMaxSell.toString()).to.equal(expectedMaxShares);
  });

  it("Should revert the insufficient liquidity volume sell", async () => {
    const balance = await binaryMarket.balanceOf(bobAddr, 0);
    // eslint-disable-next-line no-unused-expressions
    expect(binaryMarket.sell(0, balance.toString(), 0)).to.be.reverted;
  });

  it("Should get revenue by selling shares", async () => {
    const beforeTrade = await derivedToken.balanceOf(bobAddr);

    const sharesMaxSell = await binaryMarket.getSharesMaxSell(0, 0);
    const prices = await binaryMarket.getPrices(0);
    const tx = await binaryMarket
      .connect(bob)
      .sell(0, sharesMaxSell.toString(), 0);
    await tx.wait();

    const afterTrade = await derivedToken.balanceOf(bobAddr);
    const amount = BigNumber.from(sharesMaxSell.toString())
      .mul(BigNumber.from(prices[0]))
      .div(ethers.utils.parseEther("1"));
    const fee = amount.mul(MOCK_QUESTION_1[5]).div(100);
    const revenue = amount.sub(fee).toString();

    expect(await binaryMarket.getFee(0, amount.toString())).to.equal(
      fee.toString()
    );
    expect(afterTrade.toString()).to.equal(
      BigNumber.from(beforeTrade.toString()).add(BigNumber.from(revenue))
    );
  });

  it("Should claim reward", async () => {
    const approve = await derivedToken
      .connect(charlie)
      .approve(
        binaryMarket.address,
        ethers.utils.parseEther("10000000000000").toString()
      );

    await approve.wait();

    const buy = await binaryMarket
      .connect(charlie)
      .buy(0, ethers.utils.parseEther("50").toString(), 0);
    await buy.wait();

    const afterBalances = await derivedToken.balanceOf(charlieAddr);

    await ethers.provider.send("evm_increaseTime", [1000]);
    await ethers.provider.send("evm_mine");

    const resolve = await binaryMarket.resolveQuestion(0, 0);
    await resolve.wait();

    const reward = await binaryMarket.connect(charlie).getClaimableReward(0);

    const claim = await binaryMarket.connect(charlie).claim(0);
    await claim.wait();

    const afterClaimBalances = await derivedToken.balanceOf(charlieAddr);

    expect(reward.toString()).to.equal(
      BigNumber.from(afterClaimBalances.toString()).sub(
        BigNumber.from(afterBalances.toString())
      )
    );
  });
});
