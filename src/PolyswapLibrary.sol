// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

import {PolyswapPair} from "./PolyswapPair.sol";
import {SafeDecimalMath} from "./libraries/SafeDecimalMath.sol";

library PolyswapLibrary {
    using SafeDecimalMath for uint256;

    error InsufficientAmount();
    error InsufficientLiquidity();
    error InvalidPath();

    /// 获取交易池中的tokenA、tokenB的余额reserveA、reserveB
    function getReserves(address factoryAddress, address tokenA, address tokenB)
        public
        view
        returns (uint256 reserveA, uint256 reserveB)
    {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1,) = PolyswapPair(pairFor(factoryAddress, token0, token1)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function isCurveBase(address factoryAddress, address tokenA, address tokenB)
        public
        view
        returns (bool _isCurveBased)
    {
        return PolyswapPair(pairFor(factoryAddress, tokenA, tokenB)).isCurveBased();
    }

    function getCurveBasedAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 extraFee,
        uint256 a
    ) public pure returns (uint256) {
        if (amountOut == 0) revert InsufficientAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        uint256 newBalance = reserveOut.sub(amountOut);
        uint256 amountIn = ((a + reserveIn).mul(amountOut)).div(newBalance.add(a));
        uint256 numerator = amountIn.mul(997 - extraFee);
        uint256 denominator = 1000;
        return numerator.div(denominator);
    }

    function isPopular(address factoryAddress, address tokenA, address tokenB) public view returns (bool) {
        if (PolyswapPair(pairFor(factoryAddress, tokenA, tokenB)).swapCounts() >= 10) {
            return true;
        }
        return false;
    }

    function getCurveBasedAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 extraFee,
        uint256 a
    ) public pure returns (uint256) {
        if (amountIn == 0) revert InsufficientAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        uint256 newBalance = reserveIn.add(amountIn);
        uint256 amountOut = ((a + reserveOut).mul(amountIn)).div(newBalance.add(a));
        uint256 numerator = amountOut.mul(997 - extraFee);
        uint256 denominator = 1000;
        return numerator.div(denominator);
    }

    /// 用amontIn个tokenA可以兑换出多少tokenB，手续费0.003
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut, uint256 extraFee)
        public
        pure
        returns (uint256)
    {
        if (amountIn == 0) revert InsufficientAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();

        uint256 amountInWithFee = amountIn.mul(997 - extraFee);
        uint256 numerator = amountInWithFee.mul(reserveOut);
        uint256 denominator = reserveIn.mul(1000).add(amountInWithFee);
        return numerator / denominator;
    }

    /// 交易池的路由，比如，想用tokenA换tokenC，没有AC交易池，但有AB、BC交易池，此时需要挨个兑换
    function getAmountsOut(address factory, uint256 amountIn, address[] memory path)
        public
        view
        returns (uint256[] memory)
    {
        if (path.length < 2) revert InvalidPath();
        /// A -> B -> C，对应的兑换数量
        uint256[] memory amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserve0, uint256 reserve1) = getReserves(factory, path[i], path[i + 1]);
            uint256 extraFee = 0;
            if (isPopular(factory, path[i], path[i + 1])) {
                extraFee = 1;
            }
            if (isCurveBase(factory, path[i], path[i + 1])) {
                uint256 a = getA(factory, path[i], path[i + 1]);
                amounts[i + 1] = getCurveBasedAmountOut(amounts[i], reserve0, reserve1, extraFee, a);
            } else {
                amounts[i + 1] = getAmountOut(amounts[i], reserve0, reserve1, extraFee);
            }
        }

        return amounts;
    }

    /// 想兑换amountOut个tokenB，需要放入多少tokenA，手续费0.003
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut, uint256 extraFee)
        public
        pure
        returns (uint256)
    {
        if (amountOut == 0) revert InsufficientAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();

        uint256 numerator = reserveIn.mul(amountOut).mul(1000);
        uint256 denominator = reserveOut.sub(amountOut).mul(997 + extraFee);
        return (numerator / denominator).add(1);
    }

    function getA(address factoryAddress, address tokenA, address tokenB) public view returns (uint256) {
        return PolyswapPair(pairFor(factoryAddress, tokenA, tokenB)).a();
    }

    function getAmountsIn(address factory, uint256 amountOut, address[] memory path)
        public
        view
        returns (uint256[] memory)
    {
        if (path.length < 2) revert InvalidPath();
        uint256[] memory amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;

        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 reserve0, uint256 reserve1) = getReserves(factory, path[i - 1], path[i]);
            uint256 extraFee = 0;
            if (isPopular(factory, path[i - 1], path[i])) {
                extraFee = 1;
            }
            if (isCurveBase(factory, path[i], path[i - 1])) {
                uint256 a = getA(factory, path[i], path[i - 1]);
                amounts[i - 1] = getCurveBasedAmountIn(amounts[i], reserve0, reserve1, extraFee, a);
            } else {
                amounts[i - 1] = getAmountIn(amounts[i], reserve0, reserve1, extraFee);
            }
        }

        return amounts;
    }

    function quote(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256 amountOut) {
        require(amountIn != 0, "InsufficientAmount");
        require(reserveIn != 0 && reserveOut != 0, "InsufficientLiquidity");
        /// 给定amountIn个tokenA的情况下，需要按比例提供多少tokenB
        return (amountIn * reserveOut) / reserveIn;
    }

    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        return tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    /// 计算交易池地址
    function pairFor(address factoryAddress, address tokenA, address tokenB)
        internal
        pure
        returns (address pairAddress)
    {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pairAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factoryAddress,
                            keccak256(abi.encodePacked(token0, token1)),
                            keccak256(type(PolyswapPair).creationCode)
                        )
                    )
                )
            )
        );
    }
}
