// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./AsterToken.sol";
import "./LaunchpadPool.sol";

/**
 * @title TokenFactory
 * @dev Factory contract for creating new tokens and launchpad pools
 * Main entry point for AsterPad platform
 * 
 * Revenue Model:
 * - Creation fee: Configurable (default 0 for launch promo)
 * - Trading fees: 1% on all buys/sells (collected by pools)
 * - Graduation fee: 2% when token graduates to DEX
 * 
 * All fees are sent to the feeRecipient address
 */
contract TokenFactory {
    // Platform settings
    address public owner;
    address public feeRecipient;
    uint256 public creationFee;
    
    // Default bonding curve parameters
    uint256 public defaultBasePrice = 0.00001 ether;  // Starting price
    uint256 public defaultSlope = 0.0000001 ether;    // Price increase rate
    uint256 public defaultGraduationThreshold = 18 ether;  // 18 BNB to graduate
    uint256 public defaultTotalSupply = 1_000_000_000 * 1e18;  // 1 billion tokens
    
    // Token tracking
    address[] public allTokens;
    mapping(address => address) public tokenToPool;
    mapping(address => address[]) public creatorTokens;
    mapping(address => bool) public isAsterToken;
    
    // Categories
    string[] public categories;
    mapping(address => string) public tokenCategory;
    
    // Fee tracking
    uint256 public totalCreationFeesCollected;
    uint256 public totalTradingFeesCollected;
    uint256 public totalGraduationFeesCollected;
    uint256 public totalTokensCreated;
    uint256 public totalTokensGraduated;
    
    // Events
    event TokenCreated(
        address indexed token,
        address indexed pool,
        address indexed creator,
        string name,
        string symbol,
        string category,
        uint256 timestamp
    );
    
    event PoolGraduated(
        address indexed token,
        address indexed pool,
        uint256 bnbRaised,
        uint256 graduationFee,
        uint256 timestamp
    );
    
    event FeeCollected(
        address indexed from,
        uint256 amount,
        string feeType
    );
    
    event FeeRecipientUpdated(
        address indexed oldRecipient,
        address indexed newRecipient
    );
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        // Set fee recipient to AsterPad treasury wallet
        feeRecipient = 0x3717E1A8E2788Ac53D2D5084Dc6FF93d03369D27;
        creationFee = 0;  // FREE for launch promotion
        
        // Initialize default categories
        categories.push("Meme");
        categories.push("DeFi");
        categories.push("Gaming");
        categories.push("NFT");
        categories.push("AI");
        categories.push("Social");
        categories.push("Infrastructure");
        categories.push("Other");
    }
    
    /**
     * @dev Create a new token with launchpad pool
     */
    function createToken(
        string memory name,
        string memory symbol,
        string memory logoURI,
        string memory description,
        string memory category
    ) external payable returns (address tokenAddress, address poolAddress) {
        require(msg.value >= creationFee, "Insufficient creation fee");
        require(bytes(name).length > 0, "Name required");
        require(bytes(symbol).length > 0, "Symbol required");
        require(bytes(symbol).length <= 10, "Symbol too long");
        
        // Deploy pool first
        LaunchpadPool pool = new LaunchpadPool();
        poolAddress = address(pool);
        
        // Deploy token
        AsterToken token = new AsterToken(
            name,
            symbol,
            logoURI,
            description,
            defaultTotalSupply,
            msg.sender,
            poolAddress
        );
        tokenAddress = address(token);
        
        // Initialize pool
        pool.initialize(
            tokenAddress,
            msg.sender,
            defaultBasePrice,
            defaultSlope,
            defaultGraduationThreshold
        );
        
        // Track token
        allTokens.push(tokenAddress);
        tokenToPool[tokenAddress] = poolAddress;
        creatorTokens[msg.sender].push(tokenAddress);
        isAsterToken[tokenAddress] = true;
        tokenCategory[tokenAddress] = category;
        totalTokensCreated++;
        
        // Collect creation fee (if any)
        if (msg.value > 0) {
            totalCreationFeesCollected += msg.value;
            (bool success, ) = feeRecipient.call{value: msg.value}("");
            require(success, "Fee transfer failed");
            emit FeeCollected(msg.sender, msg.value, "creation");
        }
        
        emit TokenCreated(
            tokenAddress,
            poolAddress,
            msg.sender,
            name,
            symbol,
            category,
            block.timestamp
        );
        
        return (tokenAddress, poolAddress);
    }
    
    /**
     * @dev Create token with custom parameters (advanced)
     */
    function createTokenAdvanced(
        string memory name,
        string memory symbol,
        string memory logoURI,
        string memory description,
        string memory category,
        uint256 totalSupply,
        uint256 basePrice,
        uint256 slopeRate,
        uint256 graduationThreshold
    ) external payable returns (address tokenAddress, address poolAddress) {
        require(msg.value >= creationFee, "Insufficient creation fee");
        require(bytes(name).length > 0, "Name required");
        require(bytes(symbol).length > 0, "Symbol required");
        require(totalSupply >= 1_000_000 * 1e18, "Min 1M supply");
        require(graduationThreshold >= 1 ether, "Min 1 BNB threshold");
        
        // Deploy pool first
        LaunchpadPool pool = new LaunchpadPool();
        poolAddress = address(pool);
        
        // Deploy token
        AsterToken token = new AsterToken(
            name,
            symbol,
            logoURI,
            description,
            totalSupply,
            msg.sender,
            poolAddress
        );
        tokenAddress = address(token);
        
        // Initialize pool with custom parameters
        pool.initialize(
            tokenAddress,
            msg.sender,
            basePrice,
            slopeRate,
            graduationThreshold
        );
        
        // Track token
        allTokens.push(tokenAddress);
        tokenToPool[tokenAddress] = poolAddress;
        creatorTokens[msg.sender].push(tokenAddress);
        isAsterToken[tokenAddress] = true;
        tokenCategory[tokenAddress] = category;
        totalTokensCreated++;
        
        // Collect creation fee (if any)
        if (msg.value > 0) {
            totalCreationFeesCollected += msg.value;
            (bool success, ) = feeRecipient.call{value: msg.value}("");
            require(success, "Fee transfer failed");
            emit FeeCollected(msg.sender, msg.value, "creation");
        }
        
        emit TokenCreated(
            tokenAddress,
            poolAddress,
            msg.sender,
            name,
            symbol,
            category,
            block.timestamp
        );
        
        return (tokenAddress, poolAddress);
    }
    
    // View functions
    
    function getAllTokens() external view returns (address[] memory) {
        return allTokens;
    }
    
    function getTokenCount() external view returns (uint256) {
        return allTokens.length;
    }
    
    function getCreatorTokens(address creator) external view returns (address[] memory) {
        return creatorTokens[creator];
    }
    
    function getTokenInfo(address token) external view returns (
        string memory name,
        string memory symbol,
        string memory logoURI,
        string memory description,
        string memory category,
        address pool,
        address creator,
        uint256 createdAt,
        bool graduated
    ) {
        require(isAsterToken[token], "Not an Aster token");
        
        AsterToken t = AsterToken(token);
        LaunchpadPool p = LaunchpadPool(payable(tokenToPool[token]));
        
        return (
            t.name(),
            t.symbol(),
            t.logoURI(),
            t.description(),
            tokenCategory[token],
            tokenToPool[token],
            t.creator(),
            t.createdAt(),
            p.graduated()
        );
    }
    
    function getPoolInfo(address token) external view returns (
        uint256 currentPrice,
        uint256 marketCap,
        uint256 bnbRaised,
        uint256 tokensSold,
        uint256 progress,
        bool graduated
    ) {
        require(isAsterToken[token], "Not an Aster token");
        
        LaunchpadPool pool = LaunchpadPool(payable(tokenToPool[token]));
        
        return (
            pool.getCurrentPrice(),
            pool.getMarketCap(),
            pool.bnbRaised(),
            pool.tokensSold(),
            pool.getProgress(),
            pool.graduated()
        );
    }
    
    function getCategories() external view returns (string[] memory) {
        return categories;
    }
    
    /**
     * @dev Get platform statistics for admin dashboard
     */
    function getPlatformStats() external view returns (
        uint256 tokensCreated,
        uint256 tokensGraduated,
        uint256 creationFees,
        uint256 tradingFees,
        uint256 graduationFees,
        uint256 totalRevenue
    ) {
        return (
            totalTokensCreated,
            totalTokensGraduated,
            totalCreationFeesCollected,
            totalTradingFeesCollected,
            totalGraduationFeesCollected,
            totalCreationFeesCollected + totalTradingFeesCollected + totalGraduationFeesCollected
        );
    }
    
    // Admin functions
    
    function setOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }
    
    function setFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "Invalid address");
        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }
    
    function setCreationFee(uint256 newFee) external onlyOwner {
        require(newFee <= 1 ether, "Fee too high");
        creationFee = newFee;
    }
    
    function setDefaultParameters(
        uint256 basePrice,
        uint256 slopeRate,
        uint256 graduationThreshold,
        uint256 totalSupply
    ) external onlyOwner {
        defaultBasePrice = basePrice;
        defaultSlope = slopeRate;
        defaultGraduationThreshold = graduationThreshold;
        defaultTotalSupply = totalSupply;
    }
    
    function addCategory(string memory category) external onlyOwner {
        categories.push(category);
    }
    
    /**
     * @dev Record graduation (called by pools)
     */
    function recordGraduation(address token, uint256 graduationFee) external {
        require(tokenToPool[token] == msg.sender, "Only pool can record");
        totalTokensGraduated++;
        totalGraduationFeesCollected += graduationFee;
        emit PoolGraduated(token, msg.sender, 0, graduationFee, block.timestamp);
    }
    
    /**
     * @dev Receive BNB (fees from pools)
     * Trading fees and graduation fees are sent here
     */
    receive() external payable {
        // Track trading fees (graduation fees are tracked separately)
        totalTradingFeesCollected += msg.value;
        
        // Forward all fees to fee recipient
        (bool success, ) = feeRecipient.call{value: msg.value}("");
        require(success, "Forward failed");
        
        emit FeeCollected(msg.sender, msg.value, "trading");
    }
}
