require("dotenv").config();
const hre = require("hardhat");

async function main() {
  const usdx = "0x66961eF8302967e995600B15d75aB8EE7Fd4FB7e";
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
