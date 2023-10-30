// SPDX-License-Identifier: GPL-2.0-or-later                                          
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./Interfaces/IUniswapV3Helper.sol";

contract MainNFT is ERC721Enumerable, IERC2981, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using Strings for uint256;

    uint8 constant public decimalsForUSD = 4;

    uint8 public levels;
    uint16 public royaltyFee = 1000;
    int256 public lastCoinPriceInUSD;
    uint256 public totalAmountsInETH;
    uint256 public totalAmountsInUSD;
    uint256 public totalRating;
    uint256 publicSaleTokenPrice = 0.1 ether;
    uint256 baseRating = 10**20;
    string public baseURI;
    mapping (uint256 => uint256) public authorsAmountsInETH;
    mapping (uint256 => uint256) public authorsAmountsInUSD;
    mapping (uint256 => uint256) public authorsRating;
    mapping (address => bool) public verifiedContracts;

    IUniswapV3Helper public uniswapHelper;
    AggregatorV3Interface public priceFeedChainlink;

    mapping(uint256 => address) public managers;

    event Received(address indexed sender, uint256 value);

    modifier onlyVerified(address _address){
        require(verifiedContracts[_address], "Is not verified");
        _;
    }

    modifier supportsERC20(address _address){
        require(
            _address == address(0) || IERC20(_address).totalSupply() > 0 && IERC20(_address).allowance(_address, _address) >= 0,
            "Is not ERC20"
        );
        _;
    }

    modifier isContract(address _addr) {
        uint256 size;
        assembly { size := extcodesize(_addr) }
        require(size > 0, "address is not contract");
        _;
    }

    constructor(address _uniswapHelperAddress, address _priceFeedAddress, uint8 _levelsCount, string memory _baseURI) ERC721("SocialFi", "SoFi") {
        levels = _levelsCount;
        baseURI = _baseURI;
        setNewUniswapHelper(_uniswapHelperAddress);
        setNewPriceFeedChainlink(_priceFeedAddress);
        _safeMint(address(this), 0);
        baseRating = block.timestamp.div(3_600).mul(baseRating);
        authorsRating[0] += baseRating;
    }

    /***************Common interfaces BGN***************/
    function priceToMint(address minter) public view returns(uint256){
        uint256 balance = balanceOf(minter);
        return publicSaleTokenPrice * (2 ** balance);
    }

    function safeMint() public nonReentrant payable {
        require(priceToMint(msg.sender) <= msg.value, "Low value");
        uint256 nextIndex = totalSupply();
        _addAuthorsRating(msg.value, nextIndex);
        _safeMint(msg.sender, nextIndex);
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);
        uint256 _totalRating = totalRating  > baseRating ? totalRating : baseRating;
        uint256 thisLevel = (10 ** levels) * authorsRating[tokenId] / _totalRating;
        uint256 uriNumber = myLog10(thisLevel);
        if (uriNumber >= levels || tokenId == 0){
            uriNumber = levels - 1;
        }
        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, uriNumber.toString(), ".json"))
                : "";
    }

    function myLog10(uint256 x) internal pure returns (uint256) {
        uint256 result = 0;
        while (x >= 10){
            x /= 10;
            result += 1;
        }
        return result;
    }

    function onlyAuthor(address sender, uint256 author) public view returns (bool){
        return ownerOf(author) == sender || managers[author] == sender;
    }

    function isAddressExist(address _addressToCheck, address[] memory _collection) public pure returns (bool) {
        for (uint i = 0; i < _collection.length; i++) {
            if (_collection[i] == _addressToCheck) {
                return true;
            }
        }
        return false;
    }

    function commissionCollector() public view returns (address){
        return address(this);
    }    

    function converTokenPriceToEth(address tokenAddress, uint256 tokenAmount) public view returns (uint256) {
        if (tokenAddress == address(0)) {
            return tokenAmount;
        }

        try uniswapHelper.convertAmountToETH(tokenAddress, tokenAmount) returns(uint256 amountOut) {
            return amountOut;
        } catch (bytes memory) {
            return 0;
        }
    }

    function getUniswapHelperAddress() public view returns (address) {
        return address(uniswapHelper);
    }

    function getPriceFeedChainlinkAddress() public view returns (address) {
        return address(priceFeedChainlink);
    }
    /***************Common interfaces END***************/

    /***************Author options BGN***************/
    function addAuthorsRating(address tokenAddress, uint256 tokenAmount, uint256 author) public onlyVerified(msg.sender) {
        uint256 value = tokenAddress == address(0) ? tokenAmount : converTokenPriceToEth(tokenAddress, tokenAmount);
        _addAuthorsRating(value, author);
    }

    function _addAuthorsRating(uint256 value, uint256 author) private {
        totalAmountsInETH += value;
        authorsAmountsInETH[author] += value;

        uint256 rating = block.timestamp.div(3_600).mul(value);
        totalRating += rating;
        authorsRating[author] += rating;

        (,int256 priceInUSD,,,) = priceFeedChainlink.latestRoundData();
        if (lastCoinPriceInUSD != priceInUSD) {
            lastCoinPriceInUSD = priceInUSD;
        }
        uint256 modPriceInUSD = uint256(lastCoinPriceInUSD >= 0 ? lastCoinPriceInUSD : -lastCoinPriceInUSD);
        uint8 decimals = priceFeedChainlink.decimals();
        uint256 valueInUSD = value.mul(modPriceInUSD).div(10**(18 - decimalsForUSD + decimals));
        if (lastCoinPriceInUSD >= 0) {
            totalAmountsInUSD += valueInUSD;
            authorsAmountsInUSD[author] += valueInUSD;
        } else if (totalAmountsInUSD > valueInUSD && authorsAmountsInUSD[author] > valueInUSD) {
            totalAmountsInUSD -= valueInUSD;
            authorsAmountsInUSD[author] -= valueInUSD;
        }
    }

    function setManager(address newManager, uint256 author) public {
        require(ownerOf(author) == msg.sender, "Only owner");
        managers[author] = newManager;
    }

    function contractFeeForAuthor(uint256 author, uint256 amount) public view returns(uint256){
        uint256 _totalRating = totalRating  > baseRating ? totalRating : baseRating;
        uint256 thisLevel = (10 ** levels) * authorsRating[author] / _totalRating;
        uint256 contractFee = amount * 2 / ( 100 * (2 ** myLog10(thisLevel)));
        return contractFee > 0 ? contractFee : 1;
    }
    /***************Author options END***************/

    /***************Only for owner BGN***************/
    function setBaseURI(uint8 _levelsCount, string memory _baseURI) external onlyOwner {
        levels = _levelsCount;
        baseURI = _baseURI;
    }

    function setPublicSaleTokenPrice(uint256 _newPrice) external onlyOwner {
        publicSaleTokenPrice = _newPrice;
    }

    function setNewUniswapHelper(address _uniswapHelperAddress) public onlyOwner isContract(_uniswapHelperAddress) {
        uniswapHelper = IUniswapV3Helper(_uniswapHelperAddress);
    }

    function setNewPriceFeedChainlink(address _priceFeedAddress) public onlyOwner isContract(_priceFeedAddress) {
        priceFeedChainlink = AggregatorV3Interface(_priceFeedAddress);
    }

    function setVerfiedContracts(bool isVerified, address _address) public {
        require(tx.origin == owner(), "Only original owner");
        verifiedContracts[_address] = isVerified;
    }
    
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Enumerable, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }

    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view override returns (address receiver, uint256 royaltyAmount) {
        require(_exists(tokenId), "nonexistent");
        return (address(this), (salePrice * royaltyFee) / 10000);
    }    

    function setRoyaltyFee(uint16 fee) external onlyOwner {
        require (fee < 10000, "too high");
        royaltyFee = fee;
    }

    function withdraw() external onlyOwner nonReentrant {
        uint256 amount = address(this).balance;
        (bool success, ) = _msgSender().call{value: amount}("");
        require(success, "fail");
    }

    function withdrawTokens(address _address) external onlyOwner nonReentrant {
        IERC20 token = IERC20(_address);
        uint256 amount = token.balanceOf(address(this));
        token.transfer(_msgSender(), amount);
    }
    /***************Only for owner END**************/

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}