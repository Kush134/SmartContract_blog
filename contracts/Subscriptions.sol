// SPDX-License-Identifier: MIT                                                

pragma solidity ^0.8.0;
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "./Interfaces/IMainNFT.sol";
import "./Interfaces/IUniswapV3Helper.sol";

contract Subscriptions is ReentrancyGuard {
    using SafeMath for uint256;

    uint8 constant public decimalsForUSD = 4;
    int256 public lastCoinPriceInUSD;

    IMainNFT mainNFT;
    AggregatorV3Interface priceFeedChainlink;

    struct Discount{
        uint32 numberOfPeriods;
        uint16 amountAsPPM;
    }

    struct Payment{
        address tokenAddress;
        uint256 amount;
        uint256 amountInEth;
        uint256 paymentTime;
    }

    struct Subscription{
        bytes32 hexId;
        bool isActive;
        bool isRegularSubscription;
        uint256 paymetnPeriod;
        address tokenAddress;
        uint256 price;
    }

    struct Participant{
        address participantAddress;
        uint256 subscriptionEndTime;
    }

    mapping(uint256 => mapping(address => bool)) public blackListByAuthor;
    mapping(uint256 => Subscription[]) public subscriptionsByAuthor;
    mapping(uint256 => mapping(uint256 => Discount[])) public discountSubscriptionsByAuthor;
    mapping(uint256 => mapping(uint256 => Participant[])) public participantsSubscriptionsByAuthor;
    mapping(uint256 => mapping(uint256 => mapping(address => uint256))) public participantIndex;
    mapping(bytes32 => uint256[2]) public subscriptionIndexByHexId;
    
    mapping(uint256 => mapping(uint256 => Payment[])) public paymentSubscriptionsByAuthor;
    mapping(uint256 => mapping(uint256 => uint256)) public totalPaymentSubscriptionsByAuthoInEth;
    mapping(uint256 => mapping(uint256 => uint256)) public totalPaymentSubscriptionsByAuthoInUSD;

    event Received(address indexed sender, uint256 value);
    event NewOneTimeSubscriptionCreated(uint256 indexed author, bytes32 indexed hexId, address tokenAddress, uint256 price, Discount[] discounts);
    event NewRegularSubscriptionCreated(uint256 indexed author, bytes32 indexed hexId, address tokenAddress, uint256 price, uint256 paymetnPeriod, Discount[] discounts);
    event NewSubscription(bytes32 indexed hexId, address indexed participant, uint256 indexed author, uint256 subscriptionIndex, uint256 subscriptionEndTime, address tokenAddress, uint256 amount);

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
        priceFeedChainlink = AggregatorV3Interface(mainNFT.getPriceFeedChainlinkAddress());
    }

    /***************Author options BGN***************/
    function addToBlackList(address user, uint256 author) public onlyAuthor(author){
        blackListByAuthor[author][user] = true;
    }

    function removeBlackList(address user, uint256 author) public onlyAuthor(author){
        blackListByAuthor[author][user] = false;
    }

    function createNewSubscriptionByEth(
        bytes32 hexId,
        uint256 author,
        bool isRegularSubscription,
        uint256 paymetnPeriod,
        uint256 price,
        Discount[] memory discountProgramm) public onlyAuthor(author){
            createNewSubscriptionByToken(hexId, author, isRegularSubscription, paymetnPeriod, address(0), price, discountProgramm);
    }

    function createNewSubscriptionByToken(
        bytes32 hexId,
        uint256 author,
        bool isRegularSubscription,
        uint256 paymetnPeriod,
        address tokenAddress,
        uint256 price,
        Discount[] memory discountProgramm) public onlyAuthor(author){
            uint256[2] memory arrayHexId = subscriptionIndexByHexId[hexId];
            require(_efficientHash(bytes32(arrayHexId[0]), bytes32(arrayHexId[1])) == _efficientHash(bytes32(0), bytes32(0)),"Specified hexId is already in use");
            require(tokenAddress == address(0) && price >= 10**6 || price > 0, "Low price");
            require(!isRegularSubscription || paymetnPeriod >= 4 hours, "Payment period cannot be less than 4 hours for regular subscription");
            require(tokenAddress == address(0) || mainNFT.converTokenPriceToEth(tokenAddress, 10**24) > 0, "It is not possible to accept payment");

            uint256 len = subscriptionsByAuthor[author].length;
            subscriptionIndexByHexId[hexId] = [author, len];
            for (uint256 i = 0; i < discountProgramm.length; i++){
                require(discountProgramm[i].amountAsPPM <= 1000, "Error in discount programm");
                discountSubscriptionsByAuthor[author][len].push(discountProgramm[i]);
            }

            participantIndex[author][len][address(this)] = participantsSubscriptionsByAuthor[author][len].length;
            participantsSubscriptionsByAuthor[author][len].push(Participant(address(this), type(uint256).max));

            Subscription memory subscription = Subscription({
                hexId: hexId,
                isActive: true,
                isRegularSubscription: isRegularSubscription,
                paymetnPeriod: paymetnPeriod,
                tokenAddress: tokenAddress,
                price: price
            });
            subscriptionsByAuthor[author].push(subscription);

            if (isRegularSubscription) {
                emit NewRegularSubscriptionCreated(author, hexId, tokenAddress, price, paymetnPeriod, discountProgramm);
            } else {
                emit NewOneTimeSubscriptionCreated(author, hexId, tokenAddress, price, discountProgramm);
            }
    }

    function changeActivityState(uint256 author, uint256 subscriptionIndex) public onlyAuthor(author){
        subscriptionsByAuthor[author][subscriptionIndex].isActive = !subscriptionsByAuthor[author][subscriptionIndex].isActive;
    }

    function setNewDiscountProgramm(uint256 author, uint256 subscriptionIndex, Discount[] memory discountProgramm) public onlyAuthor(author){
        require(subscriptionsByAuthor[author][subscriptionIndex].isActive, "Subscription is not active");
        uint256 len = discountSubscriptionsByAuthor[author][subscriptionIndex].length;
        while (len-- > 0){
            discountSubscriptionsByAuthor[author][subscriptionIndex].pop();
        }
        for (uint256 i = 0; i < discountProgramm.length; i++){
            require(discountProgramm[i].amountAsPPM < 1000, "Error in discount programm");
            discountSubscriptionsByAuthor[author][len].push(discountProgramm[i]);
        }
    }

    function setNewPaymetnPeriod(uint256 author, uint256 subscriptionIndex, uint256 paymetnPeriod) public onlyAuthor(author){
        require(subscriptionsByAuthor[author][subscriptionIndex].isActive, "Subscription is not active");
        require(subscriptionsByAuthor[author][subscriptionIndex].isRegularSubscription, "Only for regular subscription");
        require(paymetnPeriod >= 4 hours, "Payment period cannot be less than 4 hours");
        subscriptionsByAuthor[author][subscriptionIndex].paymetnPeriod = paymetnPeriod;
    }

    function setNewTokensAndPrice(uint256 author, uint256 subscriptionIndex, address tokenAddress, uint256 price) public onlyAuthor(author){
        require(subscriptionsByAuthor[author][subscriptionIndex].isActive, "Subscription is not active");
        require(tokenAddress == address(0) && price >= 10**6 || price > 0, "Low price");
        require(tokenAddress == address(0) || mainNFT.converTokenPriceToEth(tokenAddress, 10**24) > 0, "The token is not suitable for payment");

        subscriptionsByAuthor[author][subscriptionIndex].tokenAddress = tokenAddress;
        subscriptionsByAuthor[author][subscriptionIndex].price = price;
    }

    function getSubscriptionsByAuthor(uint256 author) public view returns (Subscription[] memory){
        return subscriptionsByAuthor[author];
    }

    function getDiscountSubscriptionsByAuthor(uint256 author, uint256 subscriptionIndex) public view returns (Discount[] memory){
        return discountSubscriptionsByAuthor[author][subscriptionIndex];
    }

    function getPaymentSubscriptionsByAuthor(uint256 author, uint256 subscriptionIndex) public view returns (Payment[] memory){
        return paymentSubscriptionsByAuthor[author][subscriptionIndex];
    }

    function getParticipantsSubscriptionsByAuthor(uint256 author, uint256 subscriptionIndex) public view returns (Participant[] memory){
        return participantsSubscriptionsByAuthor[author][subscriptionIndex];
    }

    function getRatingSubscriptionsByAuthor(uint256 author, uint256 subscriptionIndex) public view returns (uint256 active, uint256 cancelled){
        Participant[] memory participants = participantsSubscriptionsByAuthor[author][subscriptionIndex];
        for(uint256 i = 0; i < participants.length; i++){
            if (participants[i].subscriptionEndTime >= block.timestamp){
                active++;
            } else {
                cancelled++;
            }
        }
    }

    function getTotalPaymentAmountForPeriod( 
        uint256 author, 
        uint256 subscriptionIndex, 
        uint32 numberOfSubscriptionPeriods) public view returns (uint256 amountInToken, uint256 amountInEth){
        Subscription memory subscription = subscriptionsByAuthor[author][subscriptionIndex];
        Discount[] memory discount = discountSubscriptionsByAuthor[author][subscriptionIndex];
        uint256 maxDiscount = 0;
        if (subscription.isRegularSubscription){
            for (uint256 i = 0; i < discount.length; i++){
                if (numberOfSubscriptionPeriods >= discount[i].numberOfPeriods && maxDiscount < discount[i].amountAsPPM){
                    maxDiscount = discount[i].amountAsPPM;
                }
            }
        } else {
            numberOfSubscriptionPeriods = 1;
        }
        amountInToken = subscription.price.mul(numberOfSubscriptionPeriods).mul(1000 - maxDiscount).div(1000);
        amountInEth = subscription.tokenAddress != address(0) ? amountInToken : mainNFT.converTokenPriceToEth(subscription.tokenAddress, amountInToken);
    }

    function getSubscriptionPriceFromCustomToken(uint256 author, uint256 subscriptionIndex, uint32 numberOfSubscriptionPeriods, address customTokenAddress) public view returns(uint256) {
        Subscription memory subscription = subscriptionsByAuthor[author][subscriptionIndex];
        (uint256 amountInToken, uint256 amountInEth) = getTotalPaymentAmountForPeriod(author, subscriptionIndex, numberOfSubscriptionPeriods);
        if (customTokenAddress == subscription.tokenAddress) {
            return amountInToken;
        }
        if (customTokenAddress == address(0)) {
            return amountInEth;
        }
        IUniswapV3Helper uniswapV3Helper = IUniswapV3Helper(mainNFT.getUniswapHelperAddress());
        return uniswapV3Helper.getAmountInMaximum(customTokenAddress, subscription.tokenAddress, amountInToken);
    }

    function getSubscriptionIndexByHexId(bytes32 hexId) public view returns (uint256[2] memory){
        return subscriptionIndexByHexId[hexId];
    }
    /***************Author options END***************/

    /***************User interfaces BGN***************/
    function subscriptionPayment(uint256 author, uint256 subscriptionIndex, address participantSelectedTokenAddress, uint32 numberOfSubscriptionPeriods) public payable{
        require(!blackListByAuthor[author][msg.sender], "You blacklisted");
        Subscription memory subscription = subscriptionsByAuthor[author][subscriptionIndex];
        require(subscription.isRegularSubscription && numberOfSubscriptionPeriods > 0, "Periods must be greater than zero");
        require(subscription.isActive, "Subscription is not active");
        require(mainNFT.converTokenPriceToEth(participantSelectedTokenAddress, 10**24) > 0, "The token is not suitable for payment");
        uint256 thisParticipantIndex = participantIndex[author][subscriptionIndex][msg.sender];
        require(thisParticipantIndex == 0 || subscription.isRegularSubscription, "You already have access to a subscription");
        (uint256 amountInToken, uint256 amountInEth) = getTotalPaymentAmountForPeriod(author, subscriptionIndex, numberOfSubscriptionPeriods);
        if (subscription.tokenAddress == address(0) && participantSelectedTokenAddress == address(0)){
            require(msg.value >= amountInToken, "Payment value does not match the price");
            _paymentEth(author, amountInToken);
            if (msg.value > amountInToken) {
                TransferHelper.safeTransferETH(msg.sender, msg.value - amountInToken);
            }
        } else {
            if (participantSelectedTokenAddress != subscription.tokenAddress){
                _swapTokenAndPay(msg.sender, participantSelectedTokenAddress, subscription.tokenAddress, amountInToken, author);
            } else {
                _paymentToken(msg.sender, participantSelectedTokenAddress, amountInToken, author);
            }
        }

        uint256 subscriptionEndTime = subscription.isRegularSubscription ?
            (block.timestamp).add(subscription.paymetnPeriod.mul(numberOfSubscriptionPeriods)) : type(uint256).max;
        if (thisParticipantIndex != 0){
            subscriptionEndTime = (participantsSubscriptionsByAuthor[author][subscriptionIndex][thisParticipantIndex].subscriptionEndTime)
                .add(subscription.paymetnPeriod.mul(numberOfSubscriptionPeriods));
            participantsSubscriptionsByAuthor[author][subscriptionIndex][thisParticipantIndex].subscriptionEndTime = subscriptionEndTime;
        } else {
            Participant[] storage participants = participantsSubscriptionsByAuthor[author][subscriptionIndex];
            participantIndex[author][subscriptionIndex][msg.sender] = participants.length;
            participants.push(Participant(msg.sender, subscriptionEndTime));
        }
        paymentSubscriptionsByAuthor[author][subscriptionIndex].push(Payment(subscription.tokenAddress, amountInToken, amountInEth, block.timestamp));
        totalPaymentSubscriptionsByAuthoInEth[author][subscriptionIndex] += amountInEth;

        (,int256 priceInUSD,,,) = priceFeedChainlink.latestRoundData();
        if (lastCoinPriceInUSD != priceInUSD) {
            lastCoinPriceInUSD = priceInUSD;
        }
        uint256 modPriceInUSD = uint256(lastCoinPriceInUSD >= 0 ? lastCoinPriceInUSD : -lastCoinPriceInUSD);
        uint8 decimals = priceFeedChainlink.decimals();
        uint256 amountInUSD = amountInEth.mul(modPriceInUSD).div(10**(18 - decimalsForUSD + decimals));
        if (lastCoinPriceInUSD >= 0) {
            totalPaymentSubscriptionsByAuthoInUSD[author][subscriptionIndex] += amountInUSD;
        } else if (totalPaymentSubscriptionsByAuthoInUSD[author][subscriptionIndex] > amountInUSD) {
            totalPaymentSubscriptionsByAuthoInUSD[author][subscriptionIndex] -= amountInUSD;
        }        

        emit NewSubscription(subscription.hexId, msg.sender, author, subscriptionIndex, subscriptionEndTime, subscription.tokenAddress, amountInToken);
    }

    function _paymentEth(uint256 author, uint256 value) internal nonReentrant {
        uint256 contractFee = mainNFT.contractFeeForAuthor(author, value);
        TransferHelper.safeTransferETH(commissionCollector(), contractFee);
        uint256 amount = value - contractFee;
        TransferHelper.safeTransferETH(ownerOf(author), amount);
        mainNFT.addAuthorsRating(address(0), value, author);
    }

    function _swapTokenAndPay(address sender, address selectedTokenAddress, address tokenAddress, uint256 tokenAmount, uint256 author) internal {
        IUniswapV3Helper uniswapV3Helper = IUniswapV3Helper(mainNFT.getUniswapHelperAddress());
        if (selectedTokenAddress != address(0)) {
            uint256 amountInMaximum = uniswapV3Helper.getAmountInMaximum(selectedTokenAddress, tokenAddress, tokenAmount);
            TransferHelper.safeApprove(selectedTokenAddress, mainNFT.getUniswapHelperAddress(), type(uint256).max);
            TransferHelper.safeTransferFrom(selectedTokenAddress, sender, address(this), amountInMaximum);
            if (tokenAddress == address(0)) {
                uniswapV3Helper.swapExactOutputToETH(sender, selectedTokenAddress, amountInMaximum, tokenAmount);
                _paymentEth(author, tokenAmount);
            } else {                
                uniswapV3Helper.swapExactOutput(address(this), sender, selectedTokenAddress, tokenAddress, amountInMaximum, tokenAmount);
                _paymentTokenFromContract(tokenAddress, tokenAmount, author);
            }
        } else {
            uniswapV3Helper.swapExactOutputFromETH{value: msg.value}(sender, tokenAddress, tokenAmount);
            _paymentTokenFromContract(tokenAddress, tokenAmount, author);
        }
    }

    function _paymentToken(address sender, address tokenAddress, uint256 tokenAmount, uint256 author) internal nonReentrant {
        uint256 contractFee = mainNFT.contractFeeForAuthor(author, tokenAmount);
        TransferHelper.safeTransferFrom(tokenAddress, sender, commissionCollector(), contractFee);
        uint256 amount = tokenAmount.sub(contractFee);
        TransferHelper.safeTransferFrom(tokenAddress, sender, ownerOf(author), amount);
        mainNFT.addAuthorsRating(tokenAddress, tokenAmount, author);
    }

    function _paymentTokenFromContract(address tokenAddress, uint256 tokenAmount, uint256 author) internal nonReentrant {
        uint256 contractFee = mainNFT.contractFeeForAuthor(author, tokenAmount);
        TransferHelper.safeTransfer(tokenAddress, commissionCollector(), contractFee);
        uint256 amount = tokenAmount.sub(contractFee);
        TransferHelper.safeTransfer(tokenAddress, ownerOf(author), amount);
        mainNFT.addAuthorsRating(tokenAddress, tokenAmount, author);
    }
    /***************User interfaces END***************/

    /***************Support BGN***************/
    function _efficientHash(bytes32 a, bytes32 b) internal pure returns (bytes32 value) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }

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
        priceFeedChainlink = AggregatorV3Interface(mainNFT.getPriceFeedChainlinkAddress());
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