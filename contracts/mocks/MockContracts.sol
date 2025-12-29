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
 * @dev Matches the actual deployed LaunchpadPool interface
 */
contract MockLaunchpadPool {
    // Public state variables (matching actual contract)
    address public token;
    address public creator;
    bool public graduated;
    uint256 public bnbRaised;
    uint256 public tokensSold;
    uint256 public basePrice;
    uint256 public slope;
    uint256 private _currentPrice;
    
    constructor(
        address _token,
        address _creator
    ) {
        token = _token;
        creator = _creator;
        graduated = false;
        bnbRaised = 0;
        tokensSold = 0;
        basePrice = 7142857142; // Default base price
        slope = 400;
        _currentPrice = 10000000000; // 10 gwei per token (example)
    }
    
    function getCurrentPrice() external view returns (uint256) {
        return _currentPrice;
    }
    
    // Test helper functions
    function setCurrentPrice(uint256 price) external {
        _currentPrice = price;
    }
    
    function setBnbRaised(uint256 amount) external {
        bnbRaised = amount;
    }
    
    function setGraduated(bool _graduated) external {
        graduated = _graduated;
    }
    
    function setTokensSold(uint256 amount) external {
        tokensSold = amount;
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
