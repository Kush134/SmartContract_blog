# smart-contracts

Our web3 application provides an opportunity for bloggers and influencers to monetize their channel on social networks through the creation of closed sessions for training, streams, and other events, as well as to receive donations from subscribers.

All payments are made through smart contracts, which guarantees security and transparency. Each channel is an NFT, which ensures ownership and earnings. To motivate the development of the channel, we have added a step-by-step reduction of the commission for our services depending on the profitability of the channel.

Our service allows authors to earn on donations and sessions, payment of which can be made in the base coin of the blockchain or in tokens specified by the author. Authors can create sessions by setting a price, a token for payment, the end time of registration, the maximum number of participants and the type of session.

Whitelists allow authors to automatically buy participation in a session without moderation, and blacklists allow you to block access to a session for certain users. All sessions have a structure with addresses of participants that can be confirmed, not confirmed or rejected by the author. In the case of a moderated session, funds are blocked on the contract until the author makes a decision on each participant.

Users can cancel the entry and refund the funds if their application has not yet been accepted by the author.

After the session ends, participants can leave likes or dislikes, and the rating of each session is stored in the blockchain and is not subject to censorship or falsification.

Each donation and session record generates an event in the blockchain, which allows embedding these events into various services.

##

## Install

```shell
npm init
npm install --save-dev "hardhat@^2.13.0" "@nomicfoundation/hardhat-toolbox@^2.0.0" @openzeppelin/contracts @uniswap/v2-periphery
npm install --save-dev solidity-coverage hardhat-gas-reporter hardhat-contract-sizer
npm install dotenv --save

npx hardhat
npx hardhat test

npx hardhat run scripts/deploy.js --network bnb_testnet

npx hardhat clean

npx hardhat compile
```

### For contracts

```
npm install @openzeppelin/contracts@4.5.0
```

### For helpers

```
npm install @openzeppelin/contracts@3.4.0
```

## Contracts (edited)

owner address: 0xc0DE5BCbE4dd5A6E1F7C827B898330d69CcEF216

MainNFT.sol: 0xA3b157a0c84c00AA6260F3cd06cE8746541aA8aB

https://testnet.bscscan.com/address/0xA3b157a0c84c00AA6260F3cd06cE8746541aA8aB#code

PublicDonation.sol: 0xB56311eA8b47454F2F3b58D6b3faeB84eE8FFB00

https://testnet.bscscan.com/address/0xB56311eA8b47454F2F3b58D6b3faeB84eE8FFB00#code

Subscriptions.sol: 0xe56e5FD2D7aeAde39B04EFb41992a233948D304e

https://testnet.bscscan.com/address/0xe56e5FD2D7aeAde39B04EFb41992a233948D304e#code

Eventf.sol: 0xe0f49A0ef3371B46F72ffd996E992F256ABA5b8C

https://testnet.bscscan.com/address/0xe0f49A0ef3371B46F72ffd996E992F256ABA5b8C#code

## Other information

uniswap v3 on BSC mainnet: 0x5Dc88340E1c5c6366864Ee415d6034cadd1A9897

levelsCount: 5

baseURI: ipfs://QmSPdJyCiJCbJ2sWnomh6gHqkT2w1FSnp7ZnXxk3itvc14/

Tether USD (USDT) on BSC testnet: 0x5eAD2D2FA49925dbcd6dE99A573cDA494E3689be

USD Coin (USDC) on BSC testnet: 0x953b8279d8Eb26c42d33bA1Aca130d853cb941C8

BUSD on BSC testnet: 0xaB1a4d4f1D656d2450692D237fdD6C7f9146e814

##

PancakeV3Factory 0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865

PancakeSmartRouter: 0x9a489505a00cE272eAa5e07Dba6491314CaE3796

WET9: 0xae13d989dac2f0debff460ac112a837c89baa7cd

Liquidity of Pancake: [100,500,2500,10000]

##

AggregatorV3 ChainLink (\_priceFeedAddress) 0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526

# New contracts on BSC TestNet:

### PancakeswapV3Helper:

0x2b08abfb5bd79c1f734b695ae9b29a7ec0a6f264

https://testnet.bscscan.com/address/0x2b08abfb5bd79c1f734b695ae9b29a7ec0a6f264#code

### Main_NFT:

0x66e8cf86Ae35A96e4B67021689B4fCf47C3267c5

https://testnet.bscscan.com/address/0x66e8cf86Ae35A96e4B67021689B4fCf47C3267c5#code


### NoddeDynamicNFT:

0x925c493975aE018bCf77dDc25290869a56671dBf

https://testnet.bscscan.com/address/0x925c493975aE018bCf77dDc25290869a56671dBf#code

### PublicDonation:

0x1F143C116A4B4E4AC650BE248BE8F4d1C935Ed3C

https://testnet.bscscan.com/address/0x1F143C116A4B4E4AC650BE248BE8F4d1C935Ed3C#code

### Subscriptions:

0xc65136CA205FbefBcB30466dD62A742a1B372327

https://testnet.bscscan.com/address/0xc65136CA205FbefBcB30466dD62A742a1B372327#code