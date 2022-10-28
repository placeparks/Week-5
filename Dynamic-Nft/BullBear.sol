// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

import "hardhat/console.sol";

contract BullBear is
    ERC721,
    ERC721Enumerable,
    ERC721URIStorage,
    Ownable,
    AutomationCompatibleInterface,
    VRFConsumerBaseV2
{
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;
    AggregatorV3Interface public pricefeed;
    VRFCoordinatorV2Interface public COORDINATOR;

    uint[] public s_randomWords;
    uint public s_requestId;
    uint32 public callbackGasLimit = 500000;
    uint64 public s_subscriptionId;
    bytes32 keyhash =
       0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f ; //I used Polygon-Mumbai testnet...

    uint public interval;
    uint public lastTimeStamp;

    int public currentPrice;

    enum MarketTrend {
        BULL,
        BEAR
    }
    MarketTrend public currentMarketTrend = MarketTrend.BULL;

    string[] bullUrisIpfs = [
        "https://ipfs.io/ipfs/QmS1v9jRYvgikKQD6RrssSKiBTBH3szDK6wzRWF4QBvunR?filename=gamer_bull.json",
        "https://ipfs.io/ipfs/QmRsTqwTXXkV8rFAT4XsNPDkdZs5WxUx9E5KwFaVfYWjMv?filename=party_bull.json",
        "https://ipfs.io/ipfs/Qmc3ueexsATjqwpSVJNxmdf2hStWuhSByHtHK5fyJ3R2xb?filename=simple_bull.json"
    ];
    string[] bearUrisIpfs = [
        "https://ipfs.io/ipfs/QmQMqVUHjCAxeFNE9eUxf89H1b7LpdzhvQZ8TXnj4FPuX1?filename=beanie_bear.json",
        "https://ipfs.io/ipfs/QmP2v34MVdoxLSFj1LbGW261fvLcoAsnJWHaBK238hWnHJ?filename=coolio_bear.json",
        "https://ipfs.io/ipfs/QmZVfjuDiUfvxPM7qAvq8Umk3eHyVh7YTbFon973srwFMD?filename=simple_bear.json"
    ];

    event TokensUpdate(string marketTrend);

    constructor(
        uint updateInterval,
        address _priceFeed,
        address _vrfCoordinator
    ) ERC721("Bull&Bear", "BBTK") VRFConsumerBaseV2(_vrfCoordinator) {
        interval = updateInterval;
        lastTimeStamp = block.timestamp;

        pricefeed = AggregatorV3Interface(_priceFeed);

        currentPrice = getLatestPrice();
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
    }

    function getLatestPrice() public view returns (int) {
        (,int price,,,) = pricefeed.latestRoundData();
        return price;
    }

    function safeMint(address to) public {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();

        _safeMint(to, tokenId);

        string memory uri = bullUrisIpfs[0];

        _setTokenURI(tokenId, uri);

        console.log(
            "DONE!!! minted token ",
            tokenId,
            " and assigned token url: ",
            uri
        );
    }

    function checkUpkeep(bytes calldata)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory)
    {
        upkeepNeeded = (block.timestamp - lastTimeStamp) > interval;
    }

    function requestRandomnessForNFTUris() internal {
        require(s_subscriptionId != 0, "Subscription ID not set");
        s_requestId = COORDINATOR.requestRandomWords(
            keyhash,
            s_subscriptionId,
            3,
            callbackGasLimit,
            1
        );
        console.log("Request ID: ", s_requestId);
    }

    function performUpkeep(bytes calldata) external override {
        if ((block.timestamp - lastTimeStamp) > interval) {
            lastTimeStamp = block.timestamp;
            int latestPrice = getLatestPrice();

            if (latestPrice == currentPrice) {
                console.log("NO CHANGE => Returning!");
                return;
            }

            if (latestPrice < currentPrice) {
                currentMarketTrend = MarketTrend.BEAR;
            } else {
                currentMarketTrend = MarketTrend.BULL;
            }
            requestRandomnessForNFTUris();
            currentPrice = latestPrice;
        } else {
            console.log("INTERVAL NOT UP!");
            return;
        }
    }

    function fulfillRandomWords(uint, uint256[] memory randomWords)
        internal
        override
    {
        s_randomWords = randomWords;
        console.log("...Fullfilling random words");

        string[] memory urisForTrend = currentMarketTrend == MarketTrend.BULL
            ? bullUrisIpfs
            : bearUrisIpfs;
        uint idx = randomWords[0] % urisForTrend.length;

        for (uint i = 0; i < _tokenIdCounter.current(); i++) {
            _setTokenURI(i, urisForTrend[idx]);
        }

        string memory trend = currentMarketTrend == MarketTrend.BULL
            ? "bull"
            : "bear";

        emit TokensUpdate(trend);
    }

    function setPriceFeed(address newFeed) public onlyOwner {
        pricefeed = AggregatorV3Interface(newFeed);
    }

    function setInterval(uint256 newInterval) public onlyOwner {
        interval = newInterval;
    }

    function setSubscriptionId(uint64 _id) public onlyOwner {
        s_subscriptionId = _id;
    }

    function setCallbackGasLimit(uint32 maxGas) public onlyOwner {
        callbackGasLimit = maxGas;
    }

    function setVrfCoodinator(address _address) public onlyOwner {
        COORDINATOR = VRFCoordinatorV2Interface(_address);
    }

    function compareStrings(string memory a, string memory b)
        internal
        pure
        returns (bool)
    {
        return (keccak256(abi.encodePacked(a)) ==
            keccak256(abi.encodePacked(b)));
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(uint256 tokenId)
        internal
        override(ERC721, ERC721URIStorage)
    {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
