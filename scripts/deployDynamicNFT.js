const hre = require("hardhat");

async function main() {
  const [owner] = await ethers.getSigners();

  const Name = "NoddeDynamicNFT";
  const Contract = await hre.ethers.getContractFactory(Name);

  const _mainNFTAddress = "0x66e8cf86Ae35A96e4B67021689B4fCf47C3267c5";
  const _baseImageURI = "ipfs://QmTQFyYyYiNQ82YpgMWDbEMqEa6U5ncBDVbQ4rBmXLrp67/";
  const result = await Contract.deploy(_mainNFTAddress, _baseImageURI);
  await result.deployed();

  console.log(`owner address: ${owner.address}`);
  console.log(`Deployed result address: ${result.address}`);

  const WAIT_BLOCK_CONFIRMATIONS = 5;
  await result.deployTransaction.wait(WAIT_BLOCK_CONFIRMATIONS);

  console.log(`Contract deployed to ${result.address} on ${network.name}`);

  console.log(`Verifying contract on Etherscan...`);

  await run(`verify:verify`, {
    address: result.address,
    constructorArguments: [_mainNFTAddress, _baseImageURI],
  });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
