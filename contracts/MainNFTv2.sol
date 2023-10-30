// SPDX-License-Identifier: GPL-2.0-or-later                                          
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "./Interfaces/IUniswapV3Helper.sol";
import "./libraries/Base64.sol";

contract MainNFT is ERC721Enumerable, IERC2981, Ownable, ReentrancyGuard {
    using Strings for uint8;
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
    mapping (uint256 => uint256) public authorsAmountsInETH;
    mapping (uint256 => uint256) public authorsAmountsInUSD;
    mapping (uint256 => uint256) public authorsRating;
    mapping (address => bool) public verifiedContracts;
    mapping(uint256 => string) public authorsLogoUri;
    mapping(uint256 => string) public authorsTitle;
    mapping(uint256 => string) public authorsDescription;
    string public baseImageUri;

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

    constructor(address _uniswapHelperAddress, address _priceFeedAddress, uint8 _levelsCount, string memory _baseImageUri) ERC721("SocialFi", "SoFi") {
        levels = _levelsCount;
        baseImageUri = _baseImageUri;
        setNewUniswapHelper(_uniswapHelperAddress);
        setNewPriceFeedChainlink(_priceFeedAddress);
        _safeMint(address(this), 0);
        baseRating = ((block.timestamp) / 3_600) * baseRating;
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

    function authorsLevel(uint256 tokenId) public view virtual returns (uint256) {
        _requireMinted(tokenId);
        uint256 _totalRating = totalRating  > baseRating ? totalRating : baseRating;
        uint256 protoLevel = (10 ** levels) * authorsRating[tokenId] / _totalRating;
        uint256 level = myLog10(protoLevel);
        return level >= levels || tokenId == 0 ? levels : level + 1;
    }

    function myLog10(uint256 x) internal pure returns (uint256) {
        uint256 result = 0;
        while (x >= 10){
            x /= 10;
            result += 1;
        }
        return result;
    }

    function stringSelector(string memory targetStr, string memory defaultStr) private pure returns (string memory) {
        return bytes(targetStr).length > 0 ? targetStr : defaultStr;
    }

    function generateHTML(uint256 tokenId) internal view returns (string memory imageUri, string memory rawAnimationImage) {
        imageUri = stringSelector(authorsLogoUri[tokenId], baseImageUri);
        rawAnimationImage = string(abi.encodePacked(
            '<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"/><meta name="viewport"/><title>NFT</title><style>body{background-image:url("', 
            imageUri, 
            '");background-position:center;background-size:cover;background-repeat:no-repeat;height:100vh;width:100vw;margin:0;}.sc{position:fixed;top:90%;left:50%;transform:translate(-50%,-50%);min-width:50%;max-width:90%;background-color:#ffffff;border-radius:20px;box-shadow:0 2px 10px #00000033;display:flex;justify-content:space-around;padding:20px;}.star{display:inline-block;vertical-align:top;width:5vh;height:5vh;background:linear-gradient(to bottom,#c5c4c4 0%,#b4b3b2 100%);position:relative;vertical-align:middle;animation-duration:1s;animation-fill-mode:both;animation:bounce 4s infinite;}.star:before{content:"";position:absolute;top:1px;left:1px;bottom:1px;right:1px;z-index:1;}.star,.star:before{-webkit-clip-path:polygon(50% 0%,66% 27%,98% 35%,76% 57%,79% 91%,50% 78%,21% 91%,24% 57%,2% 35%,32% 27%);clip-path:polygon(50% 0%,66% 27%,98% 35%,76% 57%,79% 91%,50% 78%,21% 91%,24% 57%,2% 35%,32% 27%);}.star.gold{background-image:radial-gradient(#ffeb3b,#ffd700);box-shadow:0 0 5vh #ffd700;width:6vh;height:6vh;}@keyframes glow{0%{box-shadow:0 0 1vh #ffff0080;}50%{box-shadow:0 0 2vh #ffff00;}100%{box-shadow:0 0 1vh #ffff0080;}}@keyframes bounce{0%,30%{transform:translateY(0);}5%{transform:translateY(-25px);}10%{transform:translateY(20px);}15%{transform:translateY(-10px);}20%{transform:translateY(10px);}25%{transform:translateY(-5px);}}</style></head><body><div class="sc"></div><script>const numStars=',
            (authorsLevel(tokenId)).toString(),
            ';const sc=document.querySelector(".sc");for(let i=1;i<=',
            levels.toString(),
            ';i++){const star=document.createElement("div");star.classList.add("star");if(i<=numStars){star.classList.add("gold");}sc.appendChild(star);}const stars=document.querySelectorAll(".star");function animate(){let delay=0;stars.forEach((star,index)=>{star.style.animationDelay=`${delay}s`;delay+=0.1;});}animate();</script></body></html>'
        ));
    }

    function htmlToImageURI(string memory html) internal pure returns (string memory) {
        string memory baseURL = "data:text/html;base64,";
        string memory htmlBase64Encoded = Base64.encode(bytes(string(abi.encodePacked(html))));
        return string(abi.encodePacked(baseURL, htmlBase64Encoded));
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        uint256 bnbAmount = authorsAmountsInETH[tokenId] / 10**16;
        uint256 usdAmount = authorsAmountsInUSD[tokenId] / 10**(decimalsForUSD - 2);

        (string memory imageUri, string memory rawAnimationImage) = generateHTML(tokenId);
        string memory animationImage = htmlToImageURI(rawAnimationImage);

        return string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                '{"name":"',
                                'The NODDE Dynamic NFT | Channel title: ', stringSelector(authorsTitle[tokenId], "not set"),
                                '", "description":"', stringSelector(authorsDescription[tokenId], "not set"),
                                '", "attributes":[',
                                '{ "trait_type":"rating","value":"', (authorsLevel(tokenId)).toString(), ' of ', levels.toString(),' stars" },',
                                '{ "trait_type":"Total amount in BNB","value": "BNB ', (bnbAmount / 100).toString(), '.', (bnbAmount % 100).toString(),'" },',
                                '{ "trait_type":"Total amount in USD","value": "$ ', (usdAmount / 100).toString(), '.', (usdAmount % 100).toString(),'" }',
                                '], "image":"', imageUri,
                                '", "animation_url":"', animationImage,
                                '"}'
                            )
                        )
                    )
                )
            );
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
    function setAttributes(uint256 author, string memory logoUri, string memory title, string memory description) public {
        require(msg.sender == ownerOf(author) || msg.sender == managers[author] || msg.sender == owner(), "SA");
        if (bytes(logoUri).length > 0) {
            authorsLogoUri[author] = logoUri;
        }
        if (bytes(title).length > 0) {
            authorsTitle[author] = title;
        }
        if (bytes(description).length > 0) {
            authorsDescription[author] = description;
        }
    }

    function addAuthorsRating(address tokenAddress, uint256 tokenAmount, uint256 author) public onlyVerified(msg.sender) {
        uint256 value = tokenAddress == address(0) ? tokenAmount : converTokenPriceToEth(tokenAddress, tokenAmount);
        _addAuthorsRating(value, author);
    }

    function _addAuthorsRating(uint256 value, uint256 author) private {
        totalAmountsInETH += value;
        authorsAmountsInETH[author] += value;

        uint256 rating = ((block.timestamp) / 3_600) * value;
        totalRating += rating;
        authorsRating[author] += rating;

        (,int256 priceInUSD,,,) = priceFeedChainlink.latestRoundData();
        if (lastCoinPriceInUSD != priceInUSD) {
            lastCoinPriceInUSD = priceInUSD;
        }
        uint256 modPriceInUSD = uint256(lastCoinPriceInUSD >= 0 ? lastCoinPriceInUSD : -lastCoinPriceInUSD);
        uint8 decimals = priceFeedChainlink.decimals();
        uint256 valueInUSD = value * modPriceInUSD / (10**(18 - decimalsForUSD + decimals));
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
    function setBaseSettings(uint8 _levelsCount, string memory _baseImageUri) external onlyOwner {
        levels = _levelsCount;
        baseImageUri = _baseImageUri;
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