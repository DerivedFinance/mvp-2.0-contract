require("dotenv").config();
const hre = require("hardhat");

async function main() {
  const lastMintEvent = parseInt(new Date("2021-12-25").getTime() / 1000, 10);
  const currentWeek = parseInt(Date.now() / 1000, 10);
  const initialSupply =
    process.env.INITIAL_SUPPLY || "1000000000000000000000000";

  // Deploy SafeMath
  const SafeMathLib = await hre.ethers.getContractFactory("SafeMath");
  const safeMathLib = await SafeMathLib.deploy();
  await safeMathLib.deployed();

  // Deploy SafeDecimalMath
  const SafeDecimalMathLib = await hre.ethers.getContractFactory(
    "SafeDecimalMath"
  );
  const safeDecimalMathLib = await SafeDecimalMathLib.deploy();
  await safeDecimalMathLib.deployed();

  // Deploy Math
  const MathLib = await hre.ethers.getContractFactory("Math");
  const mathLib = await MathLib.deploy();
  await mathLib.deployed();

  // Deploy DerivedToken contract
  const DerivedToken = await hre.ethers.getContractFactory("DerivedToken");
  const derivedToken = await DerivedToken.deploy(initialSupply);
  await derivedToken.deployed();

  console.log(`DerivedToken deployed: ${derivedToken.address}`);

  // Deploy SharkNFT contract
  const SupplySchedule = await hre.ethers.getContractFactory("SupplySchedule", {
    libraries: {
      // Math: mathLib.address,
      // SafeMath: safeMathLib.address,
      SafeDecimalMath: safeDecimalMathLib.address,
    },
  });
  const supplySchedule = await SupplySchedule.deploy(
    lastMintEvent,
    currentWeek,
    derivedToken.address
  );
  await supplySchedule.deployed();

  console.log(`SupplySchedule deployed: ${supplySchedule.address}`);

  // Contract verification
  // await hre.run("verify:verify", {
  //   address: derivedToken.address,
  //   constructorArguments: [initialSupply],
  // });

  // await hre.run("verify:verify", {
  //   address: supplySchedule.address,
  //   constructorArguments: [lastMintEvent, currentWeek, derivedToken.address],
  // });

  // console.log(
  //   `npx hardhat verify --contract contracts/SupplySchedule.sol:SupplySchedule ${supplySchedule.address} --network rinkeby`
  // );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
