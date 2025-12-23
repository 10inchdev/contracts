// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * ASTERPAD V2 - BSC Token Launchpad (OPTIMIZED)
 * 
 * Deploy TokenFactory with: 0x3717E1A8E2788Ac53D2D5084Dc6FF93d03369D27
 */

// Minimal Context
abstract contract Context {
    function _msgSender() internal view virtual returns (address) { return msg.sender; }
}

// Minimal Ownable
abstract contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    constructor() { _transferOwnership(_msgSender()); }
    modifier onlyOwner() { require(owner() == _msgSender(), "Not owner"); _; }
    function owner() public view virtual returns (address) { return _owner; }
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Zero address");
        _transferOwnership(newOwner);
    }
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

// Ownable2Step
abstract contract Ownable2Step is Ownable {
    address private _pendingOwner;
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    function pendingOwner() public view virtual returns (address) { return _pendingOwner; }
    function transferOwnership(address newOwner) public virtual override onlyOwner {
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner(), newOwner);
    }
    function _transferOwnership(address newOwner) internal virtual override {
        delete _pendingOwner;
        super._transferOwnership(newOwner);
    }
    function acceptOwnership() public virtual {
        require(pendingOwner() == _msgSender(), "Not pending owner");
        _transferOwnership(_msgSender());
    }
}

// Minimal Pausable
abstract contract Pausable is Context {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    constructor() { _paused = false; }
    modifier whenNotPaused() { require(!_paused, "Paused"); _; }
    modifier whenPaused() { require(_paused, "Not paused"); _; }
    function paused() public view virtual returns (bool) { return _paused; }
    function _pause() internal virtual whenNotPaused { _paused = true; emit Paused(_msgSender()); }
    function _unpause() internal virtual whenPaused { _paused = false; emit Unpaused(_msgSender()); }
}

// Minimal ReentrancyGuard
abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;
    constructor() { _status = _NOT_ENTERED; }
    modifier nonReentrant() {
        require(_status != _ENTERED, "Reentrant");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

// Minimal IERC20
interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// Minimal ERC20
contract ERC20 is Context, IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) { _name = name_; _symbol = symbol_; }
    function name() public view virtual returns (string memory) { return _name; }
    function symbol() public view virtual returns (string memory) { return _symbol; }
    function decimals() public view virtual returns (uint8) { return 18; }
    function totalSupply() public view virtual override returns (uint256) { return _totalSupply; }
    function balanceOf(address account) public view virtual override returns (uint256) { return _balances[account]; }
    
    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), to, amount);
        return true;
    }
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }
    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        _spendAllowance(from, _msgSender(), amount);
        _transfer(from, to, amount);
        return true;
    }
    function _transfer(address from, address to, uint256 amount) internal virtual {
        require(from != address(0) && to != address(0), "Zero address");
        _beforeTokenTransfer(from, to, amount);
        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "Exceeds balance");
        unchecked { _balances[from] = fromBalance - amount; _balances[to] += amount; }
        emit Transfer(from, to, amount);
    }
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "Zero address");
        _totalSupply += amount;
        unchecked { _balances[account] += amount; }
        emit Transfer(address(0), account, amount);
    }
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0) && spender != address(0), "Zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
    function _spendAllowance(address owner, address spender, uint256 amount) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "Insufficient allowance");
            unchecked { _approve(owner, spender, currentAllowance - amount); }
        }
    }
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual {}
}

// Minimal SafeERC20
library SafeERC20 {
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        (bool success, bytes memory data) = address(token).call(abi.encodeWithSelector(token.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Transfer failed");
    }
    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        (bool success, bytes memory data) = address(token).call(abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TransferFrom failed");
    }
}

// PancakeSwap
interface IPancakeRouter02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidityETH(address token, uint256 amountTokenDesired, uint256 amountTokenMin, uint256 amountETHMin, address to, uint256 deadline) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
}

interface IPancakeFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

// BondingCurve
library BondingCurve {
    uint256 constant PRECISION = 1e18;
    
    function getCurrentPrice(uint256 currentSupply, uint256 basePrice, uint256 slope) internal pure returns (uint256) {
        return basePrice + (slope * currentSupply / PRECISION);
    }
    
    function calculateSellReturn(uint256 currentSupply, uint256 amount, uint256 basePrice, uint256 slope) internal pure returns (uint256) {
        require(currentSupply >= amount && amount > 0, "Invalid amount");
        uint256 newSupply = currentSupply - amount;
        return basePrice * amount / PRECISION + slope * ((newSupply * amount) + (amount * amount / 2)) / PRECISION / PRECISION;
    }
    
    function calculateTokensForBNB(uint256 currentSupply, uint256 bnbAmount, uint256 basePrice, uint256 slope) internal pure returns (uint256) {
        require(bnbAmount > 0, "Zero BNB");
        if (slope == 0) return bnbAmount * PRECISION / basePrice;
        uint256 a = slope / 2;
        uint256 b = basePrice + (slope * currentSupply / PRECISION);
        uint256 c = bnbAmount * PRECISION;
        uint256 discriminant = (b * b) + (4 * a * c / PRECISION);
        uint256 sqrtD = sqrt(discriminant);
        require(sqrtD >= b, "Math error");
        return (sqrtD - b) * PRECISION / (2 * a);
    }
    
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) { y = z; z = (x / z + z) / 2; }
    }
}

// AsterToken
contract AsterToken is ERC20 {
    string public logoURI;
    string public description;
    address public immutable creator;
    address public immutable pool;
    bool public tradingEnabled;
    mapping(address => bool) public isExempt;
    
    modifier onlyPool() { require(msg.sender == pool, "Only pool"); _; }
    
    constructor(string memory _name, string memory _symbol, string memory _logoURI, string memory _description, uint256 _supply, address _creator, address _pool) ERC20(_name, _symbol) {
        require(_creator != address(0) && _pool != address(0) && _supply > 0, "Invalid params");
        logoURI = _logoURI;
        description = _description;
        creator = _creator;
        pool = _pool;
        _mint(_pool, _supply);
    }
    
    function _beforeTokenTransfer(address from, address to, uint256) internal virtual override {
        if (from != pool && to != pool && from != address(0)) {
            require(tradingEnabled || isExempt[from] || isExempt[to], "Trading disabled");
        }
    }
    
    function enableTrading() external onlyPool { require(!tradingEnabled, "Already enabled"); tradingEnabled = true; }
    function setExempt(address account, bool exempt) external onlyPool { isExempt[account] = exempt; }
}

// LaunchpadPool
contract LaunchpadPool is ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    
    address constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address constant ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    
    AsterToken public token;
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
    address public lpPair;
    bool public tradingActive;
    bool private _init;
    
    uint256 constant PLATFORM_FEE = 100;
    uint256 constant CREATOR_FEE = 50;
    uint256 constant GRAD_FEE = 200;
    uint256 constant BP = 10000;
    uint256 constant MAX_BUY = 100 ether;
    
    mapping(address => uint256) public lastBlock;
    
    event TokensBought(address indexed buyer, uint256 bnb, uint256 tokens, uint256 fee, uint256 price, uint256 time);
    event TokensSold(address indexed seller, uint256 tokens, uint256 bnb, uint256 fee, uint256 price, uint256 time);
    event PoolGraduated(address indexed token, uint256 bnb, uint256 tokens, uint256 fee, address lp, uint256 lpBurned, uint256 time);
    
    modifier onlyFactory() { require(msg.sender == factory, "Only factory"); _; }
    modifier whenActive() { require(tradingActive && !graduated, "Not active"); _; }
    modifier antiBot() { require(block.number > lastBlock[msg.sender] + 1, "Wait"); lastBlock[msg.sender] = block.number; _; }
    
    constructor() { factory = msg.sender; }
    
    function initialize(address t, address c, uint256 bp, uint256 s, uint256 gt, uint256 oc, uint256 lp) external onlyFactory {
        require(!_init && t != address(0) && c != address(0) && bp > 0 && gt > 0, "Invalid");
        _init = true;
        token = AsterToken(t);
        creator = c;
        basePrice = bp;
        slope = s;
        graduationThreshold = gt;
        tokensOnCurve = oc;
        tokensForLP = lp;
        tradingActive = true;
    }
    
    function buy(uint256 minTokens) external payable nonReentrant whenNotPaused whenActive antiBot returns (uint256 amt) {
        require(msg.value > 0 && msg.value <= MAX_BUY, "Invalid BNB");
        uint256 pFee = msg.value * PLATFORM_FEE / BP;
        uint256 cFee = msg.value * CREATOR_FEE / BP;
        uint256 net = msg.value - pFee - cFee;
        amt = BondingCurve.calculateTokensForBNB(tokensSold, net, basePrice, slope);
        require(amt >= minTokens && amt > 0 && tokensSold + amt <= tokensOnCurve, "Slippage/supply");
        require(token.balanceOf(address(this)) >= amt, "Insufficient");
        
        tokensSold += amt;
        bnbRaised += net;
        uint256 price = BondingCurve.getCurrentPrice(tokensSold, basePrice, slope);
        
        IERC20(address(token)).safeTransfer(msg.sender, amt);
        _send(factory, pFee);
        _send(creator, cFee);
        
        emit TokensBought(msg.sender, msg.value, amt, pFee + cFee, price, block.timestamp);
        if (bnbRaised >= graduationThreshold) _graduate();
    }
    
    function sell(uint256 amt, uint256 minBnb) external nonReentrant whenNotPaused whenActive antiBot returns (uint256 bnb) {
        require(amt > 0 && amt <= tokensSold, "Invalid amount");
        require(token.balanceOf(msg.sender) >= amt, "Insufficient");
        
        bnb = BondingCurve.calculateSellReturn(tokensSold, amt, basePrice, slope);
        uint256 pFee = bnb * PLATFORM_FEE / BP;
        uint256 cFee = bnb * CREATOR_FEE / BP;
        uint256 net = bnb - pFee - cFee;
        require(net >= minBnb && address(this).balance >= bnb, "Slippage/balance");
        
        tokensSold -= amt;
        bnbRaised -= bnb;
        uint256 price = BondingCurve.getCurrentPrice(tokensSold, basePrice, slope);
        
        IERC20(address(token)).safeTransferFrom(msg.sender, address(this), amt);
        _send(msg.sender, net);
        _send(factory, pFee);
        _send(creator, cFee);
        
        emit TokensSold(msg.sender, amt, net, pFee + cFee, price, block.timestamp);
    }
    
    function _send(address to, uint256 amt) internal {
        if (amt > 0) { (bool ok,) = to.call{value: amt}(""); require(ok, "Send failed"); }
    }
    
    function _graduate() internal {
        require(!graduated, "Done");
        graduated = true;
        tradingActive = false;
        token.enableTrading();
        
        uint256 bal = address(this).balance;
        uint256 gFee = bal * GRAD_FEE / BP;
        uint256 liqBnb = bal - gFee;
        _send(factory, gFee);
        
        token.approve(ROUTER, tokensForLP);
        IPancakeRouter02 r = IPancakeRouter02(ROUTER);
        (uint256 tA, uint256 bA,) = r.addLiquidityETH{value: liqBnb}(address(token), tokensForLP, 0, 0, address(this), block.timestamp + 300);
        
        lpPair = IPancakeFactory(r.factory()).getPair(address(token), r.WETH());
        uint256 lpBal = IERC20(lpPair).balanceOf(address(this));
        if (lpBal > 0) IERC20(lpPair).safeTransfer(DEAD, lpBal);
        token.setExempt(lpPair, true);
        
        uint256 rem = token.balanceOf(address(this));
        if (rem > 0) IERC20(address(token)).safeTransfer(DEAD, rem);
        
        emit PoolGraduated(address(token), bA, tA, gFee, lpPair, lpBal, block.timestamp);
    }
    
    function getCurrentPrice() public view returns (uint256) { return BondingCurve.getCurrentPrice(tokensSold, basePrice, slope); }
    function getProgress() external view returns (uint256) { return graduationThreshold == 0 ? BP : bnbRaised * BP / graduationThreshold; }
    function getPoolInfo() external view returns (address, address, uint256, uint256, uint256, uint256, bool, bool, bool, address) {
        return (address(token), creator, getCurrentPrice(), tokensSold, bnbRaised, graduationThreshold, graduated, tradingActive, paused(), lpPair);
    }
    
    function pause() external onlyFactory { _pause(); }
    function unpause() external onlyFactory { _unpause(); }
    function emergencyWithdrawBNB(address to) external onlyFactory whenPaused nonReentrant {
        require(!graduated && to != address(0), "Invalid");
        _send(to, address(this).balance);
    }
    
    receive() external payable {}
}

// TokenFactory
contract TokenFactory is ReentrancyGuard, Pausable, Ownable2Step {
    address public feeRecipient;
    uint256 public creationFee;
    uint256 public defaultBasePrice = 7142857142;
    uint256 public defaultSlope = 400;
    uint256 public defaultGraduationThreshold = 24 ether;
    uint256 public defaultTotalSupply = 1_000_000_000 * 1e18;
    
    uint256 constant CURVE_BP = 8000;
    uint256 constant LP_BP = 2000;
    uint256 constant BP = 10000;
    
    address[] public allTokens;
    mapping(address => address) public tokenToPool;
    mapping(address => address[]) public creatorTokens;
    mapping(address => bool) public isAsterPool;
    
    string[] public categories;
    uint256 public totalTokensCreated;
    
    event TokenCreated(address indexed token, address indexed pool, address indexed creator, uint256 time);
    event FeeCollected(address indexed from, uint256 amount);
    
    constructor(address _feeRecipient) {
        require(_feeRecipient != address(0), "Zero address");
        feeRecipient = _feeRecipient;
        creationFee = 0.01 ether;
        categories.push("Meme");
        categories.push("DeFi");
        categories.push("Gaming");
        categories.push("NFT");
        categories.push("AI");
        categories.push("Other");
    }
    
    function createToken(string calldata name, string calldata symbol, string calldata logoURI, string calldata description, string calldata) external payable nonReentrant whenNotPaused returns (address tokenAddr, address poolAddr) {
        require(msg.value >= creationFee, "Low fee");
        require(bytes(name).length > 0 && bytes(name).length <= 50 && bytes(symbol).length > 0 && bytes(symbol).length <= 10, "Invalid name/symbol");
        
        uint256 onCurve = defaultTotalSupply * CURVE_BP / BP;
        uint256 forLP = defaultTotalSupply * LP_BP / BP;
        
        LaunchpadPool pool = new LaunchpadPool();
        poolAddr = address(pool);
        
        AsterToken token = new AsterToken(name, symbol, logoURI, description, defaultTotalSupply, msg.sender, poolAddr);
        tokenAddr = address(token);
        
        pool.initialize(tokenAddr, msg.sender, defaultBasePrice, defaultSlope, defaultGraduationThreshold, onCurve, forLP);
        
        allTokens.push(tokenAddr);
        tokenToPool[tokenAddr] = poolAddr;
        creatorTokens[msg.sender].push(tokenAddr);
        isAsterPool[poolAddr] = true;
        totalTokensCreated++;
        
        if (msg.value > 0) {
            (bool ok,) = feeRecipient.call{value: msg.value}("");
            require(ok, "Fee failed");
            emit FeeCollected(msg.sender, msg.value);
        }
        
        emit TokenCreated(tokenAddr, poolAddr, msg.sender, block.timestamp);
    }
    
    function getAllTokens() external view returns (address[] memory) { return allTokens; }
    function getTokenCount() external view returns (uint256) { return allTokens.length; }
    function getCreatorTokens(address c) external view returns (address[] memory) { return creatorTokens[c]; }
    function getCategories() external view returns (string[] memory) { return categories; }
    
    function setCreationFee(uint256 fee) external onlyOwner { require(fee <= 1 ether, "Too high"); creationFee = fee; }
    function setFeeRecipient(address r) external onlyOwner { require(r != address(0), "Zero"); feeRecipient = r; }
    function setDefaultParameters(uint256 bp, uint256 s, uint256 gt, uint256 ts) external onlyOwner {
        require(bp > 0 && gt > 0 && ts > 0, "Invalid");
        defaultBasePrice = bp;
        defaultSlope = s;
        defaultGraduationThreshold = gt;
        defaultTotalSupply = ts;
    }
    
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
    function pausePool(address payable p) external onlyOwner { require(isAsterPool[p], "Not pool"); LaunchpadPool(p).pause(); }
    function unpausePool(address payable p) external onlyOwner { require(isAsterPool[p], "Not pool"); LaunchpadPool(p).unpause(); }
    
    receive() external payable {
        (bool ok,) = feeRecipient.call{value: msg.value}("");
        require(ok, "Forward failed");
    }
}

