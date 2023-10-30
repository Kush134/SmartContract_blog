const hre = require("hardhat");

async function main() {
  const [owner] = await ethers.getSigners();

  const Name = "PancakeswapV3Helper";
  const Contract = await hre.ethers.getContractFactory(Name);

  const _factoryAddr = "0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865";
  const _swapRouterAddr = "0x9a489505a00cE272eAa5e07Dba6491314CaE3796";
  const _poolFees = [100, 500, 2500, 10000];
  const result = await Contract.deploy(
    _factoryAddr,
    _swapRouterAddr,
    _poolFees
  );
  await result.deployed();

  console.log(`owner address: ${owner.address}`);
  console.log(`Deployed result address: ${result.address}`);

  const WAIT_BLOCK_CONFIRMATIONS = 6;
  await result.deployTransaction.wait(WAIT_BLOCK_CONFIRMATIONS);

  console.log(`Contract deployed to ${result.address} on ${network.name}`);

  console.log(`Verifying contract on Etherscan...`);

  await run(`verify:verify`, {
    address: result.address,
    constructorArguments: [_factoryAddr, _swapRouterAddr, _poolFees],
  });

  // await run(`verify:verify`, {
  //   address: "0x2b08ABfb5bD79c1f734B695AE9b29a7Ec0a6F264",
  //   constructorArguments: [_factoryAddr, _swapRouterAddr, _poolFees],
  // });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});