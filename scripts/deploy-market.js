require("dotenv").config();
const hre = require("hardhat");

async function main() {
  // Deploy SharkNFT contract
  const DerivedPredictionMarket = await hre.ethers.getContractFactory(
    "DerivedPredictionMarket"
  );
  const derivedPredictionMarket = await DerivedPredictionMarket.deploy(
    "0xff8422C90C165e5a8492E2DB06b4240D22D5AA3F"
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
    `npx hardhat verify --contract contracts/DerivedPredictionMarket.sol:DerivedPredictionMarket ${derivedPredictionMarket.address} --network rinkeby`
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
