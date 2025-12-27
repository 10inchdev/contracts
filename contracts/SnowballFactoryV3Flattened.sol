// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * ╔═══════════════════════════════════════════════════════════════════════════╗
 * ║                       SNOWBALL FACTORY V3 - UPGRADEABLE                   ║
 * ║                                                                           ║
 * ║    FEATURES:                                                              ║
 * ║    - UUPS Proxy Pattern (upgradeable)                                     ║
 * ║    - Configurable buyback threshold (0.001 - 1 BNB)                       ║
 * ║    - Per-pool BNB tracking (fair distribution)                            ║
 * ║    - Works with TokenFactory V2 (creator auto-exempt)                     ║
 * ║    - Supports both Snowball & Fireball launch modes                       ║
 * ║                                                                           ║
 * ║  Admin: 0x3717E1A8E2788Ac53D2D5084Dc6FF93d03369D27 (Treasury)             ║
 * ║  Network: BSC Mainnet                                                     ║
 * ╚═══════════════════════════════════════════════════════════════════════════╝
 */

// =============================================================================
// UUPS PROXY INFRASTRUCTURE
// =============================================================================

abstract contract Initializable {
    uint8 private _initialized;
    bool private _initializing;

    event Initialized(uint8 version);

    modifier initializer() {
        bool isTopLevelCall = !_initializing;
        require(
            (isTopLevelCall && _initialized < 1) || (!isTopLevelCall && _initialized == 0),
            "Initializable: contract is already initialized"
        );
        _initialized = 1;
        if (isTopLevelCall) {
            _initializing = true;
        }
        _;
        if (isTopLevelCall) {
            _initializing = false;
            emit Initialized(1);
        }
    }

    modifier reinitializer(uint8 version) {
        require(!_initializing && _initialized < version, "Initializable: contract is already initialized");
        _initialized = version;
        _initializing = true;
        _;
        _initializing = false;
        emit Initialized(version);
    }

    function _disableInitializers() internal virtual {
        require(!_initializing, "Initializable: contract is initializing");
        if (_initialized != type(uint8).max) {
            _initialized = type(uint8).max;
            emit Initialized(type(uint8).max);
        }
    }

    function _getInitializedVersion() internal view returns (uint8) {
        return _initialized;
    }

    function _isInitializing() internal view returns (bool) {
        return _initializing;
    }

    modifier onlyInitializing() {
        require(_initializing, "Initializable: contract is not initializing");
        _;
    }
}

abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal onlyInitializing {
        __Context_init_unchained();
    }

    function __Context_init_unchained() internal onlyInitializing {}

    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function __Ownable_init(address initialOwner) internal onlyInitializing {
        __Context_init_unchained();
        __Ownable_init_unchained(initialOwner);
    }

    function __Ownable_init_unchained(address initialOwner) internal onlyInitializing {
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

abstract contract Ownable2StepUpgradeable is OwnableUpgradeable {
    address private _pendingOwner;

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    function __Ownable2Step_init(address initialOwner) internal onlyInitializing {
        __Ownable_init(initialOwner);
    }

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

abstract contract PausableUpgradeable is Initializable, ContextUpgradeable {
    event Paused(address account);
    event Unpaused(address account);

    bool private _paused;

    function __Pausable_init() internal onlyInitializing {
        __Pausable_init_unchained();
    }

    function __Pausable_init_unchained() internal onlyInitializing {
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

abstract contract ReentrancyGuardUpgradeable is Initializable {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    function __ReentrancyGuard_init() internal onlyInitializing {
        __ReentrancyGuard_init_unchained();
    }

    function __ReentrancyGuard_init_unchained() internal onlyInitializing {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

// =============================================================================
// UUPS UPGRADE MECHANISM
// =============================================================================

interface IERC1822Proxiable {
    function proxiableUUID() external view returns (bytes32);
}

library StorageSlot {
    struct AddressSlot {
        address value;
    }

    function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        assembly {
            r.slot := slot
        }
    }
}

abstract contract ERC1967Upgrade {
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    event Upgraded(address indexed implementation);

    function _getImplementation() internal view returns (address) {
        return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
    }

    function _setImplementation(address newImplementation) private {
        require(newImplementation.code.length > 0, "ERC1967: new implementation is not a contract");
        StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
    }

    function _upgradeTo(address newImplementation) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
    }

    function _upgradeToAndCall(address newImplementation, bytes memory data, bool forceCall) internal {
        _upgradeTo(newImplementation);
        if (data.length > 0 || forceCall) {
            (bool success, ) = newImplementation.delegatecall(data);
            require(success, "ERC1967: upgrade call failed");
        }
    }
}

abstract contract UUPSUpgradeable is Initializable, IERC1822Proxiable, ERC1967Upgrade {
    address private immutable __self = address(this);

    modifier onlyProxy() {
        require(address(this) != __self, "Function must be called through delegatecall");
        require(_getImplementation() == __self, "Function must be called through active proxy");
        _;
    }

    modifier notDelegated() {
        require(address(this) == __self, "UUPSUpgradeable: must not be called through delegatecall");
        _;
    }

    function __UUPSUpgradeable_init() internal onlyInitializing {}

    function proxiableUUID() external view virtual override notDelegated returns (bytes32) {
        return _IMPLEMENTATION_SLOT;
    }

    function upgradeTo(address newImplementation) public virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCall(newImplementation, new bytes(0), false);
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) public payable virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCall(newImplementation, data, true);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual;
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

interface ITokenFactoryV2 {
    function createToken(
        string calldata name,
        string calldata symbol,
        string calldata logoURI,
        string calldata description,
        string calldata category
    ) external payable returns (address tokenAddress, address poolAddress);
    
    function tokenToPool(address token) external view returns (address);
    function isAsterPool(address pool) external view returns (bool);
    function creationFee() external view returns (uint256);
}

interface ILaunchpadPoolV2 {
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
    FIREBALL    // 1 - Same as Snowball, different branding (fire theme)
}

// =============================================================================
// SNOWBALL FACTORY V3 - UPGRADEABLE WITH UUPS
// =============================================================================

/**
 * @title SnowballFactoryV3
 * @notice Creates Snowball/Fireball tokens with auto-buyback & burn mechanics
 * @dev UPGRADEABLE via UUPS Proxy pattern
 * 
 * How it works:
 * 1. User calls createSnowballToken() -> creates token via TokenFactoryV2
 * 2. THIS contract becomes the "creator" and receives 0.5% creator fees
 * 3. Fees accumulate per-pool in pendingBuyback[pool]
 * 4. When threshold is reached, cron job calls batchAutoBuyback()
 * 5. Contract buys tokens from pool and burns them (deflationary!)
 */
contract SnowballFactoryV3 is 
    Initializable, 
    UUPSUpgradeable,
    Ownable2StepUpgradeable, 
    PausableUpgradeable, 
    ReentrancyGuardUpgradeable 
{
    using SafeERC20 for IERC20;
    
    // =============================================================================
    // CONSTANTS
    // =============================================================================
    
    address constant DEAD = 0x000000000000000000000000000000000000dEaD;
    
    // =============================================================================
    // STATE VARIABLES
    // =============================================================================
    
    /// @notice The TokenFactoryV2 contract address
    address public tokenFactory;
    
    /// @notice Minimum tokens to receive from buyback (slippage protection)
    uint256 public minBuybackTokens;
    
    /// @notice Minimum BNB threshold before buyback executes (configurable!)
    uint256 public minBuybackThreshold;
    
    /// @notice Pending BNB for buyback per pool (fair distribution)
    mapping(address => uint256) public pendingBuyback;
    
    /// @notice Real creator address per pool (the user who called createSnowballToken)
    mapping(address => address) public poolToRealCreator;
    
    /// @notice Launch mode per pool (Snowball or Fireball)
    mapping(address => LaunchMode) public poolLaunchMode;
    
    /// @notice Whether a pool was created by this factory
    mapping(address => bool) public isSnowballPool;
    
    /// @notice Token address to pool address mapping
    mapping(address => address) public tokenToPool;
    
    /// @notice All snowball token addresses
    address[] public allSnowballTokens;
    
    /// @notice Stats: Total BNB used for buybacks per pool
    mapping(address => uint256) public totalBuybackBnb;
    
    /// @notice Stats: Total tokens burned per pool
    mapping(address => uint256) public totalTokensBurned;
    
    /// @notice Stats: Global total BNB used for all buybacks
    uint256 public totalBuybacksBnb;
    
    /// @notice Stats: Global total tokens burned
    uint256 public totalTokensBurnedGlobal;
    
    /// @notice Counter for Snowball mode tokens
    uint256 public snowballPoolCount;
    
    /// @notice Counter for Fireball mode tokens
    uint256 public fireballPoolCount;
    
    // =============================================================================
    // EVENTS
    // =============================================================================
    
    event SnowballTokenCreated(
        address indexed token, 
        address indexed pool, 
        address indexed realCreator, 
        LaunchMode mode
    );
    
    event CreatorFeeReceived(
        address indexed pool, 
        uint256 amount, 
        uint256 totalPending
    );
    
    event AutoBuyback(
        address indexed pool, 
        uint256 bnbSpent, 
        uint256 tokensBought, 
        uint256 tokensBurned
    );
    
    event BuybackFailed(
        address indexed pool, 
        uint256 bnbAmount, 
        uint256 minTokens, 
        string reason
    );
    
    event BNBRecovered(address indexed to, uint256 amount);
    event MinBuybackTokensUpdated(uint256 oldValue, uint256 newValue);
    event MinBuybackThresholdUpdated(uint256 oldValue, uint256 newValue);
    event UnknownBNBReceived(address indexed sender, uint256 amount);
    event TokenFactoryUpdated(address indexed oldFactory, address indexed newFactory);
    
    // =============================================================================
    // CONSTRUCTOR & INITIALIZER
    // =============================================================================
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @notice Initialize the contract (called once via proxy)
     * @param _tokenFactory Address of TokenFactoryV2
     * @param _owner Admin/owner address (treasury)
     */
    function initialize(address _tokenFactory, address _owner) public initializer {
        require(_tokenFactory != address(0), "Invalid factory");
        require(_owner != address(0), "Invalid owner");
        
        __Ownable2Step_init(_owner);
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        
        tokenFactory = _tokenFactory;
        minBuybackTokens = 1; // Accept any amount (slippage handled by price impact)
        minBuybackThreshold = 0.01 ether; // 0.01 BNB default (98% efficiency)
    }
    
    // =============================================================================
    // UUPS UPGRADE AUTHORIZATION
    // =============================================================================
    
    /**
     * @notice Only owner can authorize upgrades
     * @param newImplementation Address of new implementation contract
     */
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        require(newImplementation != address(0), "Invalid implementation");
    }
    
    // =============================================================================
    // TOKEN CREATION
    // =============================================================================
    
    /**
     * @notice Create a Snowball or Fireball token
     * @dev Creates token via TokenFactoryV2, THIS contract becomes the "creator"
     *      so all 0.5% creator fees come here for auto-buyback
     * @param name Token name
     * @param symbol Token symbol (ticker)
     * @param logoURI Token logo URL
     * @param description Token description
     * @param category Token category
     * @param mode Launch mode (SNOWBALL or FIREBALL)
     * @return tokenAddr The created token address
     * @return poolAddr The created pool address
     */
    function createSnowballToken(
        string calldata name,
        string calldata symbol,
        string calldata logoURI,
        string calldata description,
        string calldata category,
        LaunchMode mode
    ) external payable nonReentrant whenNotPaused returns (address tokenAddr, address poolAddr) {
        require(msg.value >= ITokenFactoryV2(tokenFactory).creationFee(), "Insufficient creation fee");
        
        // Create token via TokenFactoryV2 - THIS CONTRACT becomes the "creator"
        // TokenFactoryV2 auto-exempts the creator (this contract) in the token
        (tokenAddr, poolAddr) = ITokenFactoryV2(tokenFactory).createToken{value: msg.value}(
            name, symbol, logoURI, description, category
        );
        
        // Track the real creator and pool info
        _registerPool(poolAddr, tokenAddr, msg.sender, mode);
        
        return (tokenAddr, poolAddr);
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
    
    // =============================================================================
    // FEE RECEPTION
    // =============================================================================
    
    /**
     * @notice Receive creator fees from pools
     * @dev When trades happen, the pool sends 0.5% here (since we're the "creator")
     *      We track which pool sent the fee for fair per-pool distribution
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
    
    // =============================================================================
    // BUYBACK FUNCTIONS
    // =============================================================================
    
    /**
     * @notice Process buyback for a specific pool
     * @dev Uses ONLY that pool's accumulated fees (fair distribution)
     * @param pool The pool address (must be created by this factory)
     * @param minTokensOut Minimum tokens to receive (slippage protection)
     */
    function processBuyback(address pool, uint256 minTokensOut) external nonReentrant {
        require(isSnowballPool[pool], "Not a valid snowball pool");
        require(minTokensOut >= minBuybackTokens, "Min tokens too low");
        
        uint256 poolBalance = pendingBuyback[pool];
        require(poolBalance > 0, "No pending buyback for this pool");
        require(poolBalance >= minBuybackThreshold, "Below minimum threshold");
        
        ILaunchpadPoolV2 poolContract = ILaunchpadPoolV2(pool);
        require(!poolContract.graduated(), "Pool graduated");
        require(poolContract.tradingActive(), "Trading not active");
        
        // Clear pending BEFORE external call (reentrancy protection)
        pendingBuyback[pool] = 0;
        
        _executeBuyback(pool, poolBalance, minTokensOut);
    }
    
    /**
     * @notice Auto-process buyback for a pool when it has pending fees
     * @dev Anyone can call this to trigger buybacks (gas paid by caller)
     * @param pool The pool address (must be created by this factory)
     * @param minTokensOut Minimum tokens to receive (slippage protection)
     */
    function autoBuyback(address pool, uint256 minTokensOut) external nonReentrant {
        require(isSnowballPool[pool], "Not a valid snowball pool");
        require(minTokensOut >= minBuybackTokens, "Min tokens too low");
        
        uint256 poolBalance = pendingBuyback[pool];
        if (poolBalance == 0 || poolBalance < minBuybackThreshold) return;
        
        ILaunchpadPoolV2 poolContract = ILaunchpadPoolV2(pool);
        if (poolContract.graduated() || !poolContract.tradingActive()) return;
        
        // Clear pending BEFORE external call (reentrancy protection)
        pendingBuyback[pool] = 0;
        
        _executeBuyback(pool, poolBalance, minTokensOut);
    }
    
    /**
     * @notice Batch process buybacks for multiple pools
     * @dev Called by cron job to process all pools with pending buybacks
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
            
            ILaunchpadPoolV2 poolContract = ILaunchpadPoolV2(pool);
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
        
        ILaunchpadPoolV2 poolContract = ILaunchpadPoolV2(pool);
        address tokenAddr = poolContract.token();
        
        // Buy tokens from the pool - tokens come to THIS contract (we're exempt!)
        try poolContract.buy{value: bnbAmount}(minTokensOut) returns (uint256 tokensBought) {
            require(tokensBought >= minTokensOut, "Slippage exceeded");
            
            if (tokensBought > 0) {
                // Send tokens to dead address (burn)
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
     * @dev Safe version for batch processing - doesn't revert on individual failure
     */
    function _executeBuybackSafe(address pool, uint256 bnbAmount, uint256 minTokensOut) internal {
        if (bnbAmount == 0) return;
        
        ILaunchpadPoolV2 poolContract = ILaunchpadPoolV2(pool);
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
    
    /**
     * @notice Get pool info including buyback stats
     */
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
    
    /**
     * @notice Get global stats
     */
    function getGlobalStats() external view returns (
        uint256 totalSnowballPools,
        uint256 totalFireballPools,
        uint256 totalBnbBuybacks,
        uint256 totalBurned,
        uint256 contractBalance
    ) {
        return (
            snowballPoolCount,
            fireballPoolCount,
            totalBuybacksBnb,
            totalTokensBurnedGlobal,
            address(this).balance
        );
    }
    
    /**
     * @notice Get all pools with pending buybacks above threshold
     * @dev Used by cron job to batch process
     */
    function getPoolsWithPendingBuybacks() external view returns (
        address[] memory pools,
        uint256[] memory amounts
    ) {
        // First pass: count qualifying pools
        uint256 count = 0;
        for (uint256 i = 0; i < allSnowballTokens.length; i++) {
            address pool = tokenToPool[allSnowballTokens[i]];
            if (pendingBuyback[pool] >= minBuybackThreshold) {
                count++;
            }
        }
        
        // Second pass: populate arrays
        pools = new address[](count);
        amounts = new uint256[](count);
        uint256 idx = 0;
        
        for (uint256 i = 0; i < allSnowballTokens.length; i++) {
            address pool = tokenToPool[allSnowballTokens[i]];
            uint256 pending = pendingBuyback[pool];
            if (pending >= minBuybackThreshold) {
                pools[idx] = pool;
                amounts[idx] = pending;
                idx++;
            }
        }
        
        return (pools, amounts);
    }
    
    /**
     * @notice Get all snowball tokens
     */
    function getAllSnowballTokens() external view returns (address[] memory) {
        return allSnowballTokens;
    }
    
    /**
     * @notice Get snowball token count
     */
    function getSnowballTokenCount() external view returns (uint256) {
        return allSnowballTokens.length;
    }
    
    /**
     * @notice Get contract BNB balance
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    /**
     * @notice Get implementation version
     */
    function version() external pure returns (string memory) {
        return "3.0.0";
    }
    
    // =============================================================================
    // ADMIN FUNCTIONS
    // =============================================================================
    
    /**
     * @notice Pause the contract (emergency)
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
     * @notice Update the TokenFactory address (for future upgrades)
     * @param newFactory New TokenFactoryV2 address
     */
    function setTokenFactory(address newFactory) external onlyOwner {
        require(newFactory != address(0), "Invalid factory");
        address oldFactory = tokenFactory;
        tokenFactory = newFactory;
        emit TokenFactoryUpdated(oldFactory, newFactory);
    }
    
    /**
     * @notice Set minimum buyback threshold
     * @dev Allows admin to adjust threshold based on gas costs
     * @param newThreshold New threshold in wei (0.001 - 1 BNB)
     */
    function setMinBuybackThreshold(uint256 newThreshold) external onlyOwner {
        require(newThreshold >= 0.001 ether, "Threshold too low (min 0.001 BNB)");
        require(newThreshold <= 1 ether, "Threshold too high (max 1 BNB)");
        
        uint256 oldThreshold = minBuybackThreshold;
        minBuybackThreshold = newThreshold;
        emit MinBuybackThresholdUpdated(oldThreshold, newThreshold);
    }
    
    /**
     * @notice Set minimum tokens for buyback (slippage)
     * @param newMin New minimum tokens
     */
    function setMinBuybackTokens(uint256 newMin) external onlyOwner {
        uint256 oldMin = minBuybackTokens;
        minBuybackTokens = newMin;
        emit MinBuybackTokensUpdated(oldMin, newMin);
    }
    
    /**
     * @notice Emergency withdraw all BNB
     * @param to Recipient address
     */
    function emergencyWithdraw(address to) external onlyOwner whenPaused {
        require(to != address(0), "Invalid address");
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance");
        (bool ok,) = to.call{value: balance}("");
        require(ok, "Withdraw failed");
    }
    
    /**
     * @notice Emergency withdraw tokens
     * @param token Token address
     * @param to Recipient address
     */
    function emergencyWithdrawToken(address token, address to) external onlyOwner whenPaused {
        require(to != address(0), "Invalid address");
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No balance");
        IERC20(token).safeTransfer(to, balance);
    }
    
    /**
     * @notice Recover specific amount of BNB
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverBNB(address to, uint256 amount) external onlyOwner whenPaused {
        require(to != address(0), "Invalid address");
        require(amount > 0 && amount <= address(this).balance, "Invalid amount");
        (bool ok,) = to.call{value: amount}("");
        require(ok, "Recovery failed");
        emit BNBRecovered(to, amount);
    }
}

// =============================================================================
// ERC1967 PROXY (Deploy this pointing to SnowballFactoryV3)
// =============================================================================

/**
 * @title ERC1967Proxy
 * @notice Minimal proxy contract for UUPS pattern
 * @dev Deploy this with SnowballFactoryV3 implementation address
 */
contract ERC1967Proxy {
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    constructor(address implementation, bytes memory _data) payable {
        require(implementation.code.length > 0, "ERC1967: implementation is not a contract");
        
        assembly {
            sstore(_IMPLEMENTATION_SLOT, implementation)
        }
        
        if (_data.length > 0) {
            (bool success, ) = implementation.delegatecall(_data);
            require(success, "ERC1967Proxy: initialization failed");
        }
    }

    fallback() external payable {
        assembly {
            let implementation := sload(_IMPLEMENTATION_SLOT)
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}
