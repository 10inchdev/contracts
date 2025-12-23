// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/**
 * @title MockPancakeRouter
 * @notice Mock PancakeSwap router for testing
 */
contract MockPancakeRouter {
    address public immutable WETH;
    address public factory;
    
    // Exchange rate: 1 BNB = 1000 tokens (for testing)
    uint256 public constant EXCHANGE_RATE = 1000;
    
    constructor(address _weth) {
        WETH = _weth;
        factory = address(this); // Mock factory
    }
    
    /**
     * @notice Swap BNB for tokens
     */
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable {
        require(deadline >= block.timestamp, "Deadline expired");
        require(path.length >= 2, "Invalid path");
        require(path[0] == WETH, "First token must be WETH");
        
        address tokenOut = path[path.length - 1];
        uint256 amountOut = msg.value * EXCHANGE_RATE;
        
        require(amountOut >= amountOutMin, "Insufficient output amount");
        
        // Transfer tokens to recipient
        IERC20(tokenOut).transfer(to, amountOut);
    }
    
    /**
     * @notice Swap tokens for BNB
     */
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external {
        require(deadline >= block.timestamp, "Deadline expired");
        require(path.length >= 2, "Invalid path");
        require(path[path.length - 1] == WETH, "Last token must be WETH");
        
        address tokenIn = path[0];
        uint256 amountOut = amountIn / EXCHANGE_RATE;
        
        require(amountOut >= amountOutMin, "Insufficient output amount");
        
        // Transfer tokens from sender
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        
        // Send BNB to recipient
        (bool success, ) = payable(to).call{value: amountOut}("");
        require(success, "BNB transfer failed");
    }
    
    /**
     * @notice Get amounts out for a swap
     */
    function getAmountsOut(
        uint256 amountIn, 
        address[] calldata path
    ) external pure returns (uint256[] memory amounts) {
        require(path.length >= 2, "Invalid path");
        
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        
        // Simple mock: apply exchange rate
        for (uint256 i = 1; i < path.length; i++) {
            amounts[i] = amounts[i - 1] * EXCHANGE_RATE;
        }
    }
    
    /**
     * @notice Add liquidity with ETH
     */
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        require(deadline >= block.timestamp, "Deadline expired");
        
        amountToken = amountTokenDesired;
        amountETH = msg.value;
        liquidity = amountToken + amountETH;
        
        // Transfer tokens from sender
        IERC20(token).transferFrom(msg.sender, address(this), amountToken);
    }
    
    // Receive BNB
    receive() external payable {}
}

