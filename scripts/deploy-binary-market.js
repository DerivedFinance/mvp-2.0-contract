require("dotenv").config();
const hre = require("hardhat");

async function main() {
  // const usdx = "0x64544969ed7EBf5f083679233325356EbE738930";

  // rinkeby
  // const usdx = "0x4a5F200B65DC4da50c7Ccf81b7bcF34c33BaF632";

  // bsctest
  const usdx = "0xfADF4D058bFD10A4aa14739d96e211693F5F295b";
  // Deploy SharkNFT contract
  const BinaryMarket = await hre.ethers.getContractFactory("BinaryMarket");
  const binaryMarket = await BinaryMarket.deploy(usdx);

  await binaryMarket.deployed();
  console.log(`BinaryMarket deployed: ${binaryMarket.address}`);

  // await hre.run("verify:verify", {
  //   address: binaryMarket.address,
  //   constructorArguments: [],
  // });
  console.log(
    `npx hardhat verify --contract contracts/BinaryMarket.sol:BinaryMarket ${binaryMarket.address} ${usdx} --network bsctest`
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
