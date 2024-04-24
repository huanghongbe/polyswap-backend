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

    /// @param tokenA address of tokenA
    /// @param tokenB address of tokenB
    /// @param amountADesired amount of tokenA that user want to provide
    /// @param amountBDesired amount of tokenB that user want to provide
    /// @param amountAMin minimun amount of tokenA that user can accept
    /// @param amountBMin minimun amount of tokenB that user can accept
    /// @param to address that user transfer to
    /// @param isCurveBased true : is curve base
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
        // if the pair is not exist, create the pair first
        if (factory.pairs(tokenA, tokenB) == address(0)) {
            factory.createPair(tokenA, tokenB, isCurveBased);
        }
        // calcualte the liquidity that user provide
        (amountA, amountB) = _calculateLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        // get the corresponding pair address
        address pairAddress = PolyswapLibrary.pairFor(address(factory), tokenA, tokenB);
        // transfer token from user
        _safeTransferFrom(tokenA, msg.sender, pairAddress, amountA);
        _safeTransferFrom(tokenB, msg.sender, pairAddress, amountB);
        // mint lp token to user
        liquidity = PolyswapPair(pairAddress).mint(to);
    }

    /// @param tokenA address of tokenA
    /// @param tokenB address of tokenB
    /// @param liquidity amount of LP token that user want to burn
    /// @param amountAMin minimun amount of tokenA that user can accept
    /// @param amountBMin minimun amount of tokenB that user can accept
    /// @param to address that user transfer to
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to
    ) public returns (uint256 amountA, uint256 amountB) {
        // get the corresponding pair address
        address pair = PolyswapLibrary.pairFor(address(factory), tokenA, tokenB);
        // transfer lp token from user
        PolyswapPair(pair).transferFrom(msg.sender, pair, liquidity);
        // burn lp tokens
        (amountA, amountB) = PolyswapPair(pair).burn(to);
        if (amountA < amountAMin) revert InsufficientAAmount();
        if (amountA < amountBMin) revert InsufficientBAmount();
    }

    /// @param amountIn amount of tokenA
    /// @param amountOutMin minimun amount of tokenB
    /// @param path swap path
    /// @param to address that user transfer to
    /// @param isConfirmed true : confirm to swap
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        bool isConfirmed
    ) public returns (uint256[] memory amounts) {
        // calculate the amount of tokenB that user could get
        amounts = PolyswapLibrary.getAmountsOut(address(factory), amountIn, path);
        if (amounts[amounts.length - 1] < amountOutMin) {
            revert InsufficientOutputAmount();
        }
        // if is confirmed, then do the transfer logic
        if (isConfirmed) {
            _safeTransferFrom(
                path[0], msg.sender, PolyswapLibrary.pairFor(address(factory), path[0], path[1]), amounts[0]
            );
            _swap(amounts, path, to);
        }
    }

    /// @param amountOut amount of tokenB
    /// @param amountInMax maximun amount of tokenA
    /// @param path swap path
    /// @param to address that user transfer to
    /// @param isConfirmed true : confirm to swap
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        bool isConfirmed
    ) public returns (uint256[] memory amounts) {
        // calculate the amount of tokenA that user should pay
        amounts = PolyswapLibrary.getAmountsIn(address(factory), amountOut, path);
        if (amounts[amounts.length - 1] > amountInMax) {
            revert ExcessiveInputAmount();
        }
        // if is confirmed, then do the transfer logic
        if (isConfirmed) {
            _safeTransferFrom(
                path[0], msg.sender, PolyswapLibrary.pairFor(address(factory), path[0], path[1]), amounts[0]
            );
            _swap(amounts, path, to);
        }
    }

    function _swap(uint256[] memory amounts, address[] memory path, address to_) internal {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = PolyswapLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];

            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));

            address to = i < path.length - 2 ? PolyswapLibrary.pairFor(address(factory), output, path[i + 2]) : to_;
            PolyswapPair(PolyswapLibrary.pairFor(address(factory), input, output)).swap(amount0Out, amount1Out, to);
        }
    }

    function _calculateLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal view returns (uint256 amountA, uint256 amountB) {
        (uint256 reserveA, uint256 reserveB) = PolyswapLibrary.getReserves(address(factory), tokenA, tokenB);

        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = PolyswapLibrary.quote(amountADesired, reserveA, reserveB);

            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "InsufficientBAmount");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = PolyswapLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);

                require(amountAOptimal >= amountAMin, "InsufficientAAmount");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function _safeTransferFrom(address token, address from, address to, uint256 value) private {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, value));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert SafeTransferFailed("SafeTransferFailed");
        }
    }
}
