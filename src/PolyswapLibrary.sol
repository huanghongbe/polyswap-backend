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

    function calculateInvariant(
        address factoryAddress,
        address tokenA,
        address tokenB,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal view returns (uint256 invariant) {
        PolyswapPair pair = PolyswapPair(pairFor(factoryAddress, tokenA, tokenB));
        uint256 a = pair.a();
        uint256 d = pair.d();
        uint256 n = pair.n();
        uint256 balanceIn = reserveIn;
        uint256 balanceOut = reserveOut;

        return a.mul(balanceIn.pow(n).add(balanceOut.pow(n))).add(d.mul(balanceIn).mul(balanceOut));
    }

    function calculateNewInvariant(
        address factoryAddress,
        address tokenA,
        address tokenB,
        uint256 reserveIn,
        uint256 invariant,
        uint256 amountChanged
    ) internal view returns (uint256 newInvariant) {
        PolyswapPair pair = PolyswapPair(pairFor(factoryAddress, tokenA, tokenB));
        uint256 a = pair.a();
        uint256 n = pair.n();
        uint256 balanceIn = reserveIn;

        return invariant.sub(a.mul(balanceIn.pow(n)).add(a.mul((balanceIn.add(amountChanged)).pow(n))));
    }

    function calculateCurveOut(
        address factoryAddress,
        address tokenA,
        address tokenB,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 newInvariant,
        uint256 amountChanged
    ) internal view returns (uint256 out) {
        PolyswapPair pair = PolyswapPair(pairFor(factoryAddress, tokenA, tokenB));
        uint256 a = pair.a();
        uint256 d = pair.d();
        uint256 n = pair.n();
        uint256 balanceIn = reserveIn;
        uint256 balanceOut = reserveOut;
        return newInvariant.sub(
            a.mul((balanceIn.add(amountChanged)).pow(n)).add(d.mul((balanceIn.add(amountChanged))).mul(balanceOut))
        );
    }

    function getCurveBasedAmountIn(
        address factoryAddress,
        address tokenA,
        address tokenB,
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) public view returns (uint256) {
        uint256 invariant = calculateInvariant(factoryAddress, tokenA, tokenB, reserveIn, reserveOut);
        uint256 newInvariant = calculateNewInvariant(factoryAddress, tokenA, tokenB, reserveIn, invariant, amountOut);
        return calculateCurveOut(factoryAddress, tokenA, tokenB, reserveIn, reserveOut, newInvariant, amountOut);
    }

    function getCurveBasedAmountOut(
        address factoryAddress,
        address tokenA,
        address tokenB,
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public view returns (uint256) {
        uint256 invariant = calculateInvariant(factoryAddress, tokenA, tokenB, reserveIn, reserveOut);
        uint256 newInvariant = calculateNewInvariant(factoryAddress, tokenA, tokenB, reserveIn, invariant, amountIn);
        return calculateCurveOut(factoryAddress, tokenA, tokenB, reserveIn, reserveOut, newInvariant, amountIn);
    }

    /// 用amontIn个tokenA可以兑换出多少tokenB，手续费0.003
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256) {
        if (amountIn == 0) revert InsufficientAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();

        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;

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
            if (isCurveBase(factory, path[i], path[i + 1])) {
                amounts[i + 1] = getCurveBasedAmountOut(factory, path[i], path[i + 1], amounts[i], reserve0, reserve1);
            } else {
                amounts[i + 1] = getAmountOut(amounts[i], reserve0, reserve1);
            }
        }

        return amounts;
    }

    /// 想兑换amountOut个tokenB，需要放入多少tokenA，手续费0.003
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256) {
        if (amountOut == 0) revert InsufficientAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();

        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;

        return (numerator / denominator) + 1;
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
            if (isCurveBase(factory, path[i], path[i + 1])) {
                amounts[i - 1] = getCurveBasedAmountIn(factory, path[i], path[i - 1], amounts[i], reserve0, reserve1);
            } else {
                amounts[i - 1] = getAmountIn(amounts[i], reserve0, reserve1);
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
