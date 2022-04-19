const { ethers } = require("hardhat");
const { expect } = require("chai");

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

  it("Should create question", async () => {
    const approve = await derivedToken.approve(
      binaryMarket.address,
      ethers.utils.parseEther("10000000000000").toString()
    );
    await approve.wait();

    const payload = [
      "Test question - 1",
      "",
      "crypto",
      parseInt(new Date().getTime() / 1000 + 1000, 10),
      ethers.utils.parseEther("1000").toString(),
      5,
    ];

    console.log("Payload: ", payload);

    const tx = await binaryMarket.createQuestion(...payload);
    await tx.wait();

    question0 = await binaryMarket.questions(0);

    expect(question0.resolveTime).to.equal(payload[3]);
    expect(question0.initialLiquidity).to.equal(payload[4]);
    expect(question0.fee).to.equal(payload[5]);
    expect(question0.slot).to.equal(3);
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
});
