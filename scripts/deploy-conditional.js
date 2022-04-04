require("dotenv").config();
const hre = require("hardhat");

async function main() {
  // Deploy SharkNFT contract
  const ConditionalTokens = await hre.ethers.getContractFactory(
    "ConditionalTokens"
  );
  const conditionalTokens = await ConditionalTokens.deploy();

  await conditionalTokens.deployed();
  console.log(
    `ConditionalTokens deployed: ${conditionalTokens.address}`
  );

  // await hre.run("verify:verify", {
  //   address: conditionalTokens.address,
  //   constructorArguments: [],
  // });
  console.log(
    `npx hardhat verify --contract contracts/ConditionalTokens.sol:ConditionalTokens ${conditionalTokens.address} --network bsctest`
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
