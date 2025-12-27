// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * ASTERPAD TOKEN FACTORY V2 - OPTIMIZED FOR SIZE
 * 
 * KEY FIX: Creator address is auto-exempt from trading restrictions
 * This allows SnowballFactory to transfer tokens for buyback & burn
 * 
 * UPGRADEABLE: Uses UUPS Proxy pattern for future updates
 * Compatible with: SnowballFactory V3
 * Network: BSC Mainnet
 */

// =============================================================================
// MINIMAL UPGRADEABLE INFRASTRUCTURE
// =============================================================================

abstract contract Initializable {
    uint8 private _initialized;
    bool private _initializing;

    modifier initializer() {
        require(!_initializing && _initialized < 1, "Already initialized");
        _initialized = 1;
        _initializing = true;
        _;
        _initializing = false;
    }

    function _disableInitializers() internal virtual {
        require(!_initializing, "Initializing");
        _initialized = type(uint8).max;
    }
}

abstract contract OwnableUpgradeable is Initializable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function __Ownable_init(address initialOwner) internal {
        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "Not owner");
        _;
    }

    function owner() public view returns (address) { return _owner; }
    
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract PausableUpgradeable is Initializable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);

    function __Pausable_init() internal { _paused = false; }
    modifier whenNotPaused() { require(!_paused, "Paused"); _; }
    modifier whenPaused() { require(_paused, "Not paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function _pause() internal { _paused = true; emit Paused(msg.sender); }
    function _unpause() internal { _paused = false; emit Unpaused(msg.sender); }
}

abstract contract ReentrancyGuardUpgradeable is Initializable {
    uint256 private _status;
    function __ReentrancyGuard_init() internal { _status = 1; }
    modifier nonReentrant() {
        require(_status != 2, "Reentrant");
        _status = 2;
        _;
        _status = 1;
    }
}

// =============================================================================
// UUPS UPGRADE MECHANISM (MINIMAL)
// =============================================================================

abstract contract UUPSUpgradeable is Initializable {
    bytes32 internal constant _IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    address private immutable __self = address(this);
    
    event Upgraded(address indexed implementation);

    function __UUPSUpgradeable_init() internal {}

    function proxiableUUID() external view returns (bytes32) {
        require(address(this) == __self, "Must not delegatecall");
        return _IMPL_SLOT;
    }

    function upgradeTo(address newImpl) public virtual {
        require(address(this) != __self, "Must delegatecall");
        _authorizeUpgrade(newImpl);
        assembly { sstore(_IMPL_SLOT, newImpl) }
        emit Upgraded(newImpl);
    }

    function _authorizeUpgrade(address) internal virtual;
}

// =============================================================================
// ERC20 (MINIMAL)
// =============================================================================

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function allowance(address, address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

contract ERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view returns (string memory) { return _name; }
    function symbol() public view returns (string memory) { return _symbol; }
    function decimals() public pure returns (uint8) { return 18; }
    function totalSupply() public view returns (uint256) { return _totalSupply; }
    function balanceOf(address account) public view returns (uint256) { return _balances[account]; }

    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "Allowance exceeded");
            _allowances[from][msg.sender] = currentAllowance - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal virtual {
        require(from != address(0) && to != address(0), "Zero address");
        _beforeTokenTransfer(from, to, amount);
        require(_balances[from] >= amount, "Balance exceeded");
        unchecked { _balances[from] -= amount; _balances[to] += amount; }
        emit Transfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "Zero address");
        _beforeTokenTransfer(address(0), account, amount);
        _totalSupply += amount;
        unchecked { _balances[account] += amount; }
        emit Transfer(address(0), account, amount);
    }

    function _beforeTokenTransfer(address, address, uint256) internal virtual {}
}

// =============================================================================
// PANCAKESWAP INTERFACES
// =============================================================================

interface IPancakeRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidityETH(address, uint, uint, uint, address, uint) external payable returns (uint, uint, uint);
}

interface IPancakeFactory {
    function getPair(address, address) external view returns (address);
}

// =============================================================================
// ASTER TOKEN V2
// =============================================================================

contract AsterTokenV2 is ERC20 {
    string public logoURI;
    string public description;
    address public immutable creator;
    address public immutable pool;
    bool public tradingEnabled;
    mapping(address => bool) public isExempt;
    
    event TradingEnabled();

    constructor(
        string memory _name, string memory _symbol, string memory _logoURI, string memory _desc,
        uint256 _supply, address _creator, address _pool
    ) ERC20(_name, _symbol) {
        logoURI = _logoURI;
        description = _desc;
        creator = _creator;
        pool = _pool;
        isExempt[_creator] = true; // V2 FIX: Auto-exempt creator
        _mint(_pool, _supply);
    }
    
    function _beforeTokenTransfer(address from, address to, uint256) internal view override {
        if (from != pool && to != pool && from != address(0)) {
            require(tradingEnabled || isExempt[from] || isExempt[to], "Trading disabled");
        }
    }
    
    function enableTrading() external {
        require(msg.sender == pool, "Only pool");
        tradingEnabled = true;
        emit TradingEnabled();
    }
    
    function setExempt(address account, bool exempt) external {
        require(msg.sender == pool, "Only pool");
        isExempt[account] = exempt;
    }
}

// =============================================================================
// LAUNCHPAD POOL V2
// =============================================================================

contract LaunchpadPoolV2 {
    address constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address constant ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    
    AsterTokenV2 public token;
    address public immutable factory;
    address public creator;
    
    uint256 public basePrice;
    uint256 public slope;
    uint256 public tokensSold;
    uint256 public bnbRaised;
    uint256 public tokensOnCurve;
    uint256 public tokensForLP;
    uint256 public graduationThreshold;
    
    bool public graduated;
    bool public tradingActive;
    bool private _init;
    address public lpPair;
    
    mapping(address => uint256) public lastBlock;
    
    event TokensBought(address indexed buyer, uint256 bnb, uint256 tokens, uint256 price);
    event TokensSold(address indexed seller, uint256 tokens, uint256 bnb, uint256 price);
    event Graduated(address indexed token, address lpPair);

    constructor() { factory = msg.sender; }
    
    function initialize(address t, address c, uint256 bp, uint256 s, uint256 gt, uint256 oc, uint256 lp) external {
        require(msg.sender == factory && !_init, "Init error");
        _init = true;
        token = AsterTokenV2(t);
        creator = c;
        basePrice = bp;
        slope = s;
        graduationThreshold = gt;
        tokensOnCurve = oc;
        tokensForLP = lp;
        tradingActive = true;
    }
    
    function buy(uint256 minTokens) external payable returns (uint256) {
        require(msg.value > 0 && msg.value <= 10 ether && tradingActive && !graduated, "Buy error");
        require(block.number > lastBlock[msg.sender], "Wait");
        lastBlock[msg.sender] = block.number;
        
        uint256 platformFee = msg.value / 100; // 1%
        uint256 creatorFee = msg.value / 200;  // 0.5%
        uint256 netBnb = msg.value - platformFee - creatorFee;
        
        uint256 tokens = _calcTokens(netBnb);
        require(tokens >= minTokens && tokensSold + tokens <= tokensOnCurve, "Slippage");
        
        tokensSold += tokens;
        bnbRaised += netBnb;
        
        IERC20(address(token)).transfer(msg.sender, tokens);
        _send(factory, platformFee);
        _send(creator, creatorFee);
        
        emit TokensBought(msg.sender, msg.value, tokens, getCurrentPrice());
        
        if (bnbRaised >= graduationThreshold) _graduate();
        return tokens;
    }
    
    function sell(uint256 tokens, uint256 minBnb) external returns (uint256) {
        require(tokens > 0 && tokens <= tokensSold && tradingActive && !graduated, "Sell error");
        require(block.number > lastBlock[msg.sender], "Wait");
        lastBlock[msg.sender] = block.number;
        
        uint256 grossBnb = _calcBnb(tokens);
        uint256 platformFee = grossBnb / 100;
        uint256 creatorFee = grossBnb / 200;
        uint256 netBnb = grossBnb - platformFee - creatorFee;
        require(netBnb >= minBnb, "Slippage");
        
        tokensSold -= tokens;
        bnbRaised -= grossBnb;
        
        IERC20(address(token)).transferFrom(msg.sender, address(this), tokens);
        _send(factory, platformFee);
        _send(creator, creatorFee);
        _send(msg.sender, netBnb);
        
        emit TokensSold(msg.sender, tokens, netBnb, getCurrentPrice());
        return netBnb;
    }
    
    function getCurrentPrice() public view returns (uint256) {
        return basePrice + (tokensSold * slope / 1e18);
    }
    
    function _calcTokens(uint256 bnb) internal view returns (uint256) {
        uint256 price = basePrice + (tokensSold * slope / 1e18);
        uint256 est = bnb * 1e18 / price;
        uint256 avg = basePrice + ((tokensSold + est / 2) * slope / 1e18);
        return bnb * 1e18 / avg;
    }
    
    function _calcBnb(uint256 tokens) internal view returns (uint256) {
        uint256 newSold = tokensSold - tokens;
        uint256 avg = basePrice + ((tokensSold + newSold) * slope / (2 * 1e18));
        return tokens * avg / 1e18;
    }
    
    function _send(address to, uint256 amt) internal {
        (bool ok,) = to.call{value: amt}("");
        require(ok, "Send failed");
    }
    
    function _graduate() internal {
        graduated = true;
        tradingActive = false;
        token.enableTrading();
        
        uint256 bal = address(this).balance;
        uint256 fee = bal / 50; // 2%
        _send(factory, fee);
        
        uint256 liq = bal - fee;
        uint256 tBal = token.balanceOf(address(this));
        uint256 tLP = tBal < tokensForLP ? tBal : tokensForLP;
        
        IERC20(address(token)).approve(ROUTER, tLP);
        IPancakeRouter r = IPancakeRouter(ROUTER);
        
        try r.addLiquidityETH{value: liq}(address(token), tLP, 0, 0, address(this), block.timestamp + 300) {
            lpPair = IPancakeFactory(r.factory()).getPair(address(token), r.WETH());
            IERC20(lpPair).transfer(DEAD, IERC20(lpPair).balanceOf(address(this)));
            token.setExempt(lpPair, true);
            uint256 rem = token.balanceOf(address(this));
            if (rem > 0) IERC20(address(token)).transfer(DEAD, rem);
            emit Graduated(address(token), lpPair);
        } catch {
            tradingActive = true;
            graduated = false;
        }
    }
    
    receive() external payable {}
}

// =============================================================================
// TOKEN FACTORY V2 - MAIN CONTRACT
// =============================================================================

contract TokenFactoryV2 is Initializable, UUPSUpgradeable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    address public feeRecipient;
    uint256 public creationFee;
    uint256 public defaultBasePrice;
    uint256 public defaultSlope;
    uint256 public defaultGraduationThreshold;
    uint256 public defaultTotalSupply;
    
    uint256 constant TOKENS_ON_CURVE_BP = 8000;
    uint256 constant TOKENS_FOR_LP_BP = 2000;
    
    address[] public allTokens;
    mapping(address => address) public tokenToPool;
    mapping(address => bool) public isAsterToken;
    mapping(address => bool) public isAsterPool;
    
    uint256 public totalTokensCreated;
    
    event TokenCreated(address indexed token, address indexed pool, address indexed creator);

    constructor() { _disableInitializers(); }
    
    function initialize(address feeRecipient_, address owner_) public initializer {
        require(feeRecipient_ != address(0) && owner_ != address(0), "Zero address");
        __Ownable_init(owner_);
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        
        feeRecipient = feeRecipient_;
        creationFee = 0.01 ether;
        defaultBasePrice = 0.000000007142857142 ether;
        defaultSlope = 400;
        defaultGraduationThreshold = 24 ether;
        defaultTotalSupply = 1_000_000_000 * 1e18;
    }
    
    function _authorizeUpgrade(address) internal view override onlyOwner {}
    
    function createToken(
        string calldata name, string calldata symbol, string calldata logoURI, string calldata description, string calldata
    ) external payable nonReentrant whenNotPaused returns (address tokenAddress, address poolAddress) {
        require(msg.value >= creationFee, "Fee");
        
        uint256 onCurve = defaultTotalSupply * TOKENS_ON_CURVE_BP / 10000;
        uint256 forLP = defaultTotalSupply * TOKENS_FOR_LP_BP / 10000;
        
        LaunchpadPoolV2 pool = new LaunchpadPoolV2();
        poolAddress = address(pool);
        
        AsterTokenV2 token = new AsterTokenV2(name, symbol, logoURI, description, defaultTotalSupply, msg.sender, poolAddress);
        tokenAddress = address(token);
        
        pool.initialize(tokenAddress, msg.sender, defaultBasePrice, defaultSlope, defaultGraduationThreshold, onCurve, forLP);
        
        allTokens.push(tokenAddress);
        tokenToPool[tokenAddress] = poolAddress;
        isAsterToken[tokenAddress] = true;
        isAsterPool[poolAddress] = true;
        totalTokensCreated++;
        
        if (msg.value > 0) {
            (bool ok,) = feeRecipient.call{value: msg.value}("");
            require(ok, "Fee transfer failed");
        }
        
        emit TokenCreated(tokenAddress, poolAddress, msg.sender);
    }
    
    function getAllTokens() external view returns (address[] memory) { return allTokens; }
    function getTokenCount() external view returns (uint256) { return allTokens.length; }
    function version() external pure returns (string memory) { return "2.0.0"; }
    
    function setCreationFee(uint256 f) external onlyOwner { creationFee = f; }
    function setFeeRecipient(address r) external onlyOwner { feeRecipient = r; }
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
    
    receive() external payable {}
}

// =============================================================================
// ERC1967 PROXY
// =============================================================================

contract ERC1967Proxy {
    bytes32 constant _IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    constructor(address impl, bytes memory data) payable {
        require(impl.code.length > 0, "Not contract");
        assembly { sstore(_IMPL_SLOT, impl) }
        if (data.length > 0) {
            (bool ok,) = impl.delegatecall(data);
            require(ok, "Init failed");
        }
    }

    fallback() external payable {
        assembly {
            let impl := sload(_IMPL_SLOT)
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result case 0 { revert(0, returndatasize()) } default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}
