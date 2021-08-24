// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract TestNFT is ERC721URIStorage, Ownable {
    using SafeMath for uint256;
    using Address for address;

    address public feeAddress;
    uint256 public feePercent = 3;

    mapping(uint256 => uint256) public price;
    mapping(uint256 => bool) public listedMap;

    uint256 private mintIndex = 0;

    IERC20 public paymentToken;

    struct BidEntity{
        uint256 tokenId;
        address buyer;
        uint256 price;
    }

    mapping (uint256=>BidEntity[]) public bidArrayOfToken;
    mapping (uint256=>mapping(address=>bool)) public bidStatusOfToken;

    event Purchase(address indexed previousOwner, address indexed newOwner, uint256 price, uint256 nftID, string uri);
    event Minted(address indexed minter, uint256 price, uint256 nftID, string uri);
    event PriceUpdate(address indexed owner, uint256 oldPrice, uint256 newPrice, uint256 nftID);
    event NftListStatus(address indexed owner, uint256 nftID, bool isListed);
    event Burned(uint256 nftID);
    event BidCreate(address indexed buyer, uint nftID, uint price);
    event BidCancel(address indexed buyer, uint nftID);
    event Sell(address indexed previousOwner, address indexed newOwner, uint256 price, uint256 nftID, string uri);

    modifier _validateBuy(uint256 _id) {
        require(_exists(_id), "Error, wrong tokenId");
        require(listedMap[_id], "Item not listed currently");
        require(msg.value >= price[_id], "Error, the amount is lower");
        require(_msgSender() != ownerOf(_id), "Can not buy what you own");
        _;
    }

    modifier _validateBid(uint256 _id, uint256 _price) {
        require(_exists(_id), "Error, wrong tokenId");
        require(listedMap[_id], "Item not listed currently");
        require(_price > 0, "Error, the amount is lower than 0");
        require(_msgSender() != ownerOf(_id), "Can not bid what you own");
        require(bidStatusOfToken[_id][_msgSender()] == false, "Can not several bid");
        _;
    }

    modifier _validateCancelBid(uint256 _id) {
        require(_exists(_id), "Error, wrong tokenId");
        require(listedMap[_id], "Item not listed currently");
        require(_msgSender() != ownerOf(_id), "Can not cancel bid what you own");
        require(bidStatusOfToken[_id][_msgSender()] == true, "You never bidded");
        _;
    }

    modifier _validateSell(uint256 _id, address _buyer) {
        require(_exists(_id), "Error, wrong tokenId");
        require(listedMap[_id], "Item not listed currently");
        require(_msgSender() == ownerOf(_id), "Only owner can sell");
        require(bidStatusOfToken[_id][_buyer] == true, "Can sell to only bidder");

        uint256 _bidPrice = getPriceOfBid(_id, _buyer);
        require(_bidPrice <= paymentToken.allowance(_buyer, address(this)), "Error, the allowance amount is lower");
        require(_bidPrice <= paymentToken.balanceOf(_buyer), "Error, the balance is lower");
        _;
    }

    modifier _validateOwnerOfToken(uint256 _id) {
        require(_exists(_id), "Error, wrong tokenId");
        require(_msgSender() == ownerOf(_id), "Only Owner Can Burn");
        _;
    }

    constructor(string memory _name, string memory _symbol, address _paymentToken) ERC721(_name, _symbol) {
        feeAddress = _msgSender();
        paymentToken = IERC20(_paymentToken);
    }

    function setFee(address _feeAddress, uint256 _feePercent) external onlyOwner {
        feeAddress = _feeAddress;
        feePercent = _feePercent;
    }

    function mint(string memory _tokenURI, uint256 _price) external returns (uint256) {
        mintIndex = mintIndex.add(1);
        uint256 _tokenId = mintIndex;
        price[_tokenId] = _price;
        listedMap[_tokenId] = true;

        _safeMint(_msgSender(), _tokenId);
        _setTokenURI(_tokenId, _tokenURI);

        emit Minted(_msgSender(), _price, _tokenId, _tokenURI);

        return _tokenId;
    }

    function burn(uint256 _id) external _validateOwnerOfToken(_id) {
        _burn(_id);
        delete price[_id];
        delete listedMap[_id];

        // Remove all Bid List
        for(uint256 i = 0; i < bidArrayOfToken[_id].length; i++)
        {
            bidStatusOfToken[_id][bidArrayOfToken[_id][i].buyer] = false;
        }
        delete bidArrayOfToken[_id];
        
        emit Burned(_id);
    }

    function buy(uint256 _id) external payable _validateBuy(_id) {
        address _previousOwner = ownerOf(_id);
        address _newOwner = _msgSender();

        address payable _buyer = payable(_newOwner);
        address payable _owner = payable(_previousOwner);

        _transfer(_owner, _buyer, _id);

        uint256 _commissionValue = price[_id].div(10**2).mul(feePercent);
        uint256 _sellerValue = price[_id].sub(_commissionValue);

        _owner.transfer(_sellerValue);
        payable(feeAddress).transfer(_commissionValue);

        // If buyer sent more than price, we send them back their rest of funds
        if (msg.value > price[_id]) {
            _buyer.transfer(msg.value.sub(price[_id]));
        }

        listedMap[_id] = false;

        // Remove all Bid List
        for(uint256 i = 0; i < bidArrayOfToken[_id].length; i++)
        {
            bidStatusOfToken[_id][bidArrayOfToken[_id][i].buyer] = false;
        }
        delete bidArrayOfToken[_id];

        emit Purchase(_previousOwner, _newOwner, price[_id], _id, tokenURI(_id));
    }

    function bid(uint256 _id, uint256 _price) external _validateBid(_id, _price){
        BidEntity memory newBidEntity = BidEntity(_id, _msgSender(), _price);
        bidArrayOfToken[_id].push(newBidEntity);
        bidStatusOfToken[_id][_msgSender()] = true;

        emit BidCreate(_msgSender(), _id, _price);
    }

    function cancelBid(uint256 _id) external _validateCancelBid(_id){
        for(uint256 i = 0; i < bidArrayOfToken[_id].length; i++)
        {
            if (bidArrayOfToken[_id][i].buyer == _msgSender())
            {
                bidArrayOfToken[_id][i] = bidArrayOfToken[_id][bidArrayOfToken[_id].length - 1];
                bidArrayOfToken[_id].pop();
                break;
            }
        }
        bidStatusOfToken[_id][_msgSender()] = false;

        emit BidCancel(_msgSender(), _id);
    }

    function sell(uint256 _id, address _buyer) external _validateSell(_id, _buyer){
        address _owner = ownerOf(_id);

        _transfer(_owner, _buyer, _id);

        uint256 _price = getPriceOfBid(_id, _buyer);
        uint256 _commissionValue = _price.div(10**2).mul(feePercent);
        uint256 _sellerValue = _price.sub(_commissionValue);

        paymentToken.transferFrom(_buyer, feeAddress, _commissionValue);
        paymentToken.transferFrom(_buyer, _owner, _sellerValue);

        listedMap[_id] = false;

        // Remove all Bid List
        for(uint256 i = 0; i < bidArrayOfToken[_id].length; i++)
        {
            bidStatusOfToken[_id][bidArrayOfToken[_id][i].buyer] = false;
        }
        delete bidArrayOfToken[_id];

        emit Sell(_owner, _buyer, _price, _id, tokenURI(_id));
    }

    function updatePrice(uint256 _tokenId, uint256 _price) external _validateOwnerOfToken(_tokenId){
        uint256 oldPrice = price[_tokenId];
        price[_tokenId] = _price;

        emit PriceUpdate(_msgSender(), oldPrice, _price, _tokenId);
    }

    function updateListingStatus(uint256 _tokenId, bool shouldBeListed) external _validateOwnerOfToken(_tokenId){
        listedMap[_tokenId] = shouldBeListed;

        emit NftListStatus(_msgSender(), _tokenId, shouldBeListed);
    }

    function getPriceOfBid(uint256 _id, address _buyer) internal view returns(uint256){
        for(uint256 i = 0; i < bidArrayOfToken[_id].length; i++)
        {
            if (bidArrayOfToken[_id][i].buyer == _buyer)
            {
                return bidArrayOfToken[_id][i].price;
            }
        }
        return 0;
    }
}