pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

interface Token {
    function transferFrom(address, address, uint) external returns (bool);
    function transfer(address, uint) external returns (bool);
}

contract LoyalDoge is Context, IERC20, Ownable {
    
    using SafeMath for uint256;
    mapping (address => uint256) private _rOwned;
    mapping (address => uint256) private _tOwned;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private _isExcludedFromFee;
    
    uint256 private constant MAX = ~uint256(0);
    uint256 private constant _tTotal = 100000000000 * 10**6 * 10**9;
    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    uint256 private _tFeeTotal;
    
    uint256 private _redisFeeOnBuy = 3;
    uint256 private _taxFeeOnBuy = 6;
    
    uint256 private _redisFeeOnSell = 3;
    uint256 private _taxFeeOnSell = 6;
    
    uint256 private _redisFee;
    uint256 private _taxFee;
    
    string private constant _name = "LoyalDoge";
    string private constant _symbol = "LDoge";
    uint8 private constant _decimals = 9;
    
    address payable private _developmentAddress = payable(0x3dcF23b07F2964060584F358266d16C9323489f8);
    address payable private _marketingAddress = payable(0x3dcF23b07F2964060584F358266d16C9323489f8);

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;
    
    bool private inSwap = false;
    bool private swapEnabled = true;
    
    // -------- extension content ---------
    // freeze time when address be block
    uint256 private _freezeTime = 2 hours;
    // The Max amount of each transfer
    uint256 private _amountThreshold = 1000000000000000 * 10**9;
    
    
    struct TxInfo {
        uint256[10] timeSnapshot; // store the time point of each transfer. 
        uint256 txCount; // the count of transfer
    }
    
    //mapping address to txInfo
    mapping(address => TxInfo) private _txInfos;
    // store invalid account be freezed time
    mapping(address => uint256) private _beFreezedTimestamp;
    // some addresses can't be freezed
    mapping(address => bool) private _whiteList;

    //statement modifier 
    modifier checkRobot {
        // check is if account in white list
        if (!_isAddressInWhitelist()) {
            // check if account be freezed 
            require(!_isFreeze(), "Be freezed account");
            address account = tx.origin;
            TxInfo storage txInfo = _txInfos[account];
            uint256[10] storage timeSnapshot = txInfo.timeSnapshot;

            // reset txInfo when the count of transfer greater than 10.
            // else record transfer timestamp and increment count
            if (txInfo.txCount >= 10) {
                txInfo.txCount = 1;
                txInfo.timeSnapshot[0] = block.timestamp;
            } else {
                txInfo.timeSnapshot[txInfo.txCount] = block.timestamp;
                txInfo.txCount += 1;
            }
            
            
            uint256 snapshotSize = txInfo.txCount;
            if (snapshotSize == 3) {
                // do this section when the amount of transfer equal 3
                uint256 duration = timeSnapshot[2] - timeSnapshot[0];
                if (duration <= 15 * 60) {
                    _beFreezedTimestamp[account] = block.timestamp;
                }
            } else if (snapshotSize == 6) {
                // do this section when the amount of transfer equal 6
                uint256 duration = timeSnapshot[5] - timeSnapshot[3];
                if (duration <= 30 * 60) {
                    _beFreezedTimestamp[account] = block.timestamp;
                }
            } else if (snapshotSize == 10) {
                // do this section when the amount of transfer equal 10
                uint256 duration = timeSnapshot[9] - timeSnapshot[6];
                if (duration <= 1 hours) {
                    _beFreezedTimestamp[account] = block.timestamp;
                }
            } 
        }
        
        _;
    }

    modifier checkLargeOrder(uint256 amount) {
        _;
        if (amount > _amountThreshold && !_isAddressInWhitelist()) {
            _beFreezedTimestamp[tx.origin] = block.timestamp;
        }
    }

    // check if be freezed
    function _isFreeze() internal view returns (bool) {
        address account = tx.origin;
        return _beFreezedTimestamp[account] != 0 && 
            _beFreezedTimestamp[account] + _freezeTime > block.timestamp;
    }

    // check if one account in white list
    function _isAddressInWhitelist() internal view returns (bool) {
        return _whiteList[tx.origin];
    }

    // update the account status in white list
    function updateWhiteList(address account, bool included) external onlyOwner {
        _whiteList[account] = included;
    }

    // set the Max amount of each transfer
    function setAmountThreshold(uint256 amount) external onlyOwner {
        _amountThreshold = amount;
    }

    // -------- extension content ---------

    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }
    constructor () {
        _rOwned[_msgSender()] = _rTotal;
        
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0xD99D1c33F9fC3444f8101754aBC46c52416550D1);
        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[_developmentAddress] = true;
        _isExcludedFromFee[_marketingAddress] = true;

        // add some specific account to white list
        _whiteList[owner()] = true;
        _whiteList[address(this)] = true;
        _whiteList[_developmentAddress] = true;
        _whiteList[_marketingAddress] = true;

        emit Transfer(address(0x0000000000000000000000000000000000000000), _msgSender(), _tTotal);
    }

    modifier onlyDev() {	
        require(owner() == _msgSender() || _developmentAddress == _msgSender(), "Caller is not the dev");	
        _;	
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public pure override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return tokenFromReflection(_rOwned[account]);
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

    function tokenFromReflection(uint256 rAmount) private view returns(uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate =  _getRate();
        return rAmount.div(currentRate);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) private checkLargeOrder(amount) checkRobot  {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        
        _redisFee = 0;
        _taxFee = 0;
        
        if (from != owner() && to != owner()) {
            
            uint256 contractTokenBalance = balanceOf(address(this));
            if (!inSwap && from != uniswapV2Pair && swapEnabled && contractTokenBalance > 0) {
                swapTokensForEth(contractTokenBalance);
                uint256 contractETHBalance = address(this).balance;
                if(contractETHBalance > 0) {
                    sendETHToFee(address(this).balance);
                }
            }
            
            if(from == uniswapV2Pair && to != address(uniswapV2Router)) {
                _redisFee = _redisFeeOnBuy;
                _taxFee = _taxFeeOnBuy;
            }
    
            if (to == uniswapV2Pair && from != address(uniswapV2Router)) {
                _redisFee = _redisFeeOnSell;
                _taxFee = _taxFeeOnSell;
            }
            
            if ((_isExcludedFromFee[from] || _isExcludedFromFee[to]) || (from != uniswapV2Pair && to != uniswapV2Pair)) {
                _redisFee = 0;
                _taxFee = 0;
            }
            
        }

        _tokenTransfer(from,to,amount);
    }

    function swapTokensForEth(uint256 tokenAmount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }
        
    function sendETHToFee(uint256 amount) private {
        _developmentAddress.transfer(amount.div(2));
        _marketingAddress.transfer(amount.div(2));
    }
    
    function _tokenTransfer(address sender, address recipient, uint256 amount) private {
        _transferStandard(sender, recipient, amount);
    }

    event tokensRescued(address indexed token, address indexed to, uint amount);
    function rescueForeignTokens(address _tokenAddr, address _to, uint _amount) public onlyDev() {
        emit tokensRescued(_tokenAddr, _to, _amount);	
        Token(_tokenAddr).transfer(_to, _amount);
    }
    
    event devAddressUpdated(address indexed previous, address indexed adr);
    function setNewDevAddress(address payable dev) public onlyDev() {
        emit devAddressUpdated(_developmentAddress, dev);	
        _developmentAddress = dev;
        _isExcludedFromFee[_developmentAddress] = true;
    }
    
    event marketingAddressUpdated(address indexed previous, address indexed adr);
    function setNewMarketingAddress(address payable markt) public onlyDev() {
        emit marketingAddressUpdated(_marketingAddress, markt);	
        _marketingAddress = markt;
        _isExcludedFromFee[_marketingAddress] = true;
    }

    function _transferStandard(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tTeam) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount); 
        _takeTeam(tTeam);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _takeTeam(uint256 tTeam) private {
        uint256 currentRate =  _getRate();
        uint256 rTeam = tTeam.mul(currentRate);
        _rOwned[address(this)] = _rOwned[address(this)].add(rTeam);
    }

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    receive() external payable {}
    
    function _getValues(uint256 tAmount) private view returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        (uint256 tTransferAmount, uint256 tFee, uint256 tTeam) = _getTValues(tAmount, _redisFee, _taxFee);
        uint256 currentRate =  _getRate();
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tFee, tTeam, currentRate);
        return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee, tTeam);
    }

    function _getTValues(uint256 tAmount, uint256 taxFee, uint256 TeamFee) private pure returns (uint256, uint256, uint256) {
        uint256 tFee = tAmount.mul(taxFee).div(100);
        uint256 tTeam = tAmount.mul(TeamFee).div(100);
        uint256 tTransferAmount = tAmount.sub(tFee).sub(tTeam);
        return (tTransferAmount, tFee, tTeam);
    }

    function _getRValues(uint256 tAmount, uint256 tFee, uint256 tTeam, uint256 currentRate) private pure returns (uint256, uint256, uint256) {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        uint256 rTeam = tTeam.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee).sub(rTeam);
        return (rAmount, rTransferAmount, rFee);
    }

	function _getRate() private view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns(uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;      
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function manualswap() external {
        require(_msgSender() == _developmentAddress || _msgSender() == _marketingAddress || _msgSender() == owner());
        uint256 contractBalance = balanceOf(address(this));
        swapTokensForEth(contractBalance);
    }

    function manualsend() external {
        require(_msgSender() == _developmentAddress || _msgSender() == _marketingAddress || _msgSender() == owner());
        uint256 contractETHBalance = address(this).balance;
        sendETHToFee(contractETHBalance);
    }
    
    function setFee(uint256 redisFeeOnBuy, uint256 redisFeeOnSell, uint256 taxFeeOnBuy, uint256 taxFeeOnSell) public onlyDev {
	    require(redisFeeOnBuy < 11, "Redis cannot be more than 10.");
	    require(redisFeeOnSell < 11, "Redis cannot be more than 10.");
	    require(taxFeeOnBuy < 7, "Tax cannot be more than 6.");
	    require(taxFeeOnSell < 7, "Tax cannot be more than 6.");
        _redisFeeOnBuy = redisFeeOnBuy;
        _redisFeeOnSell = redisFeeOnSell;
        _taxFeeOnBuy = taxFeeOnBuy;
        _taxFeeOnSell = taxFeeOnSell;
    }
    
    function toggleSwap(bool _swapEnabled) public onlyDev {
        swapEnabled = _swapEnabled;
    }

    function excludeMultipleAccountsFromFees(address[] calldata accounts, bool excluded) public onlyOwner {
        for(uint256 i = 0; i < accounts.length; i++) {
            _isExcludedFromFee[accounts[i]] = excluded;
        }
    }
}
