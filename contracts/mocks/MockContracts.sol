// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MockTokenFactory
 * @notice Mock token factory for testing PredictionMarketV1
 */
contract MockTokenFactory {
    mapping(address => address) public tokenToPool;
    
    function setPool(address token, address pool) external {
        tokenToPool[token] = pool;
    }
}

/**
 * @title MockLaunchpadPool
 * @notice Mock launchpad pool for testing PredictionMarketV1
 */
contract MockLaunchpadPool {
    address public token;
    string public name;
    string public symbol;
    uint256 public totalSupply;
    uint256 public virtualBnb;
    uint256 public virtualTokens;
    bool public graduated;
    address public creator;
    uint256 public totalBnbCollectedValue;
    
    constructor(
        address _token,
        string memory _name,
        string memory _symbol,
        address _creator
    ) {
        token = _token;
        name = _name;
        symbol = _symbol;
        totalSupply = 1_000_000_000 ether;
        virtualBnb = 10 ether;
        virtualTokens = 500_000_000 ether;
        graduated = false;
        creator = _creator;
        totalBnbCollectedValue = 0;
    }
    
    function getTokenInfo() external view returns (
        address,
        string memory,
        string memory,
        uint256,
        uint256,
        uint256,
        bool,
        address
    ) {
        return (
            token,
            name,
            symbol,
            totalSupply,
            virtualBnb,
            virtualTokens,
            graduated,
            creator
        );
    }
    
    function totalBnbCollected() external view returns (uint256) {
        return totalBnbCollectedValue;
    }
    
    // Test helper functions
    function setVirtualBnb(uint256 _virtualBnb) external {
        virtualBnb = _virtualBnb;
    }
    
    function setVirtualTokens(uint256 _virtualTokens) external {
        virtualTokens = _virtualTokens;
    }
    
    function setGraduated(bool _graduated) external {
        graduated = _graduated;
    }
    
    function setTotalBnbCollected(uint256 _amount) external {
        totalBnbCollectedValue = _amount;
    }
}

/**
 * @title MockChainlinkOracle
 * @notice Mock Chainlink price feed for testing
 */
contract MockChainlinkOracle {
    int256 public price;
    uint256 public updatedAt;
    uint80 public roundId;
    
    constructor(int256 _price) {
        price = _price;
        updatedAt = block.timestamp;
        roundId = 1;
    }
    
    function latestRoundData() external view returns (
        uint80,
        int256,
        uint256,
        uint256,
        uint80
    ) {
        return (
            roundId,
            price,
            block.timestamp,
            updatedAt,
            roundId
        );
    }
    
    function setPrice(int256 _price) external {
        price = _price;
        updatedAt = block.timestamp;
        roundId++;
    }
    
    function setStalePrice(int256 _price, uint256 _updatedAt) external {
        price = _price;
        updatedAt = _updatedAt;
        roundId++;
    }
}

/**
 * @title MockToken
 * @notice Simple mock ERC20 token for testing
 */
contract MockToken {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    
    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }
}
