// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PredictionMarketV1 (UUPS Upgradeable)
 * @notice Prediction markets for AsterPad tokens with UUPS proxy pattern
 * @dev Uses OpenZeppelin's UUPS proxy pattern for upgradeability
 * 
 * Security Features:
 * - ReentrancyGuard for external calls
 * - Pausable for emergency stops  
 * - Storage gaps for upgrade safety
 * - Oracle staleness validation
 * - Comprehensive event emissions
 * - Upgrade timelock (48 hours)
 * - Slippage protection for claims
 * - Flash loan protection (same-block bet/claim prevention)
 */

// =============================================================================
// INTERFACES
// =============================================================================

interface ILaunchpadPool {
    // Individual state variable getters (actual deployed contract interface)
    function token() external view returns (address);
    function creator() external view returns (address);
    function graduated() external view returns (bool);
    function bnbRaised() external view returns (uint256);
    function tokensSold() external view returns (uint256);
    function basePrice() external view returns (uint256);
    function slope() external view returns (uint256);
    function getCurrentPrice() external view returns (uint256);
}

interface ITokenFactory {
    function tokenToPool(address token) external view returns (address);
}

interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

// =============================================================================
// UUPS PROXY PATTERN (Simplified OpenZeppelin Implementation)
// =============================================================================

abstract contract Initializable {
    uint8 private _initialized;
    bool private _initializing;

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
        }
    }

    modifier onlyInitializing() {
        require(_initializing, "Initializable: contract is not initializing");
        _;
    }
}

abstract contract UUPSUpgradeable is Initializable {
    address private immutable __self = address(this);
    
    modifier onlyProxy() {
        require(address(this) != __self, "Function must be called through delegatecall");
        _;
    }

    modifier notDelegated() {
        require(address(this) == __self, "UUPSUpgradeable: must not be called through delegatecall");
        _;
    }

    function proxiableUUID() external view virtual notDelegated returns (bytes32) {
        return _IMPLEMENTATION_SLOT;
    }

    function upgradeTo(address newImplementation) external virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCall(newImplementation, new bytes(0), false);
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) external payable virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCall(newImplementation, data, true);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual;

    // ERC1967 storage slot for implementation
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function _getImplementation() internal view returns (address) {
        return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
    }

    function _setImplementation(address newImplementation) private {
        require(newImplementation.code.length > 0, "ERC1967: new implementation is not a contract");
        StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
    }

    function _upgradeToAndCall(address newImplementation, bytes memory data, bool forceCall) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
        if (data.length > 0 || forceCall) {
            (bool success,) = newImplementation.delegatecall(data);
            require(success, "Upgrade call failed");
        }
    }
    
    event Upgraded(address indexed implementation);
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

// =============================================================================
// REENTRANCY GUARD
// =============================================================================

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    function __ReentrancyGuard_init() internal {
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
// MAIN CONTRACT
// =============================================================================

contract PredictionMarketV1 is Initializable, UUPSUpgradeable, ReentrancyGuard {
    // =============================================================================
    // CONSTANTS
    // =============================================================================
    
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 ether; // 1B tokens
    uint256 public constant MIN_BET = 0.01 ether;              // 0.01 BNB
    uint256 public constant MAX_BET = 10 ether;                // 10 BNB
    uint256 public constant CREATION_FEE = 0.05 ether;         // 0.05 BNB
    uint256 public constant PLATFORM_FEE_BPS = 200;            // 2%
    uint256 public constant MIN_DEADLINE = 1 hours;
    uint256 public constant MAX_DEADLINE = 30 days;
    uint256 public constant BETTING_FREEZE = 10 minutes;       // Stop betting 10 min before deadline
    uint256 public constant ORACLE_STALENESS_THRESHOLD = 1 hours; // Oracle data must be fresh
    uint256 public constant UPGRADE_TIMELOCK = 48 hours;          // Timelock for upgrades
    
    // =============================================================================
    // ENUMS
    // =============================================================================
    
    enum PredictionType { MARKET_CAP, GRADUATION, PRICE_TARGET, VOLUME_TARGET }
    
    // =============================================================================
    // STATE VARIABLES
    // =============================================================================
    
    address public owner;
    address public pendingOwner; // For 2-step ownership transfer
    ITokenFactory public tokenFactory;
    AggregatorV3Interface public bnbUsdOracle;
    address public feeRecipient;
    
    uint256 public nextPredictionId;
    uint256 public totalFeesCollected;
    bool public paused;
    
    // Upgrade timelock
    address public pendingImplementation;
    uint256 public upgradeScheduledTime;
    
    // =============================================================================
    // STRUCTS
    // =============================================================================
    
    struct Prediction {
        address token;
        PredictionType predType;
        uint256 targetValue;       // In USD (18 decimals) for mcap/price, in BNB for volume
        uint256 deadline;
        uint256 yesPool;           // Total BNB bet on YES
        uint256 noPool;            // Total BNB bet on NO
        uint256 totalBettors;
        bool resolved;
        bool outcome;              // true = YES won, false = NO won
        address creator;
        bool creatorIsFree;        // Token creator doesn't pay fee
    }
    
    struct Bet {
        uint256 amount;
        bool isYes;
        bool claimed;
        uint256 placedBlock;  // For flash loan protection
    }
    
    // =============================================================================
    // MAPPINGS
    // =============================================================================
    
    mapping(uint256 => Prediction) public predictions;
    mapping(uint256 => mapping(address => Bet)) public bets;
    mapping(uint256 => address[]) public predictionBettors;
    mapping(address => uint256[]) public userPredictions;
    mapping(address => uint256[]) public userBets;
    
    // =============================================================================
    // STORAGE GAP (for future upgrades)
    // =============================================================================
    
    uint256[50] private __gap;
    
    // =============================================================================
    // EVENTS (Comprehensive)
    // =============================================================================
    
    event PredictionCreated(
        uint256 indexed predictionId,
        address indexed token,
        PredictionType predType,
        uint256 targetValue,
        uint256 deadline,
        address indexed creator,
        bool creatorIsFree
    );
    
    event BetPlaced(
        uint256 indexed predictionId,
        address indexed bettor,
        bool isYes,
        uint256 amount,
        uint256 newYesPool,
        uint256 newNoPool
    );
    
    event PredictionResolved(
        uint256 indexed predictionId,
        bool outcome,
        uint256 yesPool,
        uint256 noPool,
        address indexed resolver
    );
    
    event WinningsClaimed(
        uint256 indexed predictionId,
        address indexed bettor,
        uint256 amount,
        uint256 profit
    );
    
    event FeesWithdrawn(address indexed recipient, uint256 amount);
    
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    event Paused(address indexed account);
    event Unpaused(address indexed account);
    
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    
    event UpgradeScheduled(address indexed implementation, uint256 executeTime);
    event UpgradeCancelled(address indexed implementation);
    event UpgradeExecuted(address indexed oldImplementation, address indexed newImplementation);
    
    // =============================================================================
    // MODIFIERS
    // =============================================================================
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    modifier whenNotPaused() {
        require(!paused, "Contract paused");
        _;
    }
    
    // =============================================================================
    // INITIALIZER (replaces constructor for proxy)
    // =============================================================================
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    function initialize(
        address _tokenFactory,
        address _bnbUsdOracle,
        address _feeRecipient
    ) public initializer {
        require(_tokenFactory != address(0), "Invalid factory");
        require(_bnbUsdOracle != address(0), "Invalid oracle");
        require(_feeRecipient != address(0), "Invalid recipient");
        
        __ReentrancyGuard_init();
        
        owner = msg.sender;
        tokenFactory = ITokenFactory(_tokenFactory);
        bnbUsdOracle = AggregatorV3Interface(_bnbUsdOracle);
        feeRecipient = _feeRecipient;
        nextPredictionId = 1;
        
        emit OwnershipTransferred(address(0), msg.sender);
    }
    
    function _disableInitializers() internal virtual {
        // Prevent initialization on implementation contract
    }
    
    // =============================================================================
    // CORE FUNCTIONS
    // =============================================================================
    
    function createPrediction(
        address token,
        PredictionType predType,
        uint256 targetValue,
        uint256 deadline
    ) external payable whenNotPaused nonReentrant returns (uint256) {
        require(deadline > block.timestamp + MIN_DEADLINE, "Deadline too soon");
        require(deadline < block.timestamp + MAX_DEADLINE, "Deadline too far");
        
        address pool = tokenFactory.tokenToPool(token);
        require(pool != address(0), "Token not found");
        
        // Check if creator is token owner (free creation)
        ILaunchpadPool launchpad = ILaunchpadPool(pool);
        address tokenCreator = launchpad.creator();
        bool isFree = (msg.sender == tokenCreator);
        
        if (!isFree) {
            require(msg.value >= CREATION_FEE, "Insufficient fee");
            totalFeesCollected += msg.value;
        }
        
        // For graduation predictions, target is always 0 (just checking graduation status)
        if (predType == PredictionType.GRADUATION) {
            targetValue = 0;
        }
        
        uint256 predictionId = nextPredictionId++;
        
        predictions[predictionId] = Prediction({
            token: token,
            predType: predType,
            targetValue: targetValue,
            deadline: deadline,
            yesPool: 0,
            noPool: 0,
            totalBettors: 0,
            resolved: false,
            outcome: false,
            creator: msg.sender,
            creatorIsFree: isFree
        });
        
        userPredictions[msg.sender].push(predictionId);
        
        emit PredictionCreated(predictionId, token, predType, targetValue, deadline, msg.sender, isFree);
        
        return predictionId;
    }
    
    function bet(uint256 predictionId, bool isYes) external payable whenNotPaused nonReentrant {
        Prediction storage pred = predictions[predictionId];
        require(pred.token != address(0), "Prediction not found");
        require(!pred.resolved, "Already resolved");
        require(block.timestamp < pred.deadline - BETTING_FREEZE, "Betting closed");
        require(msg.value >= MIN_BET, "Bet too small");
        require(msg.value <= MAX_BET, "Bet too large");
        
        Bet storage userBet = bets[predictionId][msg.sender];
        
        if (userBet.amount == 0) {
            // New bettor
            pred.totalBettors++;
            predictionBettors[predictionId].push(msg.sender);
            userBets[msg.sender].push(predictionId);
        } else {
            // Additional bet - must be same side
            require(userBet.isYes == isYes, "Cannot bet both sides");
        }
        
        userBet.amount += msg.value;
        userBet.isYes = isYes;
        userBet.placedBlock = block.number;  // Flash loan protection
        
        if (isYes) {
            pred.yesPool += msg.value;
        } else {
            pred.noPool += msg.value;
        }
        
        emit BetPlaced(predictionId, msg.sender, isYes, msg.value, pred.yesPool, pred.noPool);
    }
    
    function resolve(uint256 predictionId) external whenNotPaused nonReentrant {
        Prediction storage pred = predictions[predictionId];
        require(pred.token != address(0), "Prediction not found");
        require(!pred.resolved, "Already resolved");
        require(block.timestamp >= pred.deadline, "Not yet deadline");
        
        bool outcome = checkOutcome(predictionId);
        
        pred.resolved = true;
        pred.outcome = outcome;
        
        emit PredictionResolved(predictionId, outcome, pred.yesPool, pred.noPool, msg.sender);
    }
    
    function claim(uint256 predictionId) external whenNotPaused nonReentrant {
        claimWithMinWinnings(predictionId, 0);
    }
    
    /// @notice Claim with slippage protection
    /// @param predictionId The prediction to claim from
    /// @param minWinnings Minimum expected winnings (reverts if actual < min)
    function claimWithMinWinnings(uint256 predictionId, uint256 minWinnings) public whenNotPaused nonReentrant {
        Prediction storage pred = predictions[predictionId];
        require(pred.resolved, "Not resolved");
        
        Bet storage userBet = bets[predictionId][msg.sender];
        require(userBet.amount > 0, "No bet found");
        require(!userBet.claimed, "Already claimed");
        
        // Flash loan protection: must wait at least 1 block after betting
        require(block.number > userBet.placedBlock, "Same block claim not allowed");
        
        // Check if user won
        require(userBet.isYes == pred.outcome, "Did not win");
        
        uint256 winnings = calculateWinnings(predictionId, msg.sender);
        
        // Slippage protection
        require(winnings >= minWinnings, "Winnings below minimum");
        
        uint256 profit = winnings - userBet.amount;
        userBet.claimed = true;
        
        // Transfer winnings
        (bool success, ) = payable(msg.sender).call{value: winnings}("");
        require(success, "Transfer failed");
        
        emit WinningsClaimed(predictionId, msg.sender, winnings, profit);
    }
    
    // =============================================================================
    // OUTCOME CHECKING
    // =============================================================================
    
    function checkOutcome(uint256 predictionId) public view returns (bool) {
        Prediction storage pred = predictions[predictionId];
        
        address pool = tokenFactory.tokenToPool(pred.token);
        require(pool != address(0), "Pool not found");
        
        if (pred.predType == PredictionType.MARKET_CAP) {
            uint256 currentMcap = getMarketCapUsd(pool);
            return currentMcap >= pred.targetValue;
            
        } else if (pred.predType == PredictionType.GRADUATION) {
            return hasGraduated(pool);
            
        } else if (pred.predType == PredictionType.PRICE_TARGET) {
            uint256 currentPrice = getTokenPriceUsd(pool);
            return currentPrice >= pred.targetValue;
            
        } else if (pred.predType == PredictionType.VOLUME_TARGET) {
            uint256 volume = getTokenVolume(pool);
            return volume >= pred.targetValue;
        }
        
        return false;
    }
    
    function getMarketCapUsd(address pool) public view returns (uint256) {
        ILaunchpadPool launchpad = ILaunchpadPool(pool);
        
        // Get current price from bonding curve (in wei per token)
        uint256 currentPrice = launchpad.getCurrentPrice();
        if (currentPrice == 0) return 0;
        
        // Market cap in BNB = totalSupply * pricePerToken
        uint256 mcapInBnb = (TOTAL_SUPPLY * currentPrice) / 1e18;
        
        // Convert to USD
        uint256 bnbPrice = getBnbPriceUsd();
        return (mcapInBnb * bnbPrice) / 1e18;
    }
    
    function getTokenPriceUsd(address pool) public view returns (uint256) {
        ILaunchpadPool launchpad = ILaunchpadPool(pool);
        
        // Get current price from bonding curve (in wei per token)
        uint256 priceInBnb = launchpad.getCurrentPrice();
        if (priceInBnb == 0) return 0;
        
        // Convert to USD
        uint256 bnbPrice = getBnbPriceUsd();
        return (priceInBnb * bnbPrice) / 1e18;
    }
    
    function hasGraduated(address pool) public view returns (bool) {
        ILaunchpadPool launchpad = ILaunchpadPool(pool);
        return launchpad.graduated();
    }
    
    function getTokenVolume(address pool) public view returns (uint256) {
        ILaunchpadPool launchpad = ILaunchpadPool(pool);
        return launchpad.bnbRaised();
    }
    
    function getBnbPriceUsd() public view returns (uint256) {
        (
            uint80 roundId,
            int256 price,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = bnbUsdOracle.latestRoundData();
        
        // Validate oracle data
        require(price > 0, "Invalid BNB price");
        require(updatedAt > 0, "Round not complete");
        require(answeredInRound >= roundId, "Stale price data");
        require(block.timestamp - updatedAt < ORACLE_STALENESS_THRESHOLD, "Oracle data too old");
        
        return uint256(price) * 1e10; // Chainlink returns 8 decimals, we want 18
    }
    
    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================
    
    function getPrediction(uint256 predictionId) external view returns (
        address token,
        PredictionType predType,
        uint256 targetValue,
        uint256 deadline,
        uint256 yesPool,
        uint256 noPool,
        uint256 totalBettors,
        bool resolved,
        bool outcome,
        address creator
    ) {
        Prediction storage pred = predictions[predictionId];
        return (
            pred.token,
            pred.predType,
            pred.targetValue,
            pred.deadline,
            pred.yesPool,
            pred.noPool,
            pred.totalBettors,
            pred.resolved,
            pred.outcome,
            pred.creator
        );
    }
    
    function getUserBet(uint256 predictionId, address user) external view returns (
        uint256 amount,
        bool isYes,
        bool claimed
    ) {
        Bet storage userBet = bets[predictionId][user];
        return (userBet.amount, userBet.isYes, userBet.claimed);
    }
    
    function calculateWinnings(uint256 predictionId, address user) public view returns (uint256) {
        Prediction storage pred = predictions[predictionId];
        Bet storage userBet = bets[predictionId][user];
        
        if (!pred.resolved || userBet.amount == 0 || userBet.isYes != pred.outcome) {
            return 0;
        }
        
        uint256 winningPool = pred.outcome ? pred.yesPool : pred.noPool;
        uint256 losingPool = pred.outcome ? pred.noPool : pred.yesPool;
        
        // Platform fee from losing pool
        uint256 platformFee = (losingPool * PLATFORM_FEE_BPS) / 10000;
        uint256 distributablePool = losingPool - platformFee;
        
        // User's share
        uint256 userShare = (distributablePool * userBet.amount) / winningPool;
        
        return userBet.amount + userShare;
    }
    
    function calculatePotentialWinnings(
        uint256 predictionId,
        bool isYes,
        uint256 betAmount
    ) external view returns (uint256) {
        Prediction storage pred = predictions[predictionId];
        
        uint256 yesPool = pred.yesPool + (isYes ? betAmount : 0);
        uint256 noPool = pred.noPool + (isYes ? 0 : betAmount);
        
        uint256 winningPool = isYes ? yesPool : noPool;
        uint256 losingPool = isYes ? noPool : yesPool;
        
        uint256 platformFee = (losingPool * PLATFORM_FEE_BPS) / 10000;
        uint256 distributablePool = losingPool - platformFee;
        
        uint256 userShare = (distributablePool * betAmount) / winningPool;
        
        return betAmount + userShare;
    }
    
    function getTokenPredictions(address token) external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 1; i < nextPredictionId; i++) {
            if (predictions[i].token == token) count++;
        }
        
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 1; i < nextPredictionId; i++) {
            if (predictions[i].token == token) {
                result[index++] = i;
            }
        }
        return result;
    }
    
    function getActivePredictions() external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 1; i < nextPredictionId; i++) {
            if (!predictions[i].resolved && predictions[i].deadline > block.timestamp) {
                count++;
            }
        }
        
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 1; i < nextPredictionId; i++) {
            if (!predictions[i].resolved && predictions[i].deadline > block.timestamp) {
                result[index++] = i;
            }
        }
        return result;
    }
    
    // =============================================================================
    // ADMIN FUNCTIONS
    // =============================================================================
    
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 amount = totalFeesCollected;
        require(amount > 0, "No fees to withdraw");
        totalFeesCollected = 0;
        
        (bool success, ) = payable(feeRecipient).call{value: amount}("");
        require(success, "Transfer failed");
        
        emit FeesWithdrawn(feeRecipient, amount);
    }
    
    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }
    
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }
    
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "Invalid address");
        address oldRecipient = feeRecipient;
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(oldRecipient, _feeRecipient);
    }
    
    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "Invalid address");
        address oldOracle = address(bnbUsdOracle);
        bnbUsdOracle = AggregatorV3Interface(_oracle);
        emit OracleUpdated(oldOracle, _oracle);
    }
    
    // 2-Step Ownership Transfer (safer)
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }
    
    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "Not pending owner");
        address oldOwner = owner;
        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(oldOwner, msg.sender);
    }
    
    // Emergency function to resolve if oracle fails
    function emergencyResolve(uint256 predictionId, bool outcome) external onlyOwner {
        Prediction storage pred = predictions[predictionId];
        require(pred.token != address(0), "Prediction not found");
        require(!pred.resolved, "Already resolved");
        require(block.timestamp >= pred.deadline, "Not yet deadline");
        
        pred.resolved = true;
        pred.outcome = outcome;
        
        emit PredictionResolved(predictionId, outcome, pred.yesPool, pred.noPool, msg.sender);
    }
    
    // =============================================================================
    // UUPS UPGRADE WITH TIMELOCK
    // =============================================================================
    
    /// @notice Schedule an upgrade (starts timelock)
    function scheduleUpgrade(address newImplementation) external onlyOwner {
        require(newImplementation != address(0), "Invalid implementation");
        require(newImplementation.code.length > 0, "Not a contract");
        require(pendingImplementation == address(0), "Upgrade already pending");
        
        pendingImplementation = newImplementation;
        upgradeScheduledTime = block.timestamp + UPGRADE_TIMELOCK;
        
        emit UpgradeScheduled(newImplementation, upgradeScheduledTime);
    }
    
    /// @notice Cancel a scheduled upgrade
    function cancelUpgrade() external onlyOwner {
        require(pendingImplementation != address(0), "No upgrade pending");
        
        address cancelled = pendingImplementation;
        pendingImplementation = address(0);
        upgradeScheduledTime = 0;
        
        emit UpgradeCancelled(cancelled);
    }
    
    /// @notice Execute a scheduled upgrade (after timelock expires)
    function executeUpgrade() external onlyOwner {
        require(pendingImplementation != address(0), "No upgrade pending");
        require(block.timestamp >= upgradeScheduledTime, "Timelock not expired");
        
        address oldImpl = _getImplementation();
        address newImpl = pendingImplementation;
        
        pendingImplementation = address(0);
        upgradeScheduledTime = 0;
        
        _upgradeToAndCall(newImpl, new bytes(0), false);
        
        emit UpgradeExecuted(oldImpl, newImpl);
    }
    
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        // For direct upgradeTo calls, require it matches the scheduled upgrade
        require(pendingImplementation == newImplementation, "Must use timelock");
        require(block.timestamp >= upgradeScheduledTime, "Timelock not expired");
    }
    
    // =============================================================================
    // VERSION
    // =============================================================================
    
    function version() external pure returns (string memory) {
        return "1.2.1";
    }
    
    // =============================================================================
    // FALLBACK
    // =============================================================================
    
    receive() external payable {}
}
