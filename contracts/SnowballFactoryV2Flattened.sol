// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * ASTERPAD SNOWBALL/FIREBALL FACTORY V2 - FAIR PER-POOL DISTRIBUTION
 * 
 * CHANGES FROM V1:
 * - Tracks fees PER POOL (each token's fees only buy back THAT token)
 * - Creator fees are fairly distributed to the token they came from
 * 
 * Deploy with constructor parameter:
 * _tokenFactory: 0x0fff767cad811554994f3b9e6317730ff25720e3
 */

// =============================================================================
// OPENZEPPELIN CONTRACTS (FLATTENED)
// =============================================================================

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

abstract contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    constructor(address initialOwner) {
        _transferOwnership(initialOwner);
    }
    
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }
    
    function owner() public view virtual returns (address) {
        return _owner;
    }
    
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }
    
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }
    
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

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
        require(pendingOwner() == sender, "Ownable2Step: caller is not the new owner");
        _transferOwnership(sender);
    }
}

abstract contract Pausable is Context {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    
    constructor() {
        _paused = false;
    }
    
    modifier whenNotPaused() {
        require(!paused(), "Pausable: paused");
        _;
    }
    
    modifier whenPaused() {
        require(paused(), "Pausable: not paused");
        _;
    }
    
    function paused() public view virtual returns (bool) {
        return _paused;
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

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;
    
    constructor() {
        _status = _NOT_ENTERED;
    }
    
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

library SafeERC20 {
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(token.transfer.selector, to, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "SafeERC20: transfer failed");
    }
    
    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(token.transferFrom.selector, from, to, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "SafeERC20: transferFrom failed");
    }
}

// =============================================================================
// INTERFACES
// =============================================================================

interface ITokenFactory {
    function createToken(
        string calldata name,
        string calldata symbol,
        string calldata logoURI,
        string calldata description,
        string calldata category
    ) external payable returns (address tokenAddr, address poolAddr);
    
    function tokenToPool(address token) external view returns (address);
    function isAsterPool(address pool) external view returns (bool);
    function creationFee() external view returns (uint256);
}

interface ILaunchpadPool {
    function token() external view returns (address);
    function creator() external view returns (address);
    function tokensSold() external view returns (uint256);
    function tokensOnCurve() external view returns (uint256);
    function basePrice() external view returns (uint256);
    function slope() external view returns (uint256);
    function graduated() external view returns (bool);
    function tradingActive() external view returns (bool);
    function buy(uint256 minTokens) external payable returns (uint256);
    function bnbRaised() external view returns (uint256);
    function graduationThreshold() external view returns (uint256);
}

// =============================================================================
// LAUNCH MODE ENUM
// =============================================================================
enum LaunchMode {
    SNOWBALL,   // 0 - Creator's 0.5% goes to buyback + burn
    FIREBALL    // 1 - Same as Snowball, different branding
}

// =============================================================================
// SNOWBALL FACTORY V2 - FAIR PER-POOL DISTRIBUTION
// =============================================================================
contract SnowballFactoryV2 is ReentrancyGuard, Pausable, Ownable2Step {
    using SafeERC20 for IERC20;
    
    address public immutable tokenFactory;
    address constant DEAD = 0x000000000000000000000000000000000000dEaD;
    
    // Minimum tokens to receive on buyback (slippage protection)
    uint256 public minBuybackTokens = 1;
    
    // Minimum BNB threshold before triggering buyback (saves gas on tiny amounts)
    uint256 public minBuybackThreshold = 0.001 ether; // 0.001 BNB
    
    // Pool -> Real Creator (since contract address is set as creator in pool)
    mapping(address => address) public poolToRealCreator;
    mapping(address => LaunchMode) public poolLaunchMode;
    mapping(address => bool) public isSnowballPool;
    mapping(address => address) public tokenToPool;
    
    // =========================================================================
    // V2 CHANGE: Per-pool pending buyback amounts
    // Each pool's fees are tracked separately for fair distribution
    // =========================================================================
    mapping(address => uint256) public pendingBuyback;
    
    // Stats per pool
    mapping(address => uint256) public totalBuybackBnb;
    mapping(address => uint256) public totalTokensBurned;
    
    // All tokens created via this factory
    address[] public allSnowballTokens;
    
    // Global stats
    uint256 public totalBuybacksBnb;
    uint256 public totalTokensBurnedGlobal;
    uint256 public snowballPoolCount;
    uint256 public fireballPoolCount;
    
    // Events
    event SnowballTokenCreated(
        address indexed token, 
        address indexed pool, 
        address indexed realCreator, 
        LaunchMode mode
    );
    event AutoBuyback(
        address indexed pool, 
        uint256 bnbAmount, 
        uint256 tokensBought, 
        uint256 tokensBurned
    );
    event BuybackFailed(
        address indexed pool,
        uint256 bnbAmount,
        uint256 minTokensRequested,
        string reason
    );
    event CreatorFeeReceived(address indexed pool, uint256 amount, uint256 newPendingTotal);
    event BNBRecovered(address indexed to, uint256 amount);
    event MinBuybackTokensUpdated(uint256 oldValue, uint256 newValue);
    event MinBuybackThresholdUpdated(uint256 oldValue, uint256 newValue);
    event UnknownBNBReceived(address indexed sender, uint256 amount);
    
    constructor(address _tokenFactory) Ownable(msg.sender) {
        require(_tokenFactory != address(0), "Invalid factory");
        tokenFactory = _tokenFactory;
    }
    
    /**
     * @dev Create a Snowball or Fireball token
     * This creates a token via the real factory but sets THIS contract as creator
     * so all creator fees come here for auto-buyback
     */
    function createSnowballToken(
        string calldata name,
        string calldata symbol,
        string calldata logoURI,
        string calldata description,
        string calldata category,
        LaunchMode mode
    ) external payable nonReentrant whenNotPaused returns (address tokenAddr, address poolAddr) {
        require(msg.value >= ITokenFactory(tokenFactory).creationFee(), "Insufficient creation fee");
        
        // Create token via real factory - THIS CONTRACT becomes the "creator"
        (tokenAddr, poolAddr) = ITokenFactory(tokenFactory).createToken{value: msg.value}(
            name, symbol, logoURI, description, category
        );
        
        // Track the real creator and pool info
        _registerPool(poolAddr, tokenAddr, msg.sender, mode);
    }
    
    /**
     * @dev Internal function to register pool (reduces stack depth)
     */
    function _registerPool(address poolAddr, address tokenAddr, address creator, LaunchMode mode) internal {
        poolToRealCreator[poolAddr] = creator;
        poolLaunchMode[poolAddr] = mode;
        isSnowballPool[poolAddr] = true;
        tokenToPool[tokenAddr] = poolAddr;
        allSnowballTokens.push(tokenAddr);
        
        if (mode == LaunchMode.SNOWBALL) snowballPoolCount++;
        else fireballPoolCount++;
        
        emit SnowballTokenCreated(tokenAddr, poolAddr, creator, mode);
    }
    
    /**
     * @dev Receive creator fees from pools
     * V2 CHANGE: Now tracks which pool sent the fee for fair distribution
     * When trades happen, the pool sends 0.5% here (since we're the "creator")
     */
    receive() external payable {
        // msg.sender is the pool that sent the fee
        if (isSnowballPool[msg.sender]) {
            // Track this fee for THIS specific pool
            pendingBuyback[msg.sender] += msg.value;
            emit CreatorFeeReceived(msg.sender, msg.value, pendingBuyback[msg.sender]);
        } else {
            // Unknown sender - could be manual deposit or error
            // Accept it but log for monitoring
            emit UnknownBNBReceived(msg.sender, msg.value);
        }
    }
    
    /**
     * @dev Process buyback for a specific pool using ONLY that pool's accumulated fees
     * V2 CHANGE: Uses per-pool pendingBuyback instead of total contract balance
     * @param pool The pool address to process (must be created by this factory)
     * @param minTokensOut Minimum tokens to receive (slippage protection)
     */
    function processBuyback(address pool, uint256 minTokensOut) external nonReentrant {
        require(isSnowballPool[pool], "Not a valid snowball pool");
        require(minTokensOut >= minBuybackTokens, "Min tokens too low");
        
        uint256 poolBalance = pendingBuyback[pool];
        require(poolBalance > 0, "No pending buyback for this pool");
        require(poolBalance >= minBuybackThreshold, "Below minimum threshold");
        
        ILaunchpadPool poolContract = ILaunchpadPool(pool);
        require(!poolContract.graduated(), "Pool graduated");
        require(poolContract.tradingActive(), "Trading not active");
        
        // Clear pending BEFORE external call (reentrancy protection)
        pendingBuyback[pool] = 0;
        
        _executeBuyback(pool, poolBalance, minTokensOut);
    }
    
    /**
     * @dev Auto-process buyback for a pool when it has pending fees
     * Anyone can call this to trigger buybacks
     * V2 CHANGE: Only uses THIS pool's accumulated fees, not shared pool
     * @param pool The pool address (must be created by this factory)
     * @param minTokensOut Minimum tokens to receive (slippage protection)
     */
    function autoBuyback(address pool, uint256 minTokensOut) external nonReentrant {
        require(isSnowballPool[pool], "Not a valid snowball pool");
        require(minTokensOut >= minBuybackTokens, "Min tokens too low");
        
        uint256 poolBalance = pendingBuyback[pool];
        if (poolBalance == 0 || poolBalance < minBuybackThreshold) return;
        
        ILaunchpadPool poolContract = ILaunchpadPool(pool);
        if (poolContract.graduated() || !poolContract.tradingActive()) return;
        
        // Clear pending BEFORE external call (reentrancy protection)
        pendingBuyback[pool] = 0;
        
        _executeBuyback(pool, poolBalance, minTokensOut);
    }
    
    /**
     * @dev Batch process buybacks for multiple pools
     * Useful for Chainlink Automation to process all pools in one tx
     * @param pools Array of pool addresses to process
     * @param minTokensOut Minimum tokens per buyback (slippage protection)
     */
    function batchAutoBuyback(address[] calldata pools, uint256 minTokensOut) external nonReentrant {
        require(minTokensOut >= minBuybackTokens, "Min tokens too low");
        
        for (uint256 i = 0; i < pools.length; i++) {
            address pool = pools[i];
            
            if (!isSnowballPool[pool]) continue;
            
            uint256 poolBalance = pendingBuyback[pool];
            if (poolBalance == 0 || poolBalance < minBuybackThreshold) continue;
            
            ILaunchpadPool poolContract = ILaunchpadPool(pool);
            if (poolContract.graduated() || !poolContract.tradingActive()) continue;
            
            // Clear pending BEFORE external call
            pendingBuyback[pool] = 0;
            
            _executeBuybackSafe(pool, poolBalance, minTokensOut);
        }
    }
    
    /**
     * @dev Execute buyback: buy tokens from pool and burn them
     * @param pool The validated pool address
     * @param bnbAmount Amount of BNB to spend
     * @param minTokensOut Minimum tokens to receive (slippage protection)
     */
    function _executeBuyback(address pool, uint256 bnbAmount, uint256 minTokensOut) internal {
        if (bnbAmount == 0) return;
        
        ILaunchpadPool poolContract = ILaunchpadPool(pool);
        address tokenAddr = poolContract.token();
        
        // Buy tokens from the pool with slippage protection
        try poolContract.buy{value: bnbAmount}(minTokensOut) returns (uint256 tokensBought) {
            require(tokensBought >= minTokensOut, "Slippage exceeded");
            
            if (tokensBought > 0) {
                // Send tokens to dead address (burn) using SafeERC20
                IERC20(tokenAddr).safeTransfer(DEAD, tokensBought);
                
                // Update stats
                totalBuybackBnb[pool] += bnbAmount;
                totalTokensBurned[pool] += tokensBought;
                totalBuybacksBnb += bnbAmount;
                totalTokensBurnedGlobal += tokensBought;
                
                emit AutoBuyback(pool, bnbAmount, tokensBought, tokensBought);
            }
        } catch Error(string memory reason) {
            // Buyback failed - restore pending balance for retry
            pendingBuyback[pool] += bnbAmount;
            emit BuybackFailed(pool, bnbAmount, minTokensOut, reason);
        } catch {
            // Buyback failed without reason - restore pending balance
            pendingBuyback[pool] += bnbAmount;
            emit BuybackFailed(pool, bnbAmount, minTokensOut, "Unknown error");
        }
    }
    
    /**
     * @dev Safe version for batch processing - doesn't revert on failure
     */
    function _executeBuybackSafe(address pool, uint256 bnbAmount, uint256 minTokensOut) internal {
        if (bnbAmount == 0) return;
        
        ILaunchpadPool poolContract = ILaunchpadPool(pool);
        address tokenAddr = poolContract.token();
        
        try poolContract.buy{value: bnbAmount}(minTokensOut) returns (uint256 tokensBought) {
            if (tokensBought >= minTokensOut && tokensBought > 0) {
                IERC20(tokenAddr).safeTransfer(DEAD, tokensBought);
                
                totalBuybackBnb[pool] += bnbAmount;
                totalTokensBurned[pool] += tokensBought;
                totalBuybacksBnb += bnbAmount;
                totalTokensBurnedGlobal += tokensBought;
                
                emit AutoBuyback(pool, bnbAmount, tokensBought, tokensBought);
            } else {
                // Restore balance if slippage failed
                pendingBuyback[pool] += bnbAmount;
            }
        } catch {
            // Restore pending balance for retry
            pendingBuyback[pool] += bnbAmount;
            emit BuybackFailed(pool, bnbAmount, minTokensOut, "Batch buyback failed");
        }
    }
    
    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================
    
    function getPoolInfo(address pool) external view returns (
        address realCreator,
        LaunchMode mode,
        uint256 buybackBnb,
        uint256 tokensBurned,
        uint256 pendingBnb,
        bool isRegistered
    ) {
        return (
            poolToRealCreator[pool],
            poolLaunchMode[pool],
            totalBuybackBnb[pool],
            totalTokensBurned[pool],
            pendingBuyback[pool],
            isSnowballPool[pool]
        );
    }
    
    function getGlobalStats() external view returns (
        uint256 _totalBuybacksBnb,
        uint256 _totalTokensBurned,
        uint256 _snowballPools,
        uint256 _fireballPools,
        uint256 _totalPools,
        uint256 _contractBalance
    ) {
        return (
            totalBuybacksBnb, 
            totalTokensBurnedGlobal, 
            snowballPoolCount, 
            fireballPoolCount,
            allSnowballTokens.length,
            address(this).balance
        );
    }
    
    /**
     * @dev Get all pools with pending buybacks above threshold
     * Useful for Chainlink Automation to know which pools to process
     */
    function getPoolsWithPendingBuybacks() external view returns (
        address[] memory pools,
        uint256[] memory amounts
    ) {
        uint256 count = 0;
        
        // First pass: count eligible pools
        for (uint256 i = 0; i < allSnowballTokens.length; i++) {
            address pool = tokenToPool[allSnowballTokens[i]];
            if (pendingBuyback[pool] >= minBuybackThreshold) {
                count++;
            }
        }
        
        // Second pass: populate arrays
        pools = new address[](count);
        amounts = new uint256[](count);
        uint256 index = 0;
        
        for (uint256 i = 0; i < allSnowballTokens.length; i++) {
            address pool = tokenToPool[allSnowballTokens[i]];
            uint256 pending = pendingBuyback[pool];
            if (pending >= minBuybackThreshold) {
                pools[index] = pool;
                amounts[index] = pending;
                index++;
            }
        }
    }
    
    function getAllSnowballTokens() external view returns (address[] memory) {
        return allSnowballTokens;
    }
    
    function getSnowballTokenCount() external view returns (uint256) {
        return allSnowballTokens.length;
    }
    
    function getLaunchModeString(address pool) external view returns (string memory) {
        if (!isSnowballPool[pool]) return "Standard";
        LaunchMode mode = poolLaunchMode[pool];
        if (mode == LaunchMode.SNOWBALL) return "Snowball";
        return "Fireball";
    }
    
    function getRealCreator(address pool) external view returns (address) {
        return poolToRealCreator[pool];
    }
    
    function getPendingBuyback(address pool) external view returns (uint256) {
        return pendingBuyback[pool];
    }
    
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    // =============================================================================
    // ADMIN FUNCTIONS
    // =============================================================================
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    function emergencyWithdraw(address to) external onlyOwner whenPaused {
        require(to != address(0), "Invalid address");
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance");
        (bool ok,) = to.call{value: balance}("");
        require(ok, "Withdraw failed");
    }
    
    function emergencyWithdrawToken(address token, address to) external onlyOwner whenPaused {
        require(to != address(0), "Invalid address");
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No balance");
        IERC20(token).safeTransfer(to, balance);
    }
    
    function recoverBNB(address to, uint256 amount) external onlyOwner whenPaused {
        require(to != address(0), "Invalid address");
        require(amount > 0 && amount <= address(this).balance, "Invalid amount");
        (bool ok,) = to.call{value: amount}("");
        require(ok, "Transfer failed");
        emit BNBRecovered(to, amount);
    }
    
    function setMinBuybackTokens(uint256 newMin) external onlyOwner {
        uint256 oldMin = minBuybackTokens;
        minBuybackTokens = newMin;
        emit MinBuybackTokensUpdated(oldMin, newMin);
    }
    
    function setMinBuybackThreshold(uint256 newThreshold) external onlyOwner {
        uint256 oldThreshold = minBuybackThreshold;
        minBuybackThreshold = newThreshold;
        emit MinBuybackThresholdUpdated(oldThreshold, newThreshold);
    }
}

