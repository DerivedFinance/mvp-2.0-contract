require("dotenv").config();
const hre = require("hardhat");

async function main() {
  const usdx = "0x260f6a42C14Ce903948dB23819FCC1dF67Ba6026";
  // Deploy SharkNFT contract
  const DerivedPredictionMarket = await hre.ethers.getContractFactory(
    "DerivedPredictionMarket"
  );
  const derivedPredictionMarket = await DerivedPredictionMarket.deploy(usdx);

  await derivedPredictionMarket.deployed();
  console.log(
    `DerivedPredictionMarket deployed: ${derivedPredictionMarket.address}`
  );

  // await hre.run("verify:verify", {
  //   address: derivedPredictionMarket.address,
  //   constructorArguments: [],
  // });
  console.log(
    `npx hardhat verify --contract contracts/DerivedPredictionMarket.sol:DerivedPredictionMarket ${derivedPredictionMarket.address} ${usdx} --network bsctest`
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
