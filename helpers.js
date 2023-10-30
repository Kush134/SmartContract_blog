const axios = require("axios");
require("dotenv").config();
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;

exports.getABI = async (address) => {
  const url = `https://api.etherscan.io/api
    ?module=contract
    &action=getabi
    &address=${address}
    &apikey=${ETHERSCAN_API_KEY}`;

  const res = await axios.get(url);

  const abi = JSON.parse(res.data.result);

  return abi;
};
