// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * ASTERPAD SNOWBALL/FIREBALL FACTORY - FLATTENED FOR REMIX DEPLOYMENT
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
// SNOWBALL FACTORY - Creates tokens with auto-buyback mechanics
// =============================================================================
contract SnowballFactory is ReentrancyGuard, Pausable, Ownable2Step {
    using SafeERC20 for IERC20;
    
    address public immutable tokenFactory;
    address constant DEAD = 0x000000000000000000000000000000000000dEaD;
    
    // Minimum tokens to receive on buyback (slippage protection)
    uint256 public minBuybackTokens = 1;
    
    // Pool -> Real Creator (since contract address is set as creator in pool)
    mapping(address => address) public poolToRealCreator;
    mapping(address => LaunchMode) public poolLaunchMode;
    mapping(address => bool) public isSnowballPool;  // Also serves as pool validation
    mapping(address => address) public tokenToPool;
    
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
    
    // Pending buyback amounts per pool
    mapping(address => uint256) public pendingBuyback;
    
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
        uint256 minTokensRequested
    );
    event CreatorFeeReceived(address indexed pool, uint256 amount);
    event BNBRecovered(address indexed to, uint256 amount);
    event MinBuybackTokensUpdated(uint256 oldValue, uint256 newValue);
    
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
     * When trades happen, the pool sends 0.5% here (since we're the "creator")
     */
    receive() external payable {
        // BNB received - this is creator fees from trades
        // Will be processed via processBuyback or autoBuyback
    }
    
    /**
     * @dev Process buyback for a specific pool with slippage protection
     * Uses accumulated BNB to buy and burn tokens
     * @param pool The pool address to process (must be created by this factory)
     * @param amount Amount of BNB to use (from contract balance)
     * @param minTokensOut Minimum tokens to receive (slippage protection)
     */
    function processBuyback(address pool, uint256 amount, uint256 minTokensOut) external nonReentrant {
        // SECURITY: Only allow pools created by this factory (pool validation)
        require(isSnowballPool[pool], "Not a valid snowball pool");
        require(amount > 0 && amount <= address(this).balance, "Invalid amount");
        require(minTokensOut >= minBuybackTokens, "Min tokens too low");
        
        ILaunchpadPool poolContract = ILaunchpadPool(pool);
        require(!poolContract.graduated(), "Pool graduated");
        require(poolContract.tradingActive(), "Trading not active");
        
        _executeBuyback(pool, amount, minTokensOut);
    }
    
    /**
     * @dev Auto-process buyback when balance exceeds threshold
     * Anyone can call this to trigger buybacks
     * @param pool The pool address (must be created by this factory)
     * @param minTokensOut Minimum tokens to receive (slippage protection)
     */
    function autoBuyback(address pool, uint256 minTokensOut) external nonReentrant {
        // SECURITY: Only allow pools created by this factory (pool validation)
        require(isSnowballPool[pool], "Not a valid snowball pool");
        require(minTokensOut >= minBuybackTokens, "Min tokens too low");
        
        ILaunchpadPool poolContract = ILaunchpadPool(pool);
        if (poolContract.graduated() || !poolContract.tradingActive()) return;
        
        // Use all available balance for this pool's buyback
        uint256 balance = address(this).balance;
        if (balance > 0) {
            _executeBuyback(pool, balance, minTokensOut);
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
            // SECURITY: Verify we got at least minimum tokens
            require(tokensBought >= minTokensOut, "Slippage exceeded");
            
            if (tokensBought > 0) {
                // Send tokens to dead address (burn) using SafeERC20
                IERC20(tokenAddr).safeTransfer(DEAD, tokensBought);
                
                // Update stats (state changes after external calls - but we're nonReentrant)
                totalBuybackBnb[pool] += bnbAmount;
                totalTokensBurned[pool] += tokensBought;
                totalBuybacksBnb += bnbAmount;
                totalTokensBurnedGlobal += tokensBought;
                
                emit AutoBuyback(pool, bnbAmount, tokensBought, tokensBought);
            }
        } catch {
            // Buyback failed - could be slippage, paused, or graduated
            // BNB stays in contract for retry
            // Emit event for monitoring
            emit BuybackFailed(pool, bnbAmount, minTokensOut);
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
        bool isRegistered
    ) {
        return (
            poolToRealCreator[pool],
            poolLaunchMode[pool],
            totalBuybackBnb[pool],
            totalTokensBurned[pool],
            isSnowballPool[pool]
        );
    }
    
    function getGlobalStats() external view returns (
        uint256 _totalBuybacksBnb,
        uint256 _totalTokensBurned,
        uint256 _snowballPools,
        uint256 _fireballPools,
        uint256 _totalPools
    ) {
        return (
            totalBuybacksBnb, 
            totalTokensBurnedGlobal, 
            snowballPoolCount, 
            fireballPoolCount,
            allSnowballTokens.length
        );
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
    
    // =============================================================================
    // ADMIN FUNCTIONS
    // =============================================================================
    
    /**
     * @dev Pause the contract - prevents new token creation
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @dev Emergency withdraw BNB (only when paused)
     */
    function emergencyWithdraw(address to) external onlyOwner whenPaused {
        require(to != address(0), "Invalid address");
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance");
        (bool ok,) = to.call{value: balance}("");
        require(ok, "Withdraw failed");
    }
    
    /**
     * @dev Emergency withdraw tokens (only when paused)
     */
    function emergencyWithdrawToken(address token, address to) external onlyOwner whenPaused {
        require(to != address(0), "Invalid address");
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No balance");
        IERC20(token).safeTransfer(to, balance);
    }
    
    /**
     * @dev Recover accidentally sent BNB (not from buybacks)
     * Can only be called when paused to prevent interference with normal operations
     */
    function recoverBNB(address to, uint256 amount) external onlyOwner whenPaused {
        require(to != address(0), "Invalid address");
        require(amount > 0 && amount <= address(this).balance, "Invalid amount");
        (bool ok,) = to.call{value: amount}("");
        require(ok, "Transfer failed");
        emit BNBRecovered(to, amount);
    }
    
    /**
     * @dev Update minimum buyback tokens (slippage floor)
     */
    function setMinBuybackTokens(uint256 newMin) external onlyOwner {
        uint256 oldMin = minBuybackTokens;
        minBuybackTokens = newMin;
        emit MinBuybackTokensUpdated(oldMin, newMin);
    }
    
    /**
     * @dev Get contract BNB balance (for monitoring)
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
}

