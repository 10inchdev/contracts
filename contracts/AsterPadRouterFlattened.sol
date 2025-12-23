// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title AsterPadRouter (Flattened for Remix Deployment)
 * @notice Custom trading router for AsterPad graduated tokens
 * @dev Routes trades through PancakeSwap while extracting perpetual fees
 * 
 * Fee Structure:
 * - Platform Fee: 1.0% (goes to treasury)
 * - Creator Fee: 0.5% (goes to token creator - perpetual)
 * - Total: 1.5% on all trades
 * 
 * After tokens graduate from the bonding curve to PancakeSwap, trades go through
 * this router to maintain perpetual fee collection for creators and the platform.
 * 
 * Security: OpenZeppelin ReentrancyGuard, Pausable, Ownable2Step
 */

// =============================================================================
// OPENZEPPELIN CONTRACTS (Flattened from v5.0)
// =============================================================================

/**
 * @dev Provides information about the current execution context.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

/**
 * @dev Contract module which provides a basic access control mechanism.
 */
abstract contract Ownable is Context {
    address private _owner;

    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

/**
 * @dev Contract module which provides access control with a two-step transfer.
 */
abstract contract Ownable2Step is Ownable {
    address private _pendingOwner;

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    function pendingOwner() public view virtual returns (address) {
        return _pendingOwner;
    }

    function transferOwnership(address newOwner) public virtual override onlyOwner {
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner(), newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual override {
        delete _pendingOwner;
        super._transferOwnership(newOwner);
    }

    function acceptOwnership() public virtual {
        address sender = _msgSender();
        if (pendingOwner() != sender) {
            revert OwnableUnauthorizedAccount(sender);
        }
        _transferOwnership(sender);
    }
}

/**
 * @dev Contract module which allows children to implement an emergency stop.
 */
abstract contract Pausable is Context {
    bool private _paused;

    event Paused(address account);
    event Unpaused(address account);

    error EnforcedPause();
    error ExpectedPause();

    constructor() {
        _paused = false;
    }

    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    modifier whenPaused() {
        _requirePaused();
        _;
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    function _requireNotPaused() internal view virtual {
        if (paused()) {
            revert EnforcedPause();
        }
    }

    function _requirePaused() internal view virtual {
        if (!paused()) {
            revert ExpectedPause();
        }
    }

    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}

/**
 * @dev Contract module that helps prevent reentrant calls.
 */
abstract contract ReentrancyGuard {
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    uint256 private _status;

    error ReentrancyGuardReentrantCall();

    constructor() {
        _status = NOT_ENTERED;
    }

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        if (_status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }
        _status = ENTERED;
    }

    function _nonReentrantAfter() private {
        _status = NOT_ENTERED;
    }

    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == ENTERED;
    }
}

// =============================================================================
// INTERFACES
// =============================================================================

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IPancakeRouter02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;
    
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
    
    function getAmountsOut(uint256 amountIn, address[] calldata path) 
        external view returns (uint256[] memory amounts);
}

// =============================================================================
// SAFE ERC20 LIBRARY
// =============================================================================

library SafeERC20 {
    error SafeERC20FailedOperation(address token);

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transfer, (to, value)));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transferFrom, (from, to, value)));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 oldAllowance = token.allowance(address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    function forceApprove(IERC20 token, address spender, uint256 value) internal {
        bytes memory approvalCall = abi.encodeCall(token.approve, (spender, value));

        if (!_callOptionalReturnBool(token, approvalCall)) {
            _callOptionalReturn(token, abi.encodeCall(token.approve, (spender, 0)));
            _callOptionalReturn(token, approvalCall);
        }
    }

    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        uint256 returnSize;
        uint256 returnValue;
        assembly ("memory-safe") {
            let success := call(gas(), token, 0, add(data, 0x20), mload(data), 0, 0x20)
            if iszero(success) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0, returndatasize())
                revert(ptr, returndatasize())
            }
            returnSize := returndatasize()
            returnValue := mload(0)
        }

        if (returnSize != 0 && returnValue == 0) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    function _callOptionalReturnBool(IERC20 token, bytes memory data) private returns (bool) {
        bool success;
        uint256 returnSize;
        uint256 returnValue;
        assembly ("memory-safe") {
            success := call(gas(), token, 0, add(data, 0x20), mload(data), 0, 0x20)
            returnSize := returndatasize()
            returnValue := mload(0)
        }
        return success && (returnSize == 0 || returnValue != 0);
    }
}

// =============================================================================
// ASTERPAD ROUTER CONTRACT
// =============================================================================

contract AsterPadRouter is ReentrancyGuard, Pausable, Ownable2Step {
    using SafeERC20 for IERC20;
    
    // ==========================================================================
    // CONSTANTS & IMMUTABLES
    // ==========================================================================
    
    // PancakeSwap Router on BSC Mainnet
    IPancakeRouter02 public immutable pancakeRouter;
    address public immutable WBNB;
    
    // Fee constants (basis points, 10000 = 100%)
    uint256 public constant PLATFORM_FEE_BPS = 100;    // 1.0%
    uint256 public constant CREATOR_FEE_BPS = 50;      // 0.5%
    uint256 public constant TOTAL_FEE_BPS = 150;       // 1.5%
    uint256 public constant BPS_DENOMINATOR = 10000;
    
    // Dead address for burning
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    
    // ==========================================================================
    // STATE VARIABLES
    // ==========================================================================
    
    // Treasury address for platform fees
    address public treasury;
    
    // Token -> Creator mapping (perpetual royalties)
    mapping(address => address) public tokenCreator;
    
    // Track which tokens are registered AsterPad tokens
    mapping(address => bool) public isRegisteredToken;
    
    // Launch mode for Snowball/Fireball tokens
    // 0 = Standard, 1 = Snowball, 2 = Fireball
    mapping(address => uint8) public tokenLaunchMode;
    
    // Accumulated fees for Snowball/Fireball auto-buyback
    mapping(address => uint256) public pendingBuyback;
    
    // Global stats
    uint256 public totalPlatformFees;
    uint256 public totalCreatorFees;
    uint256 public totalTradesRouted;
    
    // Per-token stats
    mapping(address => uint256) public tokenPlatformFees;
    mapping(address => uint256) public tokenCreatorFees;
    mapping(address => uint256) public tokenTradeCount;
    mapping(address => uint256) public tokenVolumeBnb;
    
    // Snowball/Fireball stats
    mapping(address => uint256) public tokenBuybackBnb;
    mapping(address => uint256) public tokenBurnedAmount;
    
    // Minimum buyback threshold
    uint256 public minBuybackThreshold = 0.001 ether;
    
    // ==========================================================================
    // CUSTOM ERRORS
    // ==========================================================================
    
    error InvalidAddress();
    error TokenNotRegistered();
    error TokenAlreadyRegistered();
    error InvalidLaunchMode();
    error NoBNBSent();
    error NoTokensSent();
    error DeadlineExpired();
    error SlippageTooHigh();
    error BelowBuybackThreshold();
    error NotSnowballToken();
    error BNBTransferFailed();
    error CannotRecoverRegisteredToken();
    
    // ==========================================================================
    // EVENTS
    // ==========================================================================
    
    event TokenRegistered(
        address indexed token, 
        address indexed creator, 
        uint8 launchMode,
        uint256 timestamp
    );
    
    event TokenBuy(
        address indexed token,
        address indexed buyer,
        uint256 bnbIn,
        uint256 tokensOut,
        uint256 platformFee,
        uint256 creatorFee,
        uint256 timestamp
    );
    
    event TokenSell(
        address indexed token,
        address indexed seller,
        uint256 tokensIn,
        uint256 bnbOut,
        uint256 platformFee,
        uint256 creatorFee,
        uint256 timestamp
    );
    
    event CreatorFeeDistributed(
        address indexed token,
        address indexed creator,
        uint256 amount
    );
    
    event BuybackExecuted(
        address indexed token,
        uint256 bnbUsed,
        uint256 tokensBurned
    );
    
    event BuybackFailed(
        address indexed token,
        uint256 bnbAmount,
        string reason
    );
    
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event CreatorUpdated(address indexed token, address indexed oldCreator, address indexed newCreator);
    event MinBuybackThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    
    // ==========================================================================
    // CONSTRUCTOR
    // ==========================================================================
    
    constructor(
        address _pancakeRouter, 
        address _treasury
    ) Ownable(msg.sender) {
        if (_pancakeRouter == address(0)) revert InvalidAddress();
        if (_treasury == address(0)) revert InvalidAddress();
        
        pancakeRouter = IPancakeRouter02(_pancakeRouter);
        WBNB = pancakeRouter.WETH();
        treasury = _treasury;
    }
    
    // ==========================================================================
    // REGISTRATION (Called by owner when tokens graduate)
    // ==========================================================================
    
    /**
     * @notice Register a token for perpetual fee collection
     * @param token The token address
     * @param creator The creator's address for royalties
     * @param launchMode 0 = Standard, 1 = Snowball, 2 = Fireball
     */
    function registerToken(
        address token, 
        address creator,
        uint8 launchMode
    ) external onlyOwner {
        if (token == address(0)) revert InvalidAddress();
        if (creator == address(0)) revert InvalidAddress();
        if (isRegisteredToken[token]) revert TokenAlreadyRegistered();
        if (launchMode > 2) revert InvalidLaunchMode();
        
        isRegisteredToken[token] = true;
        tokenCreator[token] = creator;
        tokenLaunchMode[token] = launchMode;
        
        emit TokenRegistered(token, creator, launchMode, block.timestamp);
    }
    
    /**
     * @notice Batch register multiple tokens
     * @dev Useful for migrating existing graduated tokens
     */
    function batchRegisterTokens(
        address[] calldata tokens,
        address[] calldata creators,
        uint8[] calldata launchModes
    ) external onlyOwner {
        uint256 length = tokens.length;
        require(length == creators.length && length == launchModes.length, "Length mismatch");
        
        for (uint256 i = 0; i < length;) {
            address token = tokens[i];
            address creator = creators[i];
            uint8 mode = launchModes[i];
            
            if (!isRegisteredToken[token] && token != address(0) && creator != address(0) && mode <= 2) {
                isRegisteredToken[token] = true;
                tokenCreator[token] = creator;
                tokenLaunchMode[token] = mode;
                
                emit TokenRegistered(token, creator, mode, block.timestamp);
            }
            
            unchecked { ++i; }
        }
    }
    
    // ==========================================================================
    // TRADING FUNCTIONS
    // ==========================================================================
    
    /**
     * @notice Buy tokens with BNB (applies fees first, then swaps remainder)
     * @param token The token to buy
     * @param minTokensOut Minimum tokens to receive (slippage protection)
     * @param deadline Transaction deadline
     */
    function buyTokens(
        address token,
        uint256 minTokensOut,
        uint256 deadline
    ) external payable nonReentrant whenNotPaused {
        if (!isRegisteredToken[token]) revert TokenNotRegistered();
        if (msg.value == 0) revert NoBNBSent();
        if (deadline < block.timestamp) revert DeadlineExpired();
        
        // Calculate fees
        uint256 platformFee = (msg.value * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;
        uint256 creatorFee = (msg.value * CREATOR_FEE_BPS) / BPS_DENOMINATOR;
        uint256 swapAmount = msg.value - platformFee - creatorFee;
        
        // Send platform fee to treasury
        _sendBNB(treasury, platformFee);
        totalPlatformFees += platformFee;
        tokenPlatformFees[token] += platformFee;
        
        // Handle creator fee based on launch mode
        _handleCreatorFee(token, creatorFee);
        
        // Perform swap via PancakeSwap
        address[] memory path = new address[](2);
        path[0] = WBNB;
        path[1] = token;
        
        uint256 balanceBefore = IERC20(token).balanceOf(msg.sender);
        
        pancakeRouter.swapExactETHForTokensSupportingFeeOnTransferTokens{value: swapAmount}(
            minTokensOut,
            path,
            msg.sender,
            deadline
        );
        
        uint256 tokensReceived = IERC20(token).balanceOf(msg.sender) - balanceBefore;
        
        // Update stats
        totalTradesRouted++;
        tokenTradeCount[token]++;
        tokenVolumeBnb[token] += msg.value;
        
        emit TokenBuy(token, msg.sender, msg.value, tokensReceived, platformFee, creatorFee, block.timestamp);
    }
    
    /**
     * @notice Sell tokens for BNB (swaps first, then applies fees to output)
     * @param token The token to sell
     * @param tokenAmount Amount of tokens to sell
     * @param minBnbOut Minimum BNB to receive after fees (slippage protection)
     * @param deadline Transaction deadline
     */
    function sellTokens(
        address token,
        uint256 tokenAmount,
        uint256 minBnbOut,
        uint256 deadline
    ) external nonReentrant whenNotPaused {
        if (!isRegisteredToken[token]) revert TokenNotRegistered();
        if (tokenAmount == 0) revert NoTokensSent();
        if (deadline < block.timestamp) revert DeadlineExpired();
        
        // Transfer tokens from user
        IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmount);
        
        // Approve router
        IERC20(token).forceApprove(address(pancakeRouter), tokenAmount);
        
        // Perform swap via PancakeSwap
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = WBNB;
        
        uint256 balanceBefore = address(this).balance;
        
        pancakeRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // We check minBnbOut after fees
            path,
            address(this),
            deadline
        );
        
        uint256 bnbReceived = address(this).balance - balanceBefore;
        
        // Calculate fees from output
        uint256 platformFee = (bnbReceived * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;
        uint256 creatorFee = (bnbReceived * CREATOR_FEE_BPS) / BPS_DENOMINATOR;
        uint256 userAmount = bnbReceived - platformFee - creatorFee;
        
        if (userAmount < minBnbOut) revert SlippageTooHigh();
        
        // Send platform fee to treasury
        _sendBNB(treasury, platformFee);
        totalPlatformFees += platformFee;
        tokenPlatformFees[token] += platformFee;
        
        // Handle creator fee based on launch mode
        _handleCreatorFee(token, creatorFee);
        
        // Send remaining BNB to user
        _sendBNB(msg.sender, userAmount);
        
        // Update stats
        totalTradesRouted++;
        tokenTradeCount[token]++;
        tokenVolumeBnb[token] += bnbReceived;
        
        emit TokenSell(token, msg.sender, tokenAmount, userAmount, platformFee, creatorFee, block.timestamp);
    }
    
    // ==========================================================================
    // INTERNAL FUNCTIONS
    // ==========================================================================
    
    /**
     * @notice Handle creator fee based on launch mode
     */
    function _handleCreatorFee(address token, uint256 amount) internal {
        uint8 mode = tokenLaunchMode[token];
        
        if (mode == 0) {
            // Standard: send to creator immediately
            address creator = tokenCreator[token];
            _sendBNB(creator, amount);
            totalCreatorFees += amount;
            tokenCreatorFees[token] += amount;
            emit CreatorFeeDistributed(token, creator, amount);
        } else {
            // Snowball/Fireball: accumulate for buyback
            pendingBuyback[token] += amount;
            totalCreatorFees += amount;
            tokenCreatorFees[token] += amount;
        }
    }
    
    /**
     * @notice Send BNB safely
     */
    function _sendBNB(address to, uint256 amount) internal {
        if (amount > 0) {
            (bool success, ) = payable(to).call{value: amount}("");
            if (!success) revert BNBTransferFailed();
        }
    }
    
    // ==========================================================================
    // SNOWBALL/FIREBALL AUTO-BUYBACK
    // ==========================================================================
    
    /**
     * @notice Execute buyback for a Snowball/Fireball token
     * @param token The token to buyback and burn
     * @param minTokensOut Minimum tokens to receive (slippage protection)
     */
    function executeBuyback(
        address token,
        uint256 minTokensOut
    ) external nonReentrant whenNotPaused {
        if (!isRegisteredToken[token]) revert TokenNotRegistered();
        if (tokenLaunchMode[token] == 0) revert NotSnowballToken();
        
        uint256 amount = pendingBuyback[token];
        if (amount < minBuybackThreshold) revert BelowBuybackThreshold();
        
        pendingBuyback[token] = 0;
        
        // Perform buyback
        address[] memory path = new address[](2);
        path[0] = WBNB;
        path[1] = token;
        
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        
        try pancakeRouter.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amount}(
            minTokensOut,
            path,
            address(this),
            block.timestamp + 300
        ) {
            uint256 tokensBought = IERC20(token).balanceOf(address(this)) - balanceBefore;
            
            if (tokensBought > 0) {
                IERC20(token).safeTransfer(DEAD, tokensBought);
                tokenBuybackBnb[token] += amount;
                tokenBurnedAmount[token] += tokensBought;
                
                emit BuybackExecuted(token, amount, tokensBought);
            }
        } catch {
            // Restore pending buyback on failure
            pendingBuyback[token] = amount;
            emit BuybackFailed(token, amount, "Swap failed");
        }
    }
    
    /**
     * @notice Batch execute buybacks for multiple tokens
     * @dev Can be called by anyone (cron job, keeper, etc.)
     */
    function batchExecuteBuyback(
        address[] calldata tokens,
        uint256 minTokensOut
    ) external nonReentrant whenNotPaused {
        uint256 length = tokens.length;
        
        for (uint256 i = 0; i < length;) {
            address token = tokens[i];
            
            if (isRegisteredToken[token] && 
                tokenLaunchMode[token] > 0 && 
                pendingBuyback[token] >= minBuybackThreshold) {
                
                uint256 amount = pendingBuyback[token];
                pendingBuyback[token] = 0;
                
                address[] memory path = new address[](2);
                path[0] = WBNB;
                path[1] = token;
                
                uint256 balanceBefore = IERC20(token).balanceOf(address(this));
                
                try pancakeRouter.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amount}(
                    minTokensOut,
                    path,
                    address(this),
                    block.timestamp + 300
                ) {
                    uint256 tokensBought = IERC20(token).balanceOf(address(this)) - balanceBefore;
                    
                    if (tokensBought > 0) {
                        IERC20(token).safeTransfer(DEAD, tokensBought);
                        tokenBuybackBnb[token] += amount;
                        tokenBurnedAmount[token] += tokensBought;
                        
                        emit BuybackExecuted(token, amount, tokensBought);
                    }
                } catch {
                    // Restore pending buyback on failure
                    pendingBuyback[token] = amount;
                    emit BuybackFailed(token, amount, "Swap failed");
                }
            }
            
            unchecked { ++i; }
        }
    }
    
    /**
     * @notice Get tokens with pending buybacks above threshold
     */
    function getTokensWithPendingBuybacks(
        address[] calldata tokens
    ) external view returns (address[] memory eligibleTokens, uint256[] memory amounts) {
        uint256 count = 0;
        uint256 length = tokens.length;
        
        // First pass: count eligible
        for (uint256 i = 0; i < length;) {
            if (pendingBuyback[tokens[i]] >= minBuybackThreshold && tokenLaunchMode[tokens[i]] > 0) {
                count++;
            }
            unchecked { ++i; }
        }
        
        // Second pass: populate arrays
        eligibleTokens = new address[](count);
        amounts = new uint256[](count);
        uint256 j = 0;
        
        for (uint256 i = 0; i < length;) {
            if (pendingBuyback[tokens[i]] >= minBuybackThreshold && tokenLaunchMode[tokens[i]] > 0) {
                eligibleTokens[j] = tokens[i];
                amounts[j] = pendingBuyback[tokens[i]];
                unchecked { ++j; }
            }
            unchecked { ++i; }
        }
    }
    
    // ==========================================================================
    // VIEW FUNCTIONS
    // ==========================================================================
    
    /**
     * @notice Get token info and stats
     */
    function getTokenInfo(address token) external view returns (
        bool registered,
        address creator,
        uint8 launchMode,
        uint256 platformFees,
        uint256 creatorFees,
        uint256 tradeCount,
        uint256 volumeBnb,
        uint256 buybackBnb,
        uint256 burnedAmount,
        uint256 pendingBnb
    ) {
        return (
            isRegisteredToken[token],
            tokenCreator[token],
            tokenLaunchMode[token],
            tokenPlatformFees[token],
            tokenCreatorFees[token],
            tokenTradeCount[token],
            tokenVolumeBnb[token],
            tokenBuybackBnb[token],
            tokenBurnedAmount[token],
            pendingBuyback[token]
        );
    }
    
    /**
     * @notice Get global router stats
     */
    function getGlobalStats() external view returns (
        uint256 _totalPlatformFees,
        uint256 _totalCreatorFees,
        uint256 _totalTradesRouted,
        address _treasury,
        uint256 _minBuybackThreshold
    ) {
        return (
            totalPlatformFees,
            totalCreatorFees,
            totalTradesRouted,
            treasury,
            minBuybackThreshold
        );
    }
    
    /**
     * @notice Estimate tokens out for a buy
     */
    function estimateBuyTokensOut(
        address token,
        uint256 bnbIn
    ) external view returns (uint256 tokensOut, uint256 platformFee, uint256 creatorFee) {
        platformFee = (bnbIn * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;
        creatorFee = (bnbIn * CREATOR_FEE_BPS) / BPS_DENOMINATOR;
        uint256 swapAmount = bnbIn - platformFee - creatorFee;
        
        address[] memory path = new address[](2);
        path[0] = WBNB;
        path[1] = token;
        
        try pancakeRouter.getAmountsOut(swapAmount, path) returns (uint256[] memory amounts) {
            tokensOut = amounts[1];
        } catch {
            tokensOut = 0;
        }
    }
    
    /**
     * @notice Estimate BNB out for a sell (after fees)
     */
    function estimateSellBnbOut(
        address token,
        uint256 tokensIn
    ) external view returns (uint256 bnbOut, uint256 platformFee, uint256 creatorFee) {
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = WBNB;
        
        try pancakeRouter.getAmountsOut(tokensIn, path) returns (uint256[] memory amounts) {
            uint256 grossBnb = amounts[1];
            platformFee = (grossBnb * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;
            creatorFee = (grossBnb * CREATOR_FEE_BPS) / BPS_DENOMINATOR;
            bnbOut = grossBnb - platformFee - creatorFee;
        } catch {
            bnbOut = 0;
        }
    }
    
    /**
     * @notice Get contract BNB balance
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    // ==========================================================================
    // ADMIN FUNCTIONS
    // ==========================================================================
    
    /**
     * @notice Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @notice Update treasury address
     */
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert InvalidAddress();
        emit TreasuryUpdated(treasury, _treasury);
        treasury = _treasury;
    }
    
    /**
     * @notice Update token creator (for community takeovers, etc.)
     */
    function updateCreator(address token, address newCreator) external onlyOwner {
        if (!isRegisteredToken[token]) revert TokenNotRegistered();
        if (newCreator == address(0)) revert InvalidAddress();
        
        address oldCreator = tokenCreator[token];
        tokenCreator[token] = newCreator;
        
        emit CreatorUpdated(token, oldCreator, newCreator);
    }
    
    /**
     * @notice Update minimum buyback threshold
     */
    function setMinBuybackThreshold(uint256 _threshold) external onlyOwner {
        emit MinBuybackThresholdUpdated(minBuybackThreshold, _threshold);
        minBuybackThreshold = _threshold;
    }
    
    /**
     * @notice Recover stuck tokens (not registered AsterPad tokens)
     */
    function recoverToken(address token, uint256 amount, address to) external onlyOwner {
        if (isRegisteredToken[token]) revert CannotRecoverRegisteredToken();
        if (to == address(0)) revert InvalidAddress();
        IERC20(token).safeTransfer(to, amount);
    }
    
    /**
     * @notice Recover stuck BNB (only when paused for safety)
     */
    function recoverBNB(uint256 amount, address to) external onlyOwner whenPaused {
        if (to == address(0)) revert InvalidAddress();
        _sendBNB(to, amount);
    }
    
    // Allow receiving BNB
    receive() external payable {}
}

