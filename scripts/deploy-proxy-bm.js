require("dotenv").config();
const hre = require("hardhat");

async function main() {
  // const usdx = "0x64544969ed7EBf5f083679233325356EbE738930";

  // rinkeby
  // const usdx = "0x4a5F200B65DC4da50c7Ccf81b7bcF34c33BaF632";

  // bsctest USDC
  const usdc = "0x8c9C613DA9adBe462F71E273C8284610E6F57247";

  // Deploy Proxy contract
  const ProxyContract = await hre.ethers.getContractFactory("Proxy");
  const proxyContract = await ProxyContract.deploy();

  await proxyContract.deployed();
  console.log(`Proxy Contract deployed: ${proxyContract.address}`);

  // Deploy Binary Market contract
  const BinaryMarket = await hre.ethers.getContractFactory("BinaryMarket");
  const binaryMarket = await BinaryMarket.deploy();

  await binaryMarket.deployed();
  console.log(`BinaryMarket deployed: ${binaryMarket.address}`);

  // Set implementation contract for Proxy
  const setImplementationTx = await proxyContract.setImplementation(binaryMarket.address);
  await setImplementationTx.wait();
  console.log("Implementation contract is set.");

  // Initialize binary market
  const [owner] = await ethers.getSigners();
  const abi = ["function initialize(address payable _token, address _owner, address payable _proxy) public"];
  const proxied = new ethers.Contract(proxyContract.address, abi, owner);

  const initializeTx = await proxied.initialize(usdc, owner.address, proxyContract.address);
  await initializeTx.wait();
  console.log("Initialization for Implementation executed.")

  // await hre.run("verify:verify", {
  //   address: binaryMarket.address,
  //   constructorArguments: [],
  // });
  console.log(
    `npx hardhat verify ${binaryMarket.address} --network bsctest && npx hardhat verify ${proxyContract.address} --network bsctest`
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
