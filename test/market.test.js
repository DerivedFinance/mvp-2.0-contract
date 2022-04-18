const { ethers } = require("hardhat");

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

    console.log(
      "DEBUG-Total-Supply: ",
      ethers.utils.parseEther("10000000000000").toString()
    );

    // Create testing DerivedToken to be used in asset pool
    const DerivedToken = await ethers.getContractFactory("DerivedToken");
    derivedToken = await DerivedToken.deploy(
      ethers.utils.parseEther("10000000000000").toString()
    );
    await derivedToken.deployed();

    // Create testing DerivedToken to be used in asset pool
    const DerivedPredictionMarket = await ethers.getContractFactory(
      "DerivedPredictionMarket"
    );
    derviedPredictionMarket = await DerivedPredictionMarket.deploy(
      derivedToken.address
    );
    await derviedPredictionMarket.deployed();

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
    await derivedToken.approve(
      derviedPredictionMarket.address,
      ethers.utils.parseEther("10000000000000").toString()
    );

    const payload = {
      ownerAddr,
      title: "Test question - 1",
      meta: "",
      category: "crypto",
      resolveTime: parseInt(new Date().getTime() / 1000 + 1000, 10),
      funds: ethers.utils.parseEther("1000").toString(),
      fee: 5,
    };
    console.log("DEBUG-payload", { payload });

    const tx = await derviedPredictionMarket.createQuestion(
      ownerAddr,
      "Test question - 1",
      "",
      "crypto",
      parseInt(new Date().getTime() / 1000 + 1000, 10),
      ethers.utils.parseEther("1000").toString(),
      5
    );
    const resp = await tx.wait();
    console.log("DEBUG-tx", tx);
    console.log("DEBUG-resp", resp);
  });
});
