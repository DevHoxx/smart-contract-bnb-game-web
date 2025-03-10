// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;
    }
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * b;
    }
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;
    }
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    constructor() {
        _transferOwnership(_msgSender());
    }
    
    function owner() public view virtual returns (address) {
        return _owner;
    }
    
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
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

interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

contract GameToken is Context, IERC20, Ownable {
    using SafeMath for uint256;
    
    // Configurações do token
    string private _name = "GameToken";
    string private _symbol = "GAME";
    uint8 private _decimals = 18;
    uint256 private _totalSupply = 1000000000 * 10**uint256(_decimals);
    
    // Mapeamentos
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => bool) private _whitelist;
    mapping(address => uint256[]) private _playerItems;
    mapping(uint256 => uint256) public itemPrices;
    
    // Taxas
    struct FeeStructure {
        uint256 gameTx;
        uint256 standard;
    }
    FeeStructure public fees = FeeStructure(20, 30); // 2% e 3%
    
    // Uniswap
    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;
    
    // Controles
    bool private _paused;
    uint256 public maxTxAmount = _totalSupply.mul(1).div(100); // 1% do supply
    
    // Eventos
    event ItemPurchased(address indexed buyer, uint256 itemId);
    event FeesUpdated(uint256 gameFee, uint256 standardFee);
    
    constructor() {
        _balances[_msgSender()] = _totalSupply;
        
        // Inicializa Uniswap
        IUniswapV2Router02 _router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        uniswapV2Pair = IUniswapV2Factory(_router.factory()).createPair(address(this), _router.WETH());
        uniswapV2Router = _router;
        
        // Exclui dono e contrato das taxas
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        
        emit Transfer(address(0), _msgSender(), _totalSupply);
    }
    
    // Modificador de pausa
    modifier whenNotPaused() {
        require(!_paused || _whitelist[_msgSender()], "Pausado");
        _;
    }
    
    // Funções ERC20
    function name() public view returns (string memory) {
        return _name;
    }
    function symbol() public view returns (string memory) {
        return _symbol;
    }
    function decimals() public view returns (uint8) {
        return _decimals;
    }
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }
    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }
    
    // Lógica de transferência
    function _transfer(address from, address to, uint256 amount) internal whenNotPaused {
        require(from != address(0), "Endereço zero");
        require(to != address(0), "Endereço zero");
        require(amount > 0, "Quantia inválida");
        
        // Verifica limite máximo de transação
        if(!_isExcludedFromFee[from] && !_isExcludedFromFee[to]) {
            require(amount <= maxTxAmount, "Excede limite máximo");
        }
        
        // Calcula taxas
        uint256 fee = 0;
        if(!_isExcludedFromFee[from] && !_isExcludedFromFee[to]) {
            fee = amount.mul(isGameTransaction(from, to) ? fees.gameTx : fees.standard).div(1000);
        }
        
        uint256 transferAmount = amount.sub(fee);
        _balances[from] = _balances[from].sub(amount);
        _balances[to] = _balances[to].add(transferAmount);
        
        if(fee > 0) {
            _balances[address(this)] = _balances[address(this)].add(fee);
            emit Transfer(from, address(this), fee);
        }
        
        emit Transfer(from, to, transferAmount);
    }
    
    function isGameTransaction(address from, address to) internal view returns (bool) {
        return from == uniswapV2Pair || to == uniswapV2Pair;
    }
    
    // Gerenciamento de itens
    function setItemPrice(uint256 itemId, uint256 price) external onlyOwner {
        itemPrices[itemId] = price;
    }
    
    function purchaseItem(uint256 itemId) external whenNotPaused {
        uint256 price = itemPrices[itemId];
        require(price > 0, "Item não disponível");
        require(_balances[msg.sender] >= price, "Saldo insuficiente");
        
        _transfer(msg.sender, address(this), price);
        _playerItems[msg.sender].push(itemId);
        
        emit ItemPurchased(msg.sender, itemId);
    }
    
    function getPlayerItems(address player) external view returns (uint256[] memory) {
        return _playerItems[player];
    }
    
    // Gerenciamento de taxas
    function setFees(uint256 gameFee, uint256 standardFee) external onlyOwner {
        require(gameFee.add(standardFee) <= 50, "Taxas totais não podem exceder 5%");
        fees = FeeStructure(gameFee, standardFee);
        emit FeesUpdated(gameFee, standardFee);
    }
    
    // Gerenciamento de whitelist
    function addToWhitelist(address account) external onlyOwner {
        _whitelist[account] = true;
    }
    
    function removeFromWhitelist(address account) external onlyOwner {
        _whitelist[account] = false;
    }
    
    // Controle de pausa
    function pause() external onlyOwner {
        _paused = true;
    }
    
    function unpause() external onlyOwner {
        _paused = false;
    }
    
    // Funções auxiliares
    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "Endereço zero");
        require(spender != address(0), "Endereço zero");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
    
    // Resgate de ETH
    function withdrawETH() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
    
    // Resgate de tokens presos
    function recoverTokens(address tokenAddress) external onlyOwner {
        require(tokenAddress != address(this), "Não pode resgatar o token principal");
        IERC20(tokenAddress).transfer(owner(), IERC20(tokenAddress).balanceOf(address(this)));
    }
    
    // Recebe ETH
    receive() external payable {}
}