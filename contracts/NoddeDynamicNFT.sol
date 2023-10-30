// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./libraries/Base64.sol";
import "./Interfaces/IMainNFT.sol";

contract NoddeDynamicNFT is ERC721Enumerable, Ownable {
    using Strings for uint8;
    using Strings for uint256;
    IMainNFT public mainNFT;
    string public baseImageURI;

    mapping(uint256 => string) public imgScrFromAutor;
    mapping(uint256 => string) public autorsTitle;
    mapping(uint256 => string) public autorsDescription;

    function authorsLevel(uint256 tokenId) public view virtual returns (uint256) {
        uint256 _totalRating = mainNFT.totalRating()  > 10**20 ? mainNFT.totalRating() : 10**20;
        uint256 protoLevel =  (10 ** mainNFT.levels()) * mainNFT.authorsRating(tokenId) / _totalRating;
        uint256 level = myLog10(protoLevel);
        return level >= mainNFT.levels() || tokenId == 0 ? mainNFT.levels() : level + 1;
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

    function getImageURI(uint256 level) private view returns (string memory) {
        uint256 uriNumber = level - 1;
        return
            bytes(baseImageURI).length > 0
                ? string(abi.encodePacked(baseImageURI, uriNumber.toString(), ".png"))
                : "";
    }

    function generateHTML(uint256 tokenId) internal view returns (string memory imageUri, string memory rawAnimationImage) {
        uint256 level = authorsLevel(tokenId);
        imageUri = stringSelector(imgScrFromAutor[tokenId], getImageURI(level));
        rawAnimationImage = string(abi.encodePacked(
            '<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"/><meta name="viewport"/><title>NFT</title><style>body{background-image:url("', 
            imageUri, 
            '");background-position:center;background-size:cover;background-repeat:no-repeat;height:100vh;width:100vw;margin:0;}.sc{position:fixed;top:90%;left:50%;transform:translate(-50%,-50%);min-width:50%;max-width:90%;background-color:#ffffff;border-radius:20px;box-shadow:0 2px 10px #00000033;display:flex;justify-content:space-around;padding:20px;}.star{display:inline-block;vertical-align:top;width:5vh;height:5vh;background:linear-gradient(to bottom,#c5c4c4 0%,#b4b3b2 100%);position:relative;vertical-align:middle;animation-duration:1s;animation-fill-mode:both;animation:bounce 4s infinite;}.star:before{content:"";position:absolute;top:1px;left:1px;bottom:1px;right:1px;z-index:1;}.star,.star:before{-webkit-clip-path:polygon(50% 0%,66% 27%,98% 35%,76% 57%,79% 91%,50% 78%,21% 91%,24% 57%,2% 35%,32% 27%);clip-path:polygon(50% 0%,66% 27%,98% 35%,76% 57%,79% 91%,50% 78%,21% 91%,24% 57%,2% 35%,32% 27%);}.star.gold{background-image:radial-gradient(#ffeb3b,#ffd700);box-shadow:0 0 5vh #ffd700;width:6vh;height:6vh;}@keyframes glow{0%{box-shadow:0 0 1vh #ffff0080;}50%{box-shadow:0 0 2vh #ffff00;}100%{box-shadow:0 0 1vh #ffff0080;}}@keyframes bounce{0%,30%{transform:translateY(0);}5%{transform:translateY(-25px);}10%{transform:translateY(20px);}15%{transform:translateY(-10px);}20%{transform:translateY(10px);}25%{transform:translateY(-5px);}}</style></head><body><div class="sc"></div><script>const numStars=',
            level.toString(),
            ';const sc=document.querySelector(".sc");for(let i=1;i<=',
            (mainNFT.levels()).toString(),
            ';i++){const star=document.createElement("div");star.classList.add("star");if(i<=numStars){star.classList.add("gold");}sc.appendChild(star);}const stars=document.querySelectorAll(".star");function animate(){let delay=0;stars.forEach((star,index)=>{star.style.animationDelay=`${delay}s`;delay+=0.1;});}animate();</script></body></html>'
        ));
    }

    function htmlToImageURI(string memory html) internal pure returns (string memory) {
        string memory baseURL = "data:text/html;base64,";
        string memory htmlBase64Encoded = Base64.encode(bytes(string(abi.encodePacked(html))));
        return string(abi.encodePacked(baseURL, htmlBase64Encoded));
    }

    function setAttributes(uint256 tokenId, string memory imgScr, string memory title, string memory description) public {
        require(msg.sender == mainNFT.ownerOf(tokenId) || msg.sender == owner(), "SA");
        if (bytes(imgScr).length > 0) {
            imgScrFromAutor[tokenId] = imgScr;
        }
        if (bytes(title).length > 0) {
            autorsTitle[tokenId] = title;
        }
        if (bytes(description).length > 0) {
            autorsDescription[tokenId] = description;
        }
    }
    
    constructor(address _mainNFTAddress, string memory _baseImageURI) ERC721("The NODDE Dynamic NFT", "NoddeNFT") {
        mainNFT = IMainNFT(_mainNFTAddress);
        setBaseImageURI(_baseImageURI);
        _safeMint(address(this), 0);
        mintAll();
    }

    function mintAll() public {
        uint256 startIndex = totalSupply();
        uint256 endIndex = mainNFT.totalSupply();
        for (uint256 i = startIndex; i < endIndex; i++ ) {
            _safeMint(mainNFT.ownerOf(i), i);
        }
    }

    function setBaseImageURI(string memory _baseImageURI) public onlyOwner {
        baseImageURI = _baseImageURI;
    }

    /***************ERC-721 wrapper BGN***************/
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        uint256 bnbAmount = mainNFT.authorsAmountsInETH(tokenId) / 10**16;
        uint256 usdAmount = mainNFT.authorsAmountsInUSD(tokenId) / 10**(mainNFT.decimalsForUSD() - 2);

        (string memory imageUri, string memory rawAnimationImage) = generateHTML(tokenId);
        string memory animationImage = htmlToImageURI(rawAnimationImage);

        return string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                '{"name":"',
                                'The NODDE Dynamic NFT | Channel title: ', stringSelector(autorsTitle[tokenId], "not set"),
                                '", "description":"', stringSelector(autorsDescription[tokenId], "not set"),
                                '", "attributes":[',
                                '{ "trait_type":"rating","value":"', (authorsLevel(tokenId)).toString(), ' of ', (mainNFT.levels()).toString(), ' stars" },',
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
    /***************ERC-721 wrapper END***************/

    /***************Royalty BGN***************/
    function withdraw() external onlyOwner {
        (bool success, ) = _msgSender().call{value: address(this).balance}("");
        require(success, "withdraw failed");
    }

    receive() external payable { }
    /***************Royalty END***************/
}