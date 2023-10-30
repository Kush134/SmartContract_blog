require("dotenv").config();
const { ethers } = require("ethers");
const {
  MAIN_NFT_ADDRESS,
  MAIN_NFT_ABI,
  ERC20_ABI,
} = require("../constants/constants_v2");
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const BNBT_RPC_URL = process.env.BNBT_RPC_URL;