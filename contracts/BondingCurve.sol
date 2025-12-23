// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title BondingCurve
 * @dev Library for bonding curve calculations
 * Uses a linear bonding curve: price = basePrice + (supply * slope)
 * This creates a fair launch mechanism where early buyers get lower prices
 */
library BondingCurve {
    uint256 constant PRECISION = 1e18;
    
    /**
     * @dev Calculate the price for buying tokens
     * @param currentSupply Current supply of tokens sold
     * @param amount Amount of tokens to buy
     * @param basePrice Starting price in wei
     * @param slope Price increase per token
     * @return cost Total cost in BNB (wei)
     */
    function calculateBuyPrice(
        uint256 currentSupply,
        uint256 amount,
        uint256 basePrice,
        uint256 slope
    ) internal pure returns (uint256 cost) {
        // Integral of linear function: area under curve
        // Cost = basePrice * amount + slope * (currentSupply * amount + amount^2 / 2)
        uint256 startArea = basePrice * amount / PRECISION;
        uint256 slopeArea = slope * (
            (currentSupply * amount) + (amount * amount / 2)
        ) / PRECISION / PRECISION;
        
        cost = startArea + slopeArea;
    }
    
    /**
     * @dev Calculate the return for selling tokens
     * @param currentSupply Current supply of tokens sold
     * @param amount Amount of tokens to sell
     * @param basePrice Starting price in wei
     * @param slope Price increase per token
     * @return returnAmount Amount of BNB returned (wei)
     */
    function calculateSellReturn(
        uint256 currentSupply,
        uint256 amount,
        uint256 basePrice,
        uint256 slope
    ) internal pure returns (uint256 returnAmount) {
        require(currentSupply >= amount, "Insufficient supply");
        
        uint256 newSupply = currentSupply - amount;
        
        // Calculate area under curve between newSupply and currentSupply
        uint256 startArea = basePrice * amount / PRECISION;
        uint256 slopeArea = slope * (
            (newSupply * amount) + (amount * amount / 2)
        ) / PRECISION / PRECISION;
        
        returnAmount = startArea + slopeArea;
    }
    
    /**
     * @dev Calculate current token price
     * @param currentSupply Current supply of tokens sold
     * @param basePrice Starting price in wei
     * @param slope Price increase per token
     * @return price Current price per token in wei
     */
    function getCurrentPrice(
        uint256 currentSupply,
        uint256 basePrice,
        uint256 slope
    ) internal pure returns (uint256 price) {
        price = basePrice + (slope * currentSupply / PRECISION);
    }
    
    /**
     * @dev Calculate market cap
     * @param currentSupply Current supply of tokens sold
     * @param basePrice Starting price in wei
     * @param slope Price increase per token
     * @return marketCap Current market cap in wei
     */
    function getMarketCap(
        uint256 currentSupply,
        uint256 basePrice,
        uint256 slope
    ) internal pure returns (uint256 marketCap) {
        uint256 currentPrice = getCurrentPrice(currentSupply, basePrice, slope);
        marketCap = currentPrice * currentSupply / PRECISION;
    }
    
    /**
     * @dev Calculate tokens received for a given BNB amount
     * @param currentSupply Current supply of tokens sold
     * @param bnbAmount Amount of BNB to spend
     * @param basePrice Starting price in wei
     * @param slope Price increase per token
     * @return tokenAmount Amount of tokens received
     */
    function calculateTokensForBNB(
        uint256 currentSupply,
        uint256 bnbAmount,
        uint256 basePrice,
        uint256 slope
    ) internal pure returns (uint256 tokenAmount) {
        // Solve quadratic equation: slope/2 * x^2 + (basePrice + slope*currentSupply) * x - bnbAmount = 0
        // Using quadratic formula: x = (-b + sqrt(b^2 + 4ac)) / 2a
        // where a = slope/2, b = basePrice + slope*currentSupply, c = bnbAmount
        
        if (slope == 0) {
            // Linear case: tokens = bnbAmount / basePrice
            return bnbAmount * PRECISION / basePrice;
        }
        
        uint256 a = slope / 2;
        uint256 b = basePrice + (slope * currentSupply / PRECISION);
        uint256 c = bnbAmount * PRECISION;
        
        // Discriminant: b^2 + 4ac (note: we use + because c is positive in our equation)
        uint256 discriminant = (b * b) + (4 * a * c / PRECISION);
        
        // sqrt approximation using Newton's method
        uint256 sqrtDiscriminant = sqrt(discriminant);
        
        // x = (-b + sqrt(discriminant)) / (2a)
        // Since b is always positive and sqrt > b, we get positive result
        tokenAmount = (sqrtDiscriminant - b) * PRECISION / (2 * a);
    }
    
    /**
     * @dev Square root using Newton's method
     */
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}






