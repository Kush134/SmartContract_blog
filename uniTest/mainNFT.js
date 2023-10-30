require("dotenv").config();
const { ethers } = require("ethers");
const {
  MAIN_NFT_ADDRESS,
  MAIN_NFT_ABI,
  ERC20_ABI,
} = require("../constants/constants_v2");
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const BNBT_RPC_URL = process.env.BNBT_RPC_URL;

const provider = new ethers.providers.JsonRpcProvider(BNBT_RPC_URL);
const signer = new ethers.Wallet(PRIVATE_KEY, provider);
const addressSigner = signer.address;
console.log(`Address signer: ${addressSigner}`);

const contract = new ethers.Contract(MAIN_NFT_ADDRESS, MAIN_NFT_ABI, signer);
const WAIT_BLOCK_CONFIRMATIONS = 2;

// Mint token función. Se verifica automáticamente la cantidad mínima requerida para la menta
async function safeMint(address) {
  const price = await contract.priceToMint(address);
  const tx = await contract.safeMint({ value: price });
  console.log(`safeMint hash: ${tx.hash}`);
  await signer.provider.waitForTransaction(tx.hash, WAIT_BLOCK_CONFIRMATIONS);
}

// Obtener la lista de direcciones de tokens para la donación por el autor
async function donateTokenAddressesByAuthor(author) {
  let addresses = [];
  let counter = 0;
  while (counter < 999) {
    try {
      const addr = await contract.donateTokenAddressesByAuthor(
        author,
        counter++
      );
      addresses.push(addr);
    } catch (err) {
      // console.log(`Error al obtener una dirección con un índice ${counter - 1}: ${err}`);
      break;
    }
  }
  return addresses;
}

async function main() {
  let usersToken = await getUsersTokens(addressSigner);
  console.log(
    `User token balance: ${usersToken.balance}, tokens: ${usersToken.tokens}`
  );
  if (usersToken.balance == 0) {
    await safeMint(addressSigner);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
