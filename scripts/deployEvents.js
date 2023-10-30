const hre = require("hardhat");

async function main() {
  const [owner] = await ethers.getSigners();

  const Name = "Events";
  const Contract = await hre.ethers.getContractFactory(Name);

  const param1 = "0xA3b157a0c84c00AA6260F3cd06cE8746541aA8aB";
  const result = await Contract.deploy(param1);
  await result.deployed();

  console.log(`owner address: ${owner.address}`);
  console.log(`Deployed result address: ${result.address}`);

  const WAIT_BLOCK_CONFIRMATIONS = 6;
  await result.deployTransaction.wait(WAIT_BLOCK_CONFIRMATIONS);

  console.log(`Contract deployed to ${result.address} on ${network.name}`);

  console.log(`Verifying contract on Etherscan...`);

  await run(`verify:verify`, {
    address: result.address,
    constructorArguments: [param1],
  });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
