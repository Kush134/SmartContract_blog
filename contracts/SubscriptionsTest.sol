// SPDX-License-Identifier: MIT                                                

pragma solidity ^0.8.18;
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

interface IMainNFT {
    function getUniswapRouterAddress() external view returns (address);
    function ownerOf(uint256) external view returns (address);
    function onlyAuthor(address, uint256) external pure returns (bool);
    function isAddressExist(address, address[] memory) external pure returns (bool);
    function contractFeeForAuthor(uint256, uint256) external view returns(uint256);
    function commissionCollector() external view returns (address);
    function addAuthorsRating(address, uint256, uint256) external;
    function setVerfiedContracts(bool, address) external;
    function converTokenPriceToEth(address, uint256) external view returns(uint256);
}

contract SubscriptionsTest is ReentrancyGuard {
    using SafeMath for uint256;

    IMainNFT mainNFT;    
    IUniswapV2Router02 uniswapRouter;

    struct Discount{
        uint256 period;
        uint16 amountAsPPM;
    }

    struct Payment{
        address tokenAddress;
        uint256 amount;
        uint256 amountInEth;
        uint256 paymentTime;
    }

    struct Subscription{
        bytes32 hexName;
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
    mapping(bytes32 => uint256[2]) public subscriptionIndexByHexName;
    
    mapping(uint256 => mapping(uint256 => Payment[])) public paymentSubscriptionsByAuthor;
    mapping(uint256 => mapping(uint256 => uint256)) public totalPaymentSubscriptionsByAuthoInEth;

    event Received(address indexed sender, uint256 value);
    event NewOneTimeSubscriptionCreated(uint256 indexed author, bytes32 indexed hexName, address tokenAddress, uint256 price, Discount[] discounts);
    event NewRegularSubscriptionCreated(uint256 indexed author, bytes32 indexed hexName, address tokenAddress, uint256 price, uint256 paymetnPeriod, Discount[] discounts);
    event NewSubscription(address indexed participant, uint256 indexed author, uint256 indexed subscriptionIndex, uint256 subscriptionEndTime, address tokenAddress, uint256 amount);

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

    constructor(address mainNFTAddress) {
        setIMainNFT(mainNFTAddress);
    }

    /***************Author options BGN***************/
    function addToBlackList(address user, uint256 author) public onlyAuthor(author){
        blackListByAuthor[author][user] = true;
    }

    function removeBlackList(address user, uint256 author) public onlyAuthor(author){
        blackListByAuthor[author][user] = false;
    }

    function createNewSubscriptionByEth(
        bytes32 hexName,
        uint256 author,
        bool isRegularSubscription,
        uint256 paymetnPeriod,
        uint256 price,
        Discount[] memory discountProgramm) public onlyAuthor(author){
            createNewSubscriptionByToken(hexName, author, isRegularSubscription, paymetnPeriod, address(0), price, discountProgramm);
    }

    function createNewSubscriptionByToken(
        bytes32 hexName,
        uint256 author,
        bool isRegularSubscription,
        uint256 paymetnPeriod,
        address tokenAddress,
        uint256 price,
        Discount[] memory discountProgramm) public onlyAuthor(author){
            uint256[2] memory nameHaxIndex = subscriptionIndexByHexName[hexName];
            require(_efficientHash(bytes32(nameHaxIndex[0]), bytes32(nameHaxIndex[1])) == _efficientHash(bytes32(0), bytes32(0)),"Specified haxName is already in use");
            require(tokenAddress == address(0) && price >= 10**6 || price > 0, "Low price");
            require(!isRegularSubscription || paymetnPeriod >= 4 hours, "Payment period cannot be less than 4 hours for regular subscription");
            require(tokenAddress == address(0) || mainNFT.converTokenPriceToEth(tokenAddress, 10**24) > 0, "It is not possible to accept payment");

            uint256 len = subscriptionsByAuthor[author].length;
            subscriptionIndexByHexName[hexName] = [author, len];
            for (uint256 i = 0; i < discountProgramm.length; i++){
                require(discountProgramm[i].amountAsPPM <= 1000, "Error in discount programm");
                discountSubscriptionsByAuthor[author][len].push(discountProgramm[i]);
            }

            participantIndex[author][len][address(this)] = participantsSubscriptionsByAuthor[author][len].length;
            participantsSubscriptionsByAuthor[author][len].push(Participant(address(this), type(uint256).max));

            Subscription memory subscription = Subscription({
                hexName: hexName,
                isActive: true,
                isRegularSubscription: isRegularSubscription,
                paymetnPeriod: paymetnPeriod,
                tokenAddress: tokenAddress,
                price: price
            });
            subscriptionsByAuthor[author].push(subscription);

            if (isRegularSubscription) {
                emit NewRegularSubscriptionCreated(author, hexName, tokenAddress, price, paymetnPeriod, discountProgramm);
            } else {
                emit NewOneTimeSubscriptionCreated(author, hexName, tokenAddress, price, discountProgramm);
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
        uint256 periods) public view returns (uint256 amountInToken, uint256 amountInEth){
        Subscription memory subscription = subscriptionsByAuthor[author][subscriptionIndex];
        Discount[] memory discount = discountSubscriptionsByAuthor[author][subscriptionIndex];
        uint256 maxDiscount = 0;
        if (subscription.isRegularSubscription){
            for (uint256 i = 0; i < discount.length; i++){
                if (periods >= discount[i].period && maxDiscount < discount[i].amountAsPPM){
                    maxDiscount = discount[i].amountAsPPM;
                }
            }
        }
        amountInToken = subscription.price.mul(periods).mul(1000 - maxDiscount).div(1000);
        amountInEth = subscription.tokenAddress != address(0) ? amountInToken : mainNFT.converTokenPriceToEth(subscription.tokenAddress, amountInToken);
    }

    function getSubscriptionIndexByHexName(bytes32 hexName) public view returns (uint256[2] memory){
        return subscriptionIndexByHexName[hexName];
    }
    /***************Author options END***************/

    /***************User interfaces BGN***************/
    function subscriptionPayment(uint256 author, uint256 subscriptionIndex, address participantSelectedTokenAddress, uint256 periods) public payable{
        require(!blackListByAuthor[author][msg.sender], "You blacklisted");
        require(periods > 0, "Periods must be greater than zero");
        Subscription memory subscription = subscriptionsByAuthor[author][subscriptionIndex];
        require(subscription.isActive, "Subscription is not active");
        require(mainNFT.converTokenPriceToEth(participantSelectedTokenAddress, 10**24) > 0, "The token is not suitable for payment");
        uint256 thisParticipantIndex = participantIndex[author][subscriptionIndex][msg.sender];
        require(thisParticipantIndex == 0 || subscription.isRegularSubscription, "You already have access to a subscription");
        (uint256 amountInToken, uint256 amountInEth) = getTotalPaymentAmountForPeriod(author, subscriptionIndex, periods);
        if (subscription.tokenAddress == address(0)){
            require(msg.value == amountInToken, "Payment value does not match the price");
            _paymentEth(author, amountInToken);
        } else {
            require(msg.value == 0, "Payment in native coin is not provided for this subscription");
            _swapTokenAndPay(msg.sender, participantSelectedTokenAddress, subscription.tokenAddress, amountInToken, author);
        }

        uint256 subscriptionEndTime = subscription.isRegularSubscription ?
            (block.timestamp).add(subscription.paymetnPeriod.mul(periods)) : type(uint256).max;
        if (thisParticipantIndex != 0){
            subscriptionEndTime = (participantsSubscriptionsByAuthor[author][subscriptionIndex][thisParticipantIndex].subscriptionEndTime)
                .add(subscription.paymetnPeriod.mul(periods));
            participantsSubscriptionsByAuthor[author][subscriptionIndex][thisParticipantIndex].subscriptionEndTime = subscriptionEndTime;
        } else {
            Participant[] storage participants = participantsSubscriptionsByAuthor[author][subscriptionIndex];
            participantIndex[author][subscriptionIndex][msg.sender] = participants.length;
            participants.push(Participant(msg.sender, subscriptionEndTime));
        }
        paymentSubscriptionsByAuthor[author][subscriptionIndex].push(Payment(subscription.tokenAddress, amountInToken, amountInEth, block.timestamp));
        totalPaymentSubscriptionsByAuthoInEth[author][subscriptionIndex] += amountInEth;
        emit NewSubscription(msg.sender, author, subscriptionIndex, subscriptionEndTime, subscription.tokenAddress, amountInToken);
    }

    function _paymentEth(uint256 author, uint256 value) internal nonReentrant {
        uint256 contractFee = mainNFT.contractFeeForAuthor(author, value);
        uint256 amount = value - contractFee;
        (bool success1, ) = owner().call{value: contractFee}("");
        (bool success2, ) = ownerOf(author).call{value: amount}("");
        require(success1 && success2, "fail");
        mainNFT.addAuthorsRating(address(0), value, author);
    }

    function _swapTokenAndPay(address sender, address selectedTokenAddress, address tokenAddress, uint256 tokenAmount, uint256 author) internal {
        uint256 targetAmountInEth = mainNFT.converTokenPriceToEth(selectedTokenAddress, tokenAmount.mul(101).div(100));
        uint256 oneTokenValue = 10**18;
        uint256 basePriceInEth = mainNFT.converTokenPriceToEth(selectedTokenAddress, oneTokenValue);
        require(targetAmountInEth > 0 && basePriceInEth > 0, "Payment fail");
        uint256 baseAmount = (oneTokenValue.mul(101).div(100)).mul(targetAmountInEth).div(basePriceInEth);

        IERC20 token = IERC20(selectedTokenAddress);
        token.transferFrom(sender, address(this), baseAmount);

        address[] memory pathBase = new address[](2);
        pathBase[0] = selectedTokenAddress;
        pathBase[1] = uniswapRouter.WETH();
        uniswapRouter.swapTokensForExactTokens(targetAmountInEth, baseAmount, pathBase, address(this), block.timestamp.add(3600));

        address[] memory pathTarget = new address[](2);
        pathTarget[0] = uniswapRouter.WETH();
        pathTarget[1] = tokenAddress;
        uniswapRouter.swapTokensForExactTokens(tokenAmount, targetAmountInEth, pathTarget, address(this), block.timestamp.add(3600));

        _paymentToken(address(this), tokenAddress, tokenAmount, author);
    }

    function _paymentToken(address sender, address tokenAddress, uint256 tokenAmount, uint256 author) internal nonReentrant {
        IERC20 token = IERC20(tokenAddress);
        uint256 contractFee = mainNFT.contractFeeForAuthor(author, tokenAmount);
        token.transferFrom(sender, owner(), contractFee);
        uint256 amount = tokenAmount - contractFee;
        token.transferFrom(sender, ownerOf(author), amount);
        mainNFT.addAuthorsRating(tokenAddress, tokenAmount, author);
    }
    /***************User interfaces END***************/

    /***************Support BGN***************/
    function _efficientHash(bytes32 a, bytes32 b) private pure returns (bytes32 value) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }

    function owner() public view returns(address){
        return mainNFT.commissionCollector();
    }

    function ownerOf(uint256 author) public view returns (address){
        return mainNFT.ownerOf(author);
    }

    function _setNewRouter(address _uniswapRouterAddress) internal onlyOwner {
        uniswapRouter = IUniswapV2Router02(_uniswapRouterAddress);
    }

    function setIMainNFT(address mainNFTAddress) public onlyOwner{
        mainNFT = IMainNFT(mainNFTAddress);
        mainNFT.setVerfiedContracts(true, address(this));
        _setNewRouter(mainNFT.getUniswapRouterAddress());
    }

    function withdraw() external onlyOwner nonReentrant {
        uint256 amount = address(this).balance;
        (bool success, ) = owner().call{value: amount}("");
        require(success, "fail");
    }

    function withdrawTokens(address _address) external onlyOwner nonReentrant {
        IERC20 token = IERC20(_address);
        uint256 tokenBalance = token.balanceOf(address(this));
        uint256 amount = tokenBalance;
        token.transfer(owner(), amount);
    }
    /***************Support END**************/

    receive() external payable {
        (bool success, ) = owner().call{value: msg.value}("");
        require(success, "fail");
        emit Received(msg.sender, msg.value);
    }
}