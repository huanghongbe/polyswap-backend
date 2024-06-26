    // SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

import "./tokens/ERC20.sol";
import "./libraries/Math.sol";
import "./libraries/UQ112x112.sol";

contract PolyswapPair is ERC20, Math {
    using UQ112x112 for uint224;

    // minimun liquidity, use for initial pair
    uint256 constant MINIMUM_LIQUIDITY = 1000;
    // address of tokenA
    address public token0;
    // address of tokenB
    address public token1;

    // 112 + 112 + 32 = 256 = 1 ethereum storage slot.
    // reserve of tokenA
    uint112 private reserve0;
    // reserve of tokenB
    uint112 private reserve1;
    // timestamp of last block mined
    uint32 private blockTimestampLast;
    // current price of tokenA
    uint256 public price0CumulativeLast;
    // current price of tokenB
    uint256 public price1CumulativeLast;

    // is curve based
    bool public isCurveBased;

    // curve based properties
    // Amplification coefficient for the constant sum invariant
    uint256 public a;

    // swap counts of a pair, use for extra fee
    uint256 public swapCounts;

    error TransferFailed();

    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address to);
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Sync(uint256 reserve0, uint256 reserve1);
    event Swap(address indexed sender, uint256 amount0Out, uint256 amount1Out, address indexed to);

    // reentrancy
    uint256 private unlocked = 1;

    modifier lock() {
        require(unlocked == 1, "Polyswap: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    constructor() ERC20("Polyswap Pair", "POLY", 18) {} // pair can mint lp tokens.

    function initialize(address token0_, address token1_, bool isCurveBased_) public {
        require(token0 == address(0) && token1 == address(0), "this pair already initialize");
        token0 = token0_;
        token1 = token1_;
        isCurveBased = isCurveBased_;
        swapCounts = 0;
        if (isCurveBased) {
            a = 85;
        }
    }

    /// mint LP Token
    function mint(address to) public lock returns (uint256 liquidity) {
        (uint112 reserve0_, uint112 reserve1_,) = getReserves();
        uint256 balance0 = ERC20(token0).balanceOf(address(this));
        uint256 balance1 = ERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - reserve0_;
        uint256 amount1 = balance1 - reserve1_;

        if (totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            liquidity = Math.min((amount0 * totalSupply) / reserve0_, (amount1 * totalSupply) / reserve1_);
        }

        require(liquidity > 0, "Please provide more liquidity");

        _mint(to, liquidity);

        _update(balance0, balance1, reserve0_, reserve1_);

        emit Mint(to, amount0, amount1);
    }

    /// burn LP Token
    function burn(address to) public lock returns (uint256 amount0, uint256 amount1) {
        uint256 balance0 = ERC20(token0).balanceOf(address(this));
        uint256 balance1 = ERC20(token1).balanceOf(address(this));
        uint256 liquidity = balanceOf[address(this)];

        amount0 = (liquidity * balance0) / totalSupply;
        amount1 = (liquidity * balance1) / totalSupply;

        require(amount0 > 0 && amount1 > 0, "Insufficient Liquidity Burned");

        _burn(address(this), liquidity);

        _safeTransfer(token0, to, amount0);
        _safeTransfer(token1, to, amount1);

        balance0 = ERC20(token0).balanceOf(address(this));
        balance1 = ERC20(token1).balanceOf(address(this));

        (uint112 reserve0_, uint112 reserve1_,) = getReserves();
        _update(balance0, balance1, reserve0_, reserve1_);

        emit Burn(msg.sender, amount0, amount1, to);
    }

    function swap(uint256 amount0Out, uint256 amount1Out, address to) public lock {
        require(amount0Out != 0 || amount1Out != 0, "InsufficientOutputAmount");
        (uint112 reserve0_, uint112 reserve1_,) = getReserves();
        require(amount0Out < reserve0_ && amount1Out < reserve1_, "InsufficientLiquidity");

        if (amount0Out > 0) _safeTransfer(token0, to, amount0Out);
        if (amount1Out > 0) _safeTransfer(token1, to, amount1Out);

        /// balance = reserve + amountIn - amountOut
        uint256 balance0 = ERC20(token0).balanceOf(address(this));
        uint256 balance1 = ERC20(token1).balanceOf(address(this));
        uint256 amount0In = balance0 > reserve0 - amount0Out ? balance0 - (reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > reserve1 - amount1Out ? balance1 - (reserve1 - amount1Out) : 0;

        require(amount0In != 0 || amount1In != 0);

        // Adjusted = balance before swap - swap fee; fee stays in the contract
        uint256 balance0Adjusted = (balance0 * 1000) - (amount0In * 3);
        uint256 balance1Adjusted = (balance1 * 1000) - (amount1In * 3);
        require(balance0Adjusted * balance1Adjusted >= uint256(reserve0_) * uint256(reserve1_) * (1000 ** 2));

        swapCounts++;
        _update(balance0, balance1, reserve0_, reserve1_);

        emit Swap(msg.sender, amount0Out, amount1Out, to);
    }

    function sync() public {
        (uint112 reserve0_, uint112 reserve1_,) = getReserves();
        _update(ERC20(token0).balanceOf(address(this)), ERC20(token1).balanceOf(address(this)), reserve0_, reserve1_);
    }

    function getReserves() public view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, blockTimestampLast);
    }

    function _update(uint256 balance0, uint256 balance1, uint112 reserve0_, uint112 reserve1_) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "BalanceOverflow");

        unchecked {
            uint32 timeElapsed = uint32(block.timestamp) - blockTimestampLast;

            if (timeElapsed > 0 && reserve0_ > 0 && reserve1_ > 0) {
                price0CumulativeLast += uint256(UQ112x112.encode(reserve1_).uqdiv(reserve0_)) * timeElapsed;
                price1CumulativeLast += uint256(UQ112x112.encode(reserve0_).uqdiv(reserve1_)) * timeElapsed;
            }
        }

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = uint32(block.timestamp);

        emit Sync(reserve0, reserve1);
    }

    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, value));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert TransferFailed();
        }
    }
}
