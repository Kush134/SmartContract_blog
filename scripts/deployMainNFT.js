const hre = require("hardhat");

async function main() {
  const [owner] = await ethers.getSigners();

  const Name = "MainNFT";
  const Contract = await hre.ethers.getContractFactory(Name);

  const _uniswapHelperAddress = "0x2b08abfb5bd79c1f734b695ae9b29a7ec0a6f264";
  const _priceFeedAddress = "0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526";
  const _levelsCount = 5;
  const _baseURI = "ipfs://QmSPdJyCiJCbJ2sWnomh6gHqkT2w1FSnp7ZnXxk3itvc14/";
  const result = await Contract.deploy(
    _uniswapHelperAddress,
    _priceFeedAddress,
    _levelsCount,
    _baseURI
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
    constructorArguments: [
      _uniswapHelperAddress,
      _priceFeedAddress,
      _levelsCount,
      _baseURI,
    ],
  });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
