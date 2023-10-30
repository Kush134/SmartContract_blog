// SPDX-License-Identifier: MIT                                                
pragma solidity ^0.8.0;

interface IMainNFT {
    function authorsAmountsInETH(uint256) external view returns (uint256);
    function authorsAmountsInUSD(uint256) external view returns (uint256);
    function authorsRating(uint256) external view returns (uint256);
    function totalRating() external view returns (uint256);
    function levels() external view returns (uint8);
    function decimalsForUSD() external view returns (uint8);
    function tokenURI(uint256) external view returns (string memory);
    function getUniswapHelperAddress() external view returns (address);
    function getPriceFeedChainlinkAddress() external view returns (address);
    function ownerOf(uint256) external view returns (address);
    function owner() external view returns (address);
    function onlyAuthor(address, uint256) external pure returns (bool);
    function isAddressExist(address, address[] memory) external pure returns (bool);
    function contractFeeForAuthor(uint256, uint256) external view returns(uint256);
    function commissionCollector() external view returns (address);
    function addAuthorsRating(address, uint256, uint256) external;
    function setVerfiedContracts(bool, address) external;
    function converTokenPriceToEth(address, uint256) external view returns(uint256);
    function balanceOf(address) external view returns (uint256);
    function tokenOfOwnerByIndex(address, uint256) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function tokenByIndex(uint256) external view returns (uint256);
}