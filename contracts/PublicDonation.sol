// SPDX-License-Identifier: GPL-2.0-or-later                                               
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "./Interfaces/IMainNFT.sol";
import "./Interfaces/IUniswapV3Helper.sol";

contract PublicDonation is  ReentrancyGuard {
    using SafeMath for uint256;
    IMainNFT mainNFT;

    mapping(uint256 => address[]) donateTokenAddressesByAuthor;

    event Received(address indexed sender, uint256 value);
    event Donate(address indexed sender, address indexed token, uint256 value, uint256 indexed author);

    modifier onlyAuthor(uint256 author) {
        require(mainNFT.onlyAuthor(msg.sender, author), "Only for Author");
        _;
    }

    modifier supportsERC20(address _address){
        require(
            _address == address(0) || IERC20(_address).totalSupply() > 0 && IERC20(_address).allowance(_address, _address) >= 0,
            "Is not ERC20"
        );
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner(), "Only owner");
        _;
    }

    constructor(address _mainNFTAddress) {
        mainNFT = IMainNFT(_mainNFTAddress);
        mainNFT.setVerfiedContracts(true, address(this));
    }

    /***************Author options BGN***************/
    function addDonateAddress(address tokenAddress, uint256 author) supportsERC20(tokenAddress) onlyAuthor(author) public {
        address[] storage tokens = donateTokenAddressesByAuthor[author];
        require(!mainNFT.isAddressExist(tokenAddress, tokens), "Already exists");
        tokens.push(tokenAddress);
    }

    function removeDonateAddress(address tokenAddress, uint256 author) supportsERC20(tokenAddress) onlyAuthor(author) public {
        address[] storage tokens = donateTokenAddressesByAuthor[author];
        require(mainNFT.isAddressExist(tokenAddress, tokens), "Not exist");
        for (uint i = 0; i < tokens.length; i++) {
            if (tokens[i] == tokenAddress) {
                tokens[i] = tokens[tokens.length - 1];
                tokens.pop();
                break;
            }
        }
    }
    /***************Author options END***************/

    /***************User interfaces BGN***************/
    function getAllDonateTokenAddressesByAuthor(uint256 author) public view returns (address[] memory){
        return donateTokenAddressesByAuthor[author];
    }

    function paymentEth(uint256 author, uint256 value) internal nonReentrant {
        uint256 contractFee = mainNFT.contractFeeForAuthor(author, value);
        TransferHelper.safeTransferETH(commissionCollector(), contractFee);
        uint256 amount = value - contractFee;
        TransferHelper.safeTransferETH(ownerOf(author), amount);
        mainNFT.addAuthorsRating(address(0), value, author);
    }

    function paymentToken(address sender, address tokenAddress, uint256 tokenAmount, uint256 author) internal nonReentrant {
        address[] memory tokensByAuthor = donateTokenAddressesByAuthor[author];
        require(mainNFT.isAddressExist(tokenAddress, tokensByAuthor), "Token not exist");

        uint256 contractFee = mainNFT.contractFeeForAuthor(author, tokenAmount);
        TransferHelper.safeTransferFrom(tokenAddress, sender, commissionCollector(), contractFee);
        uint256 amount = tokenAmount - contractFee;
        TransferHelper.safeTransferFrom(tokenAddress, sender, commissionCollector(), amount);
        mainNFT.addAuthorsRating(tokenAddress, tokenAmount, author);
    }

    function donateEth(uint256 author) public payable {        
        require(msg.value >= 10**6, "Low value");
        paymentEth(author, msg.value);
        emit Donate(msg.sender, address(0), msg.value, author);
    }

    function donateToken(address tokenAddress, uint256 tokenAmount, uint256 author) public {
        require(tokenAmount > 0, "Low value");
        paymentToken(msg.sender, tokenAddress, tokenAmount, author);
        emit Donate(msg.sender, tokenAddress, tokenAmount, author);
    }

    function donateFromSwap(address tokenAddress, uint256 tokenAmount, uint256 author) public {
        require(tokenAmount > 0, "Low value");
        address[] memory tokensByAuthor = donateTokenAddressesByAuthor[author];
        if (mainNFT.isAddressExist(tokenAddress, tokensByAuthor)) {
            paymentToken(msg.sender, tokenAddress, tokenAmount, author);
        } else {            
            TransferHelper.safeTransferFrom(tokenAddress, msg.sender, address(this), tokenAmount);
            TransferHelper.safeApprove(tokenAddress, mainNFT.getUniswapHelperAddress(), type(uint256).max);
            IUniswapV3Helper uniswapV3Helper = IUniswapV3Helper(mainNFT.getUniswapHelperAddress());
            uint256 amountOut = uniswapV3Helper.swapExactInputToETH(tokenAddress, tokenAmount);
            paymentEth(author, amountOut);
        }
        emit Donate(msg.sender, tokenAddress, tokenAmount, author);
    }
    /***************User interfaces END***************/

    /***************Support BGN***************/
    function owner() public view returns(address){
        return mainNFT.owner();
    }

    function commissionCollector() public view returns(address){
        return mainNFT.commissionCollector();
    }

    function ownerOf(uint256 author) public view returns (address){
        return mainNFT.ownerOf(author);
    }

    function setIMainNFT(address mainNFTAddress) external onlyOwner{
        mainNFT = IMainNFT(mainNFTAddress);        
        mainNFT.setVerfiedContracts(true, address(this));
    }

    function withdraw() external onlyOwner nonReentrant {
        uint256 amount = address(this).balance;
        TransferHelper.safeTransferETH(commissionCollector(), amount);
    }

    function withdrawTokens(address _address) external onlyOwner nonReentrant {
        uint256 amount = IERC20(_address).balanceOf(address(this));
        TransferHelper.safeTransfer(_address, commissionCollector(), amount);
    }
    /***************Support END**************/

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}