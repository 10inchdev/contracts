// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IBEP20.sol";

/**
 * @title AsterToken
 * @dev BEP-20 token created by AsterPad launchpad
 * Features: Standard BEP-20 with metadata URI for logo
 */
contract AsterToken is IBEP20 {
    string private _name;
    string private _symbol;
    string public logoURI;
    string public description;
    uint8 private constant _decimals = 18;
    uint256 private _totalSupply;
    
    address public creator;
    address public launchpad;
    uint256 public createdAt;
    
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    // Anti-bot measures
    bool public tradingEnabled;
    uint256 public maxTxAmount;
    uint256 public cooldownTime;
    mapping(address => uint256) public lastTxTime;
    mapping(address => bool) public isExempt;
    
    modifier onlyLaunchpad() {
        require(msg.sender == launchpad, "Only launchpad");
        _;
    }
    
    modifier onlyCreator() {
        require(msg.sender == creator, "Only creator");
        _;
    }
    
    constructor(
        string memory name_,
        string memory symbol_,
        string memory logoURI_,
        string memory description_,
        uint256 totalSupply_,
        address creator_,
        address launchpad_
    ) {
        _name = name_;
        _symbol = symbol_;
        logoURI = logoURI_;
        description = description_;
        _totalSupply = totalSupply_;
        creator = creator_;
        launchpad = launchpad_;
        createdAt = block.timestamp;
        
        // Mint all tokens to launchpad for bonding curve
        _balances[launchpad_] = totalSupply_;
        emit Transfer(address(0), launchpad_, totalSupply_);
        
        // Set anti-bot defaults
        tradingEnabled = false;
        maxTxAmount = totalSupply_ / 100; // 1% max tx
        cooldownTime = 30; // 30 seconds cooldown
        
        // Exempt launchpad and creator
        isExempt[launchpad_] = true;
        isExempt[creator_] = true;
    }
    
    function name() external view override returns (string memory) {
        return _name;
    }
    
    function symbol() external view override returns (string memory) {
        return _symbol;
    }
    
    function decimals() external pure override returns (uint8) {
        return _decimals;
    }
    
    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }
    
    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }
    
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }
    
    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        _transfer(sender, recipient, amount);
        
        uint256 currentAllowance = _allowances[sender][msg.sender];
        require(currentAllowance >= amount, "Transfer exceeds allowance");
        unchecked {
            _approve(sender, msg.sender, currentAllowance - amount);
        }
        return true;
    }
    
    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "Transfer from zero");
        require(recipient != address(0), "Transfer to zero");
        require(_balances[sender] >= amount, "Insufficient balance");
        
        // Anti-bot checks (skip for exempt addresses)
        if (!isExempt[sender] && !isExempt[recipient]) {
            require(tradingEnabled, "Trading not enabled");
            require(amount <= maxTxAmount, "Exceeds max tx");
            require(block.timestamp >= lastTxTime[sender] + cooldownTime, "Cooldown active");
            lastTxTime[sender] = block.timestamp;
        }
        
        unchecked {
            _balances[sender] -= amount;
            _balances[recipient] += amount;
        }
        
        emit Transfer(sender, recipient, amount);
    }
    
    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "Approve from zero");
        require(spender != address(0), "Approve to zero");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
    
    // Launchpad functions
    function enableTrading() external onlyLaunchpad {
        tradingEnabled = true;
    }
    
    function setExempt(address account, bool exempt) external onlyLaunchpad {
        isExempt[account] = exempt;
    }
    
    function setMaxTxAmount(uint256 amount) external onlyLaunchpad {
        require(amount >= _totalSupply / 1000, "Too low"); // Min 0.1%
        maxTxAmount = amount;
    }
    
    function setCooldownTime(uint256 time) external onlyLaunchpad {
        require(time <= 300, "Max 5 minutes");
        cooldownTime = time;
    }
    
    // Metadata
    function setLogoURI(string memory uri) external onlyCreator {
        logoURI = uri;
    }
    
    function setDescription(string memory desc) external onlyCreator {
        description = desc;
    }
}






