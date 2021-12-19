const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("DerivedPredictionMarket", () => {
  let alice;
  let bob;
  let charlie;
  let derviedPredictionMarket;
  let derivedToken;

  let ownerAddr;
  let bobAddr;
  let charlieAddr;

  before(async () => {
    [alice, bob, charlie] = await ethers.getSigners();
    [ownerAddr, bobAddr, charlieAddr] = await Promise.all(
      [alice, bob, charlie].map((x) => x.getAddress())
    );

    // Create testing DerivedToken to be used in asset pool
    const DerivedToken = await ethers.getContractFactory("DerivedToken");
    derivedToken = await DerivedToken.deploy(1000);
    await derivedToken.deployed();

    // Create testing DerivedToken to be used in asset pool
    const DerivedPredictionMarket = await ethers.getContractFactory(
      "DerivedPredictionMarket"
    );
    derviedPredictionMarket = await DerivedPredictionMarket.deploy();
    await derviedPredictionMarket.deployed();

    await derivedToken.transfer(bobAddr, 100);
    await derivedToken.transfer(charlieAddr, 100);
  });

  it("Should create question", async () => {
    await derivedToken.approve(derviedPredictionMarket.address, 100);
    const tx = await derviedPredictionMarket.createQuestion(
      derivedToken.address,
      ownerAddr,
      "BTC will dump to 40k again",
      100,
      0
    );
    const resp = await tx.wait();

    console.log("DEBUG-tx", tx);
    console.log("DEBUG-resp", resp);
  });
});
