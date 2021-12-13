require("dotenv").config();
const hre = require("hardhat");

const initialSupply = process.env.INITIAL_SUPPLY || "1000000000000000000000000";

async function main() {
  // Deploy DerivedToken contract
  const DerivedToken = await hre.ethers.getContractFactory("DerivedToken");
  const derivedToken = await DerivedToken.deploy(initialSupply);

  await derivedToken.deployed();

  console.log(`DerivedToken deployed: ${derivedToken.address}`);
  // await hre.run("verify:verify", {
  //   address: derivedToken.address,
  //   constructorArguments: [initialSupply],
  // });
  console.log(
    `npx hardhat verify --contract contracts/DerivedToken.sol:DerivedToken ${derivedToken.address} ${initialSupply} --network rinkeby`
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
