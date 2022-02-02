require("dotenv").config();
const hre = require("hardhat");

async function main() {
  // Deploy SharkNFT contract
  const DerivedPredictionMarket = await hre.ethers.getContractFactory(
    "DerivedPredictionMarket"
  );
  const derivedPredictionMarket = await DerivedPredictionMarket.deploy(
    "0xe92C13C39c9c2F1589C1d9dedAad06057BF3C593"
  );

  await derivedPredictionMarket.deployed();
  console.log(
    `DerivedPredictionMarket deployed: ${derivedPredictionMarket.address}`
  );

  // await hre.run("verify:verify", {
  //   address: derivedPredictionMarket.address,
  //   constructorArguments: [],
  // });
  console.log(
    `npx hardhat verify --contract contracts/DerivedPredictionMarket.sol:DerivedPredictionMarket ${derivedPredictionMarket.address} 0xe92C13C39c9c2F1589C1d9dedAad06057BF3C593 --network bsctest`
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
