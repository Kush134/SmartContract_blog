require("dotenv").config();
const { ethers } = require("ethers");
const {
  MAIN_NFT_ADDRESS,
  MAIN_NFT_ABI,
  PUBLIC_DONATION_ADDRESS,
  PUBLIC_DONATION_ABI,
  ERC20_ABI,
} = require("../constants/constants_v2");
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const BNBT_RPC_URL = process.env.BNBT_RPC_URL;

const BUSD_ADDRESS = "0xaB1a4d4f1D656d2450692D237fdD6C7f9146e814";
const USDT_ADDRESS = "0x5eAD2D2FA49925dbcd6dE99A573cDA494E3689be";
const USDC_ADDRESS = "0x953b8279d8Eb26c42d33bA1Aca130d853cb941C8";

const provider = new ethers.providers.JsonRpcProvider(BNBT_RPC_URL);
const signer = new ethers.Wallet(PRIVATE_KEY, provider);
const addressSigner = signer.address;
console.log(`Address signer: ${addressSigner}`);

const publicDonationContract = new ethers.Contract(
  PUBLIC_DONATION_ADDRESS,
  PUBLIC_DONATION_ABI,
  signer
);
const WAIT_BLOCK_CONFIRMATIONS = 2;

// Donat en Tokens. !!!ATENCIÓN, la función toma un valor múltiplo de 10**18, es decir, la unidad Ether
async function donateTokenByEther(tokenAddress, tokenAmountFromEther, author) {
  const value = ethers.utils.parseEther(tokenAmountFromEther.toString());
  const contractERC20 = new ethers.Contract(tokenAddress, ERC20_ABI, signer);
  const allowance = await contractERC20.allowance(
    addressSigner,
    PUBLIC_DONATION_ADDRESS
  );
  const balance = await contractERC20.balanceOf(addressSigner);
  if (balance < value) {
    return {
      message: "Balance to low for donate",
    };
  }
  if (allowance < value) {
    const approveTx = await contractERC20.approve(
      PUBLIC_DONATION_ADDRESS,
      balance
    );
    console.log(`approve hash: ${approveTx.hash}`);
    await signer.provider.waitForTransaction(
      approveTx.hash,
      WAIT_BLOCK_CONFIRMATIONS
    );
  }
  const tx = await publicDonationContract.donateFromSwap(
    tokenAddress,
    value,
    author
  );
  console.log(`donateToken hash: ${tx.hash}`);
  return {
    message: "Donation requested",
  };
}

// Donat en la Moneda de la cadena de bloques. !!!ATENCIÓN, la función toma un valor múltiplo de 10**18, es decir, la unidad Ether
async function donateEthByEther(author, valueFromEther) {
  const value = ethers.utils.parseEther(valueFromEther.toString());
  const tx = await publicDonationContract.donateEth(author, { value: value });
  console.log(`donate hash: ${tx.hash}`);
}

async function main() {
  const authorId = 0;

  // Unidad de medida múltiplo de 10 a la potencia de 18
  const amountInEther = 0.02809;

  //const donationResult = await donateEthByEther(authorId, amountInEther);

  const donationResult = await donateTokenByEther(USDC_ADDRESS, amountInEther, authorId);
  console.log(`Donation result: ${donationResult.message}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
