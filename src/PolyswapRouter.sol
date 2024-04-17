// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

import "./PolyswapPairFactory.sol";
import "./PolyswapLibrary.sol";

contract PolyswapRouter {
    PolyswapPairFactory factory;

    error SafeTransferFailed(string);
    error InsufficientAAmount();
    error InsufficientBAmount();
    error InsufficientOutputAmount();
    error ExcessiveInputAmount();

    constructor(address factoryAddress) {
        factory = PolyswapPairFactory(factoryAddress);
    }

    /// @param to 流动性提供者的地址
    /// @param amountADesired 提供者希望提供的tokenA的数量
    /// @param amountBDesired 提供者希望提供的tokenB的数量
    /// @param amountAMin 提供者希望最少可以提供的tokenA的数量
    /// @param amountBMin 提供者希望最少可以提供的tokenB的数量
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        bool isCurveBased
    ) public returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        /// 如果没有交易对先创建一个
        if (factory.pairs(tokenA, tokenB) == address(0)) {
            factory.createPair(tokenA, tokenB, isCurveBased);
        }

        /// 计算流动性，获取流动性提供者需要提供的两种token数量amountA, amountB
        (amountA, amountB) = _calculateLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);

        /// 获取交易池地址
        address pairAddress = PolyswapLibrary.pairFor(address(factory), tokenA, tokenB);

        /// 将提供的流动性token发给交易池
        _safeTransferFrom(tokenA, msg.sender, pairAddress, amountA);
        _safeTransferFrom(tokenB, msg.sender, pairAddress, amountB);
        /// 提供者获取交易池铸造出的流动性代币（LP Token）的数量liquidity
        liquidity = PolyswapPair(pairAddress).mint(to);
    }

    /// 销毁LP Token，换成对应的tokenA、tokenB
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to
    ) public returns (uint256 amountA, uint256 amountB) {
        address pair = PolyswapLibrary.pairFor(address(factory), tokenA, tokenB);
        /// 用户向交易池中发送要销毁的LP Token的数量
        PolyswapPair(pair).transferFrom(msg.sender, pair, liquidity);
        (amountA, amountB) = PolyswapPair(pair).burn(to);
        if (amountA < amountAMin) revert InsufficientAAmount();
        if (amountA < amountBMin) revert InsufficientBAmount();
    }

    /// 放入amountIn个tokenA可以兑换多少tokenB（费率为0.003）
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        bool isConfirmed
    ) public returns (uint256[] memory amounts) {
        amounts = PolyswapLibrary.getAmountsOut(address(factory), amountIn, path);
        if (amounts[amounts.length - 1] < amountOutMin) {
            revert InsufficientOutputAmount();
        }
        if (isConfirmed) {
            _safeTransferFrom(
                path[0], msg.sender, PolyswapLibrary.pairFor(address(factory), path[0], path[1]), amounts[0]
            );
            _swap(amounts, path, to);
        }
    }

    /// 想得到amountOut个tokenB需要放入多少tokenA（费率为0.003）
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        bool isConfirmed
    ) public returns (uint256[] memory amounts) {
        amounts = PolyswapLibrary.getAmountsIn(address(factory), amountOut, path);
        if (amounts[amounts.length - 1] > amountInMax) {
            revert ExcessiveInputAmount();
        }
        if (isConfirmed) {
            _safeTransferFrom(
                path[0], msg.sender, PolyswapLibrary.pairFor(address(factory), path[0], path[1]), amounts[0]
            );
            _swap(amounts, path, to);
        }
    }

    /// 根据交易池的路由，逐个更新交易池的token数
    function _swap(uint256[] memory amounts, address[] memory path, address to_) internal {
        /// 比如说交易路由A -> B -> C，则先处理AB对，再处理BC对，因此有(path[i], path[i + 1])
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = PolyswapLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            /// 因为Pair中token0、token1是排好序的，因此，对应的amount0Out、amount1Out也应该是排好序的
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            /// 计算下一个交易对的地址
            address to = i < path.length - 2 ? PolyswapLibrary.pairFor(address(factory), output, path[i + 2]) : to_;
            PolyswapPair(PolyswapLibrary.pairFor(address(factory), input, output)).swap(amount0Out, amount1Out, to);
        }
    }

    /// 计算流动性
    function _calculateLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal view returns (uint256 amountA, uint256 amountB) {
        /// 获取交易对中的余额
        (uint256 reserveA, uint256 reserveB) = PolyswapLibrary.getReserves(address(factory), tokenA, tokenB);

        /// 如果池中余额为0，代表此时池子刚创建，
        /// 此时直接把希望提供的token数amountADesired、amountBDesired赋给amountA, amountB
        /// 如果池子不是首次创建，则需要按比例提供两种token
        /// 此时实际提供的amount和希望提供amountDesired数量可能不一致
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            /// 首先计算，如果希望提供amountADesired个tokenA，此时需要提供多少tokenB
            uint256 amountBOptimal = PolyswapLibrary.quote(amountADesired, reserveA, reserveB);
            /// 需要提供的tokenB数量amountBOptimal必须要在（amountBMin，amountBDesired）之间
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "InsufficientBAmount");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                /// 如果amountBOptimal超范围了，那就以“希望提供amountBDesired个tokenB”为基准，重新计算
                uint256 amountAOptimal = PolyswapLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);

                require(amountAOptimal >= amountAMin, "InsufficientAAmount");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    /// 调用token合约的transferFrom，将value个token从from地址发给to地址
    function _safeTransferFrom(address token, address from, address to, uint256 value) private {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, value));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert SafeTransferFailed("SafeTransferFailed");
        }
    }
}
