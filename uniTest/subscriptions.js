require("dotenv").config();
const { ethers, BigNumber } = require("ethers");
const {
  MAIN_NFT_ADDRESS,
  MAIN_NFT_ABI,
  SUBSCRIPTIONS_ADDRESS,
  SUBSCRIPTIONS_ABI,
  ERC20_ABI,
} = require("../constants/constants_v2");
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const BNBT_RPC_URL = process.env.BNBT_RPC_URL;

const zeroAddr = "0x0000000000000000000000000000000000000000";
const provider = new ethers.providers.JsonRpcProvider(BNBT_RPC_URL);
const signer = new ethers.Wallet(PRIVATE_KEY, provider);
const addressSigner = signer.address;
console.log(`Address signer: ${addressSigner}`);

const mainContract = new ethers.Contract(
  MAIN_NFT_ADDRESS,
  MAIN_NFT_ABI,
  signer
);

const subscriptionsContract = new ethers.Contract(
  SUBSCRIPTIONS_ADDRESS,
  SUBSCRIPTIONS_ABI,
  signer
);
const WAIT_BLOCK_CONFIRMATIONS = 2;

// Create new Subscription
async function createNewSubscriptionByEth(
  hexName,
  author,
  isRegularSubscription,
  paymetnPeriod,
  price,
  discountProgramm
) {
  const tx = await subscriptionsContract.createNewSubscriptionByEth(
    hexName,
    author,
    isRegularSubscription,
    paymetnPeriod,
    price,
    discountProgramm
  );
  console.log(`createNewSubscriptionByEth hash: ${tx.hash}`);
  await signer.provider.waitForTransaction(tx.hash, WAIT_BLOCK_CONFIRMATIONS);
}

// Create new Subscription by token
async function createNewSubscriptionByToken(
  hexName,
  author,
  isRegularSubscription,
  paymetnPeriod,
  tokenAddresses,
  price,
  discountProgramm
) {
  const tx = await subscriptionsContract.createNewSubscriptionByToken(
    hexName,
    author,
    isRegularSubscription,
    paymetnPeriod,
    tokenAddresses,
    price,
    discountProgramm
  );
  console.log(`createNewSubscriptionByToken hash: ${tx.hash}`);
  await signer.provider.waitForTransaction(tx.hash, WAIT_BLOCK_CONFIRMATIONS);
}

// Get total payment amount for period
async function getTotalPaymentAmountForPeriod(author, subscriptionId, periods) {
  const amounts = await subscriptionsContract.getTotalPaymentAmountForPeriod(
    author,
    subscriptionId,
    periods
  );
  return {
    amount: amounts[0],
    amountInEth: amounts[1],
  };
}

// Getting user tokens, returns the number of tokens and their id
async function subscriptionPayment(
  author,
  subscriptionId,
  tokenAddress,
  periods
) {
  const amounts = await getTotalPaymentAmountForPeriod(
    author,
    subscriptionId,
    periods
  );
  const amount = amounts.amount;
  if (tokenAddress.toLowerCase() === zeroAddr) {
    const tx = await subscriptionsContract.subscriptionPayment(
      author,
      subscriptionId,
      tokenAddress,
      periods,
      { value: amount }
    );
    console.log(`subscriptionPayment hash: ${tx.hash}`);
    await signer.provider.waitForTransaction(tx.hash, WAIT_BLOCK_CONFIRMATIONS);
  } else {
    const contractERC20 = new ethers.Contract(tokenAddress, ERC20_ABI, signer);
    const allowance = await contractERC20.allowance(
      addressSigner,
      SUBSCRIPTIONS_ADDRESS
    );

    const balance = await contractERC20.balanceOf(addressSigner);
    if (balance.lt(amount)) {
      console.log(`Balance to low for subscriptions`);
      return;
    }

    if (allowance.lt(amount)) {
      const approveTx = await contractERC20.approve(
        SUBSCRIPTIONS_ADDRESS,
        balance
      );
      console.log(`approve hash: ${approveTx.hash}`);
      await signer.provider.waitForTransaction(
        approveTx.hash,
        WAIT_BLOCK_CONFIRMATIONS
      );
    }

    const tx = await subscriptionsContract.subscriptionPayment(
      author,
      subscriptionId,
      tokenAddress,
      periods,
      { value: 0 }
    );
    console.log(`subscriptionPayment hash: ${tx.hash}`);
    await signer.provider.waitForTransaction(tx.hash, WAIT_BLOCK_CONFIRMATIONS);
  }
}

function generateNewHash(someString) {
  const hash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(someString));
  console.log(`generateNewHash: ${hash}`);
  return hash;
}

async function _getBlockTimestamp(blockNumber) {
  const block = await provider.getBlock(blockNumber);
  return await _getTimestamp(block.timestamp * 1000);
}

async function _getTimestamp(timestamp) {
  const date = new Date(timestamp);
  const year = date.getFullYear();
  const month = ("0" + (date.getMonth() + 1)).slice(-2);
  const day = ("0" + date.getDate()).slice(-2);
  const hours = ("0" + date.getHours()).slice(-2);
  const minutes = ("0" + date.getMinutes()).slice(-2);
  const formattedDate =
    year + "-" + month + "-" + day + " " + hours + ":" + minutes;
  return formattedDate;
}

async function callbackEvents() {
  const blockNumber = await provider.getBlockNumber();

  // Getting last 10 events NewSubscription from last 100000 blocks
  subscriptionsContract
    .queryFilter("NewSubscription", blockNumber - 100000, blockNumber)
    .then((events) => {
      console.log(`Found ${events.length} NewSubscription events:`);
      events.slice(-10).forEach(async (event) => {
        const blockNumber = event.blockNumber;
        const blockTimestamp = await _getBlockTimestamp(blockNumber);
        const hexId = event.args.hexId;
        const participant = event.args.participant;
        const author = event.args.author;
        const subscriptionIndex = event.args.subscriptionIndex;
        const subscriptionEndTime = event.args.subscriptionEndTime;
        const tokenAddress = event.args.tokenAddress;
        const amount = event.args.amount;

        console.log(
          `${blockTimestamp}, blockNumber: ${blockNumber}, hexId: ${hexId}, participant: ${participant}, author: ${author}, subscriptionEndTime: ${subscriptionEndTime}`
        );
      });
    });

  // Getting last 10 events NewOneTimeSubscriptionCreated from last 50000 blocks
  subscriptionsContract
    .queryFilter(
      "NewOneTimeSubscriptionCreated",
      blockNumber - 50000,
      blockNumber
    )
    .then((events) => {
      console.log(
        `Found ${events.length} NewOneTimeSubscriptionCreated events:`
      );
      events.slice(-10).forEach(async (event) => {
        const blockNumber = event.blockNumber;
        const blockTimestamp = await _getBlockTimestamp(blockNumber);
        const author = event.args.author;
        const hexId = event.args.hexId;
        const tokenAddress = event.args.tokenAddress;
        const discounts = event.args.discounts;

        console.log(
          `${blockTimestamp}, blockNumber: ${blockNumber}, author: ${author}, hexId: ${hexId}, tokenAddress: ${tokenAddress}`
        );
      });
    });

  // Getting last 10 events NewRegularSubscriptionCreated from last 50000 blocks
  subscriptionsContract
    .queryFilter(
      "NewRegularSubscriptionCreated",
      blockNumber - 50000,
      blockNumber
    )
    .then((events) => {
      console.log(
        `Found ${events.length} NewRegularSubscriptionCreated events:`
      );
      events.slice(-10).forEach(async (event) => {
        const blockNumber = event.blockNumber;
        const blockTimestamp = await _getBlockTimestamp(blockNumber);
        const author = event.args.author;
        const hexId = event.args.hexId;
        const tokenAddress = event.args.tokenAddress;
        const paymetnPeriod = event.args.paymetnPeriod;
        const discounts = event.args.discounts;

        console.log(
          `${blockTimestamp}, blockNumber: ${blockNumber}, author: ${author}, hexId: ${hexId}, tokenAddress: ${tokenAddress}, paymetnPeriod: ${paymetnPeriod}`
        );
      });
    });
}

async function main() {
  //   const timestamp = Date.now();
  //   const index = generateNewHash(timestamp.toString());
  const id = 1234;
  const hexId = ethers.utils.hexZeroPad(ethers.utils.hexlify(id), 32);
  const idValue = ethers.BigNumber.from(hexId).toNumber();

  const author = 1;
  const isRegularSubscription = false;
  const paymetnPeriod = 14400;
  const tokenAddresses = ["0x5eAD2D2FA49925dbcd6dE99A573cDA494E3689be"];
  const price = BigNumber.from(10 ** 15);
  const discountProgramm = [
    {
      period: 2,
      amountAsPPM: 200,
    },
    {
      period: 5,
      amountAsPPM: 500,
    },
  ];

  /**
  await createNewSubscriptionByEth(
    hexId,
    author,
    isRegularSubscription,
    paymetnPeriod,
    price,
    discountProgramm
  );
  */

  /**
  await createNewSubscriptionByToken(
    hexId,
    author,
    isRegularSubscription,
    paymetnPeriod,
    tokenAddresses,
    price,
    discountProgramm
  );
   */

  /**
  const subscriptionId = 0;
  await subscriptionPayment(author, subscriptionId, zeroAddr, 5);
  */

  /**
  const subscriptionId = 1;
  await subscriptionPayment(author, subscriptionId, tokenAddresses[0], 2);
  */

  await callbackEvents();
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
