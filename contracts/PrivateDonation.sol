// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface IPublicDonation {
    function donateEth(uint256 author) external payable;
    function owner() external view returns (address);
    function ownerOf(uint256) external view returns (address);
}

interface IVerifierZK {
    struct G1Point {
        uint X;
        uint Y;
    }
    
    struct G2Point {
        uint[2] X;
        uint[2] Y;
    }

    struct Proof {
        G1Point a;
        G2Point b;
        G1Point c;
    }
    function verifyTx(Proof memory proof, uint[64] memory input) external view returns (bool r);
}

contract PrivateDonation {
    using SafeMath for uint256;
    
    uint16 minCountToGetDonation;
    address publicDonationAddress;
    address verifierProvider;
    address verifierZkAddress;
    uint256 donationValue;
    uint256 public donationFee;
    uint256 blockedForWithdraw;
    mapping(bytes32 => bool) isClosed;
    mapping(bytes32 => uint256) hashIndex;
    mapping(uint256 => bool) tokenClosing;
    bytes32[] public hashes;

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "Donation: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    bool isActive;
    modifier onlyActive() {
        require(isActive, "Donation: NOT ACTIVE");
        _;
    }

    modifier onlyOwner() {
        require(owner() == msg.sender, "Only owner");
        _;
    }

    modifier onlyVerifierProvider(){
        require(verifierProvider == msg.sender, "Only verifier provider");
        _;
    }

    event Received(address indexed sender, uint256 value);

    constructor(address _publicDonationAddress, address _verifierProvider, address _verifierZkAddress, uint256 _donationValue, uint256 _donationFee) {
        isActive = true;
        pushNewHash(0);
        setPublicDonation(_publicDonationAddress);
        setVerifierProvider(_verifierProvider);
        setVerifierZkAddress(_verifierZkAddress);
        setDonationValue(_donationValue);
        setDonationFee(_donationFee);
        setMinCountToGetDonation(5);
    }

    function setDonationValue(uint256 _donationValue) public onlyOwner{
        require(_donationValue >= 10**6, "Low value");
        require(address(this).balance == 0, "Contract has unclosed donations");
        donationValue = _donationValue;
    }

    function setDonationFee(uint256 _donationFee) public onlyOwner{
        require(_donationFee < 10000, "Fee too high");
        donationFee = _donationFee;
    }

    function setActivation(bool newStatus) public onlyOwner{
        require(isActive != newStatus, "Value does not match the expectation");
        isActive = newStatus;
    }

    function setVerifierProvider(address _verifierProvider) public onlyOwner{
        verifierProvider = _verifierProvider;
    }
    
    function setVerifierZkAddress(address _verifierZkAddress) public onlyOwner{
        verifierZkAddress = _verifierZkAddress;
    }

    function setPublicDonation(address _address) public onlyOwner {
        require(address(this).balance == 0, "Contract has unclosed donations");
        publicDonationAddress = _address;
    }

    function setMinCountToGetDonation(uint16 _value) public onlyOwner{
        minCountToGetDonation = _value;
    }

    function pushNewHash(bytes32 hash) private {
        hashIndex[hash] = hashes.length;
        hashes.push(hash);
    }

    function getDonationValue() public view returns(uint256){
        return donationValue + donationValue.mul(donationFee).div(10000);
    }

    function _hashUsed(bytes32 hash) private view returns(bool) {
        return hashIndex[hash] != 0;
    }

    function getPublicHash(bytes32 privateHash) public view returns(bytes32 profHash, bytes32 lastProfHash, uint256 nonce) {
        profHash = privateHash;
        for(nonce = 0; nonce < hashes.length; nonce++){
            lastProfHash = profHash;
            profHash = _efficientHash(profHash, bytes32(nonce));
            if (!isClosed[lastProfHash]){
                lastProfHash = hashes[0];
            }
            if (!_hashUsed(profHash)){
                break;
            }
        }
    }

    function sendPrivateDonation(bytes32 publicHash) public onlyActive lock payable {
        require(!isClosed[publicHash], "This donation is closed");
        require(msg.value == getDonationValue(), "Value is incorrect");
        require(!_hashUsed(publicHash), "Hash was used, try next time");
        uint256 feeValue = donationValue.mul(donationFee).div(10000);
        (bool success, ) = IPublicDonation(publicDonationAddress).owner().call{value: feeValue}("");
        require(success, "fail");
        pushNewHash(publicHash);
        blockedForWithdraw += donationValue;
    }

    function receiveDonation(bytes32 publicHash, uint256 tokenId, uint256 count, uint256 gasFee) public onlyVerifierProvider lock {
        require(!_hashUsed(publicHash), "Hash was used, try next time");
        require(count >= minCountToGetDonation, "not enough");
        pushNewHash(publicHash);
        isClosed[publicHash] = true;
        (bool successFee, ) = verifierProvider.call{value: gasFee}("");
        require(successFee, "fail");
        uint256 amount = count.mul(donationValue);
        IPublicDonation(publicDonationAddress).donateEth{value: amount.sub(gasFee)}(tokenId);
        blockedForWithdraw -= amount;
    }

    function closeSessionByAuthor(bytes32 publicHash, uint256 tokenId, uint256 count, IVerifierZK.Proof memory proof) public lock {
        require(publicHash != hashes[0], "Hash error");
        require(!isClosed[publicHash] && !tokenClosing[tokenId], "This donation is closed");
        require(!_hashUsed(publicHash), "Hash was used, try next time");
        require(IPublicDonation(publicDonationAddress).ownerOf(tokenId) == msg.sender, "You not owner");
        require(count > minCountToGetDonation, "not enough");

        IVerifierZK verifierZK = IVerifierZK(verifierZkAddress);
        require(verifierZK.verifyTx(proof, _bytes32ToUintArray(publicHash, _convertUintToBytes32(count))), "Prof of public hash is not valid");

        pushNewHash(publicHash);
        isClosed[publicHash] = true;
        tokenClosing[tokenId] = true;
    }

    function receiveDonationByZK(bytes32 publicHash, bytes32 lastPublicHash, uint256 tokenId, uint256 count, IVerifierZK.Proof memory proof) public lock {
        require(!isClosed[publicHash], "Public Hash was used");
        require(isClosed[lastPublicHash] && tokenClosing[tokenId], "Please close session by Author before");
        require(_hashUsed(lastPublicHash), "Hash not found");
        require(count > minCountToGetDonation, "not enough");

        IVerifierZK verifierZK = IVerifierZK(verifierZkAddress);
        require(verifierZK.verifyTx(proof, _bytes32ToUintArray(lastPublicHash, _convertUintToBytes32(count.sub(1)))), "Prof of last public hash is not valid");
        require(verifierZK.verifyTx(proof, _bytes32ToUintArray(publicHash, _convertUintToBytes32(count))), "Prof of public hash is not valid");

        isClosed[publicHash] = true;
        tokenClosing[tokenId] = false;
        
        uint256 amount = (count.sub(1)).mul(donationValue);
        IPublicDonation(publicDonationAddress).donateEth{value: amount}(tokenId);
        blockedForWithdraw -= amount;
    }
    
    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return a < b ? _efficientHash(a, b) : _efficientHash(b, a);
    }

    function _efficientHash(bytes32 a, bytes32 b) private pure returns (bytes32 value) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }

    function _bytes32ToUintArray(bytes32 a, bytes32 b) private pure returns (uint[64] memory result) {
        bytes memory aBytes = abi.encodePacked(a);
        bytes memory bBytes = abi.encodePacked(b);
        require(aBytes.length == 32, "Invalid input length for a");
        require(bBytes.length == 32, "Invalid input length for b");
        assembly {
            let offset := 32
            let index := 0
            mstore(add(result, offset), mload(add(aBytes, 32)))
            for { } lt(index, 32) { index := add(index, 1) } {
                offset := add(offset, 1)
                mstore(add(result, offset), byte(index, mload(add(aBytes, 32))))
            }
            offset := 64
            index := 0
            mstore(add(result, offset), mload(add(bBytes, 32)))
            for { } lt(index, 32) { index := add(index, 1) } {
                offset := add(offset, 1)
                mstore(add(result, offset), byte(index, mload(add(bBytes, 32))))
            }
        }
    }

    function _convertUintToBytes32(uint256 value) private pure returns (bytes32 result) {
        assembly {
            result := mload(0x0)
            mstore(result, value)
        }
    }

    function owner() public view returns(address){
        return IPublicDonation(publicDonationAddress).owner();
    }

    function withdraw() external onlyOwner lock {
        require(address(this).balance > blockedForWithdraw, "not enough");
        uint256 amount = address(this).balance - blockedForWithdraw;
        (bool success, ) = IPublicDonation(publicDonationAddress).owner().call{value: amount}("");
        require(success, "fail");
    }

    function withdrawTokens(address _address) external onlyOwner lock {
        IERC20 token = IERC20(_address);
        uint256 tokenBalance = token.balanceOf(address(this));
        token.transfer(IPublicDonation(publicDonationAddress).owner(), tokenBalance);
    }

    receive() external payable {
        (bool success, ) = IPublicDonation(publicDonationAddress).owner().call{value: msg.value}("");
        require(success, "fail");
        emit Received(msg.sender, msg.value);
    }
}