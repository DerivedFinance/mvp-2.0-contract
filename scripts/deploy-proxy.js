require("dotenv").config();
const { ethers, upgrades } = require("hardhat");

async function main() {
  // bsctest USDC
  const usdx = "0x8c9C613DA9adBe462F71E273C8284610E6F57247";

  const binaryMarketProxy = await upgrades.deployProxy(
    await ethers.getContractFactory("BinaryMarket"),
    [usdx],
    {
      initializer: "initialize",
    }
  );
  await binaryMarketProxy.deployed();

  console.log("Binary Market Proxy: ", binaryMarketProxy.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
