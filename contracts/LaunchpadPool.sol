// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./AsterToken.sol";
import "./BondingCurve.sol";

/**
 * @title LaunchpadPool
 * @dev Manages a single token's bonding curve pool
 * Handles buying/selling and graduation to PancakeSwap
 * 
 * Fee Structure:
 * - 1% trading fee on buys and sells
 * - 2% graduation fee when token graduates to DEX
 */
contract LaunchpadPool {
    using BondingCurve for *;
    
    // Pool state
    AsterToken public token;
    address public factory;
    address public creator;
    
    // Bonding curve parameters
    uint256 public basePrice;      // Starting price in wei
    uint256 public slope;          // Price increase rate
    uint256 public tokensSold;     // Tokens sold through bonding curve
    uint256 public bnbRaised;      // Total BNB raised
    
    // Graduation settings
    uint256 public graduationThreshold;  // BNB amount to graduate (e.g., 18 BNB)
    bool public graduated;               // Whether pool has graduated to DEX
    
    // Fees (basis points, 10000 = 100%)
    uint256 public constant PLATFORM_FEE = 100;      // 1% trading fee
    uint256 public constant GRADUATION_FEE = 200;    // 2% graduation fee
    uint256 public constant BASIS_POINTS = 10000;
    
    // Fee tracking
    uint256 public totalFeesCollected;
    uint256 public graduationFeeCollected;
    
    // Trading state
    bool public tradingActive;
    
    // Events
    event TokensBought(
        address indexed buyer,
        uint256 bnbAmount,
        uint256 tokenAmount,
        uint256 fee,
        uint256 newPrice
    );
    
    event TokensSold(
        address indexed seller,
        uint256 tokenAmount,
        uint256 bnbAmount,
        uint256 fee,
        uint256 newPrice
    );
    
    event PoolGraduated(
        address indexed token,
        uint256 bnbLiquidity,
        uint256 tokenLiquidity,
        uint256 graduationFee,
        address dexPair
    );
    
    event FeesCollected(
        address indexed pool,
        uint256 tradingFees,
        uint256 graduationFee
    );
    
    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory");
        _;
    }
    
    modifier whenActive() {
        require(tradingActive && !graduated, "Pool not active");
        _;
    }
    
    constructor() {
        factory = msg.sender;
    }
    
    /**
     * @dev Initialize the pool (called by factory)
     */
    function initialize(
        address token_,
        address creator_,
        uint256 basePrice_,
        uint256 slope_,
        uint256 graduationThreshold_
    ) external onlyFactory {
        token = AsterToken(token_);
        creator = creator_;
        basePrice = basePrice_;
        slope = slope_;
        graduationThreshold = graduationThreshold_;
        tradingActive = true;
    }
    
    /**
     * @dev Buy tokens with BNB
     */
    function buy(uint256 minTokens) external payable whenActive returns (uint256 tokenAmount) {
        require(msg.value > 0, "No BNB sent");
        
        // Calculate platform fee (1%)
        uint256 fee = msg.value * PLATFORM_FEE / BASIS_POINTS;
        uint256 netBnb = msg.value - fee;
        
        // Calculate tokens to receive
        tokenAmount = BondingCurve.calculateTokensForBNB(
            tokensSold,
            netBnb,
            basePrice,
            slope
        );
        
        require(tokenAmount >= minTokens, "Slippage exceeded");
        require(token.balanceOf(address(this)) >= tokenAmount, "Insufficient tokens");
        
        // Update state
        tokensSold += tokenAmount;
        bnbRaised += netBnb;
        totalFeesCollected += fee;
        
        // Transfer tokens to buyer
        token.transfer(msg.sender, tokenAmount);
        
        // Send fee to factory (which forwards to fee recipient)
        (bool feeSuccess, ) = factory.call{value: fee}("");
        require(feeSuccess, "Fee transfer failed");
        
        uint256 newPrice = getCurrentPrice();
        emit TokensBought(msg.sender, msg.value, tokenAmount, fee, newPrice);
        
        // Check for graduation
        if (bnbRaised >= graduationThreshold) {
            _graduate();
        }
        
        return tokenAmount;
    }
    
    /**
     * @dev Sell tokens for BNB
     */
    function sell(uint256 tokenAmount, uint256 minBnb) external whenActive returns (uint256 bnbAmount) {
        require(tokenAmount > 0, "No tokens");
        require(token.balanceOf(msg.sender) >= tokenAmount, "Insufficient tokens");
        
        // Calculate BNB to return
        bnbAmount = BondingCurve.calculateSellReturn(
            tokensSold,
            tokenAmount,
            basePrice,
            slope
        );
        
        // Apply platform fee (1%)
        uint256 fee = bnbAmount * PLATFORM_FEE / BASIS_POINTS;
        uint256 netBnb = bnbAmount - fee;
        
        require(netBnb >= minBnb, "Slippage exceeded");
        require(address(this).balance >= bnbAmount, "Insufficient BNB");
        
        // Update state
        tokensSold -= tokenAmount;
        bnbRaised -= bnbAmount;
        totalFeesCollected += fee;
        
        // Transfer tokens from seller
        token.transferFrom(msg.sender, address(this), tokenAmount);
        
        // Send BNB to seller
        (bool success, ) = msg.sender.call{value: netBnb}("");
        require(success, "BNB transfer failed");
        
        // Send fee to factory
        (bool feeSuccess, ) = factory.call{value: fee}("");
        require(feeSuccess, "Fee transfer failed");
        
        uint256 newPrice = getCurrentPrice();
        emit TokensSold(msg.sender, tokenAmount, netBnb, fee, newPrice);
        
        return netBnb;
    }
    
    /**
     * @dev Graduate pool to PancakeSwap
     * Takes 2% graduation fee from the liquidity
     */
    function _graduate() internal {
        graduated = true;
        tradingActive = false;
        
        // Enable trading on token
        token.enableTrading();
        
        // Get remaining tokens and BNB for liquidity
        uint256 tokenBalance = token.balanceOf(address(this));
        uint256 bnbBalance = address(this).balance;
        
        // Calculate graduation fee (2% of BNB liquidity)
        uint256 gradFee = bnbBalance * GRADUATION_FEE / BASIS_POINTS;
        uint256 liquidityBnb = bnbBalance - gradFee;
        
        graduationFeeCollected = gradFee;
        
        // Send graduation fee to factory
        if (gradFee > 0) {
            (bool feeSuccess, ) = factory.call{value: gradFee}("");
            require(feeSuccess, "Graduation fee transfer failed");
        }
        
        emit PoolGraduated(
            address(token),
            liquidityBnb,
            tokenBalance,
            gradFee,
            address(0) // Would be actual pair address after DEX integration
        );
        
        emit FeesCollected(address(this), totalFeesCollected, gradFee);
        
        // TODO: Integrate with PancakeSwap Router
        // IPancakeRouter router = IPancakeRouter(PANCAKE_ROUTER);
        // router.addLiquidityETH{value: liquidityBnb}(
        //     address(token),
        //     tokenBalance,
        //     0,
        //     0,
        //     address(this), // LP tokens to this contract (then lock)
        //     block.timestamp + 300
        // );
    }
    
    /**
     * @dev Force graduation (factory only, for edge cases)
     */
    function forceGraduate() external onlyFactory {
        require(!graduated, "Already graduated");
        _graduate();
    }
    
    // View functions
    
    function getCurrentPrice() public view returns (uint256) {
        return BondingCurve.getCurrentPrice(tokensSold, basePrice, slope);
    }
    
    function getMarketCap() external view returns (uint256) {
        return BondingCurve.getMarketCap(tokensSold, basePrice, slope);
    }
    
    function getBuyPrice(uint256 amount) external view returns (uint256) {
        uint256 cost = BondingCurve.calculateBuyPrice(tokensSold, amount, basePrice, slope);
        return cost + (cost * PLATFORM_FEE / BASIS_POINTS);
    }
    
    function getSellReturn(uint256 amount) external view returns (uint256) {
        uint256 returnAmt = BondingCurve.calculateSellReturn(tokensSold, amount, basePrice, slope);
        return returnAmt - (returnAmt * PLATFORM_FEE / BASIS_POINTS);
    }
    
    function getProgress() external view returns (uint256) {
        if (graduationThreshold == 0) return 10000;
        return bnbRaised * 10000 / graduationThreshold;
    }
    
    function getTokensRemaining() external view returns (uint256) {
        return token.balanceOf(address(this));
    }
    
    function getTotalFeesCollected() external view returns (uint256 trading, uint256 graduation) {
        return (totalFeesCollected, graduationFeeCollected);
    }
    
    // Receive BNB
    receive() external payable {}
}
