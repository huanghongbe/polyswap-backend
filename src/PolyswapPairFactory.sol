// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

import "./PolyswapPair.sol";
import "./libraries/SafeDecimalMath.sol";

contract PolyswapPairFactory {
    using SafeDecimalMath for uint256;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    /// 记录每种交易池的创建地址，[token1, token2] -> pairAddress
    mapping(address => mapping(address => address)) public pairs;

    /// 记录所有的交易池地址
    address[] public allPairs;

    function createPair(address tokenA, address tokenB, bool isCurveBased) public returns (address pair) {
        require(tokenA != tokenB, "tokenA == tokenB");

        /// 对两个token地址进行排序，方便后续处理
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        require(token0 != address(0), "token0 == address(0)");

        /// 避免相同交易对重复创建
        require(pairs[token0][token1] == address(0), "this pair already exists");

        /// 获取Pair字节码中的creation部分，使用create2方式，创建确定地址的Pair合约
        bytes memory bytecode = type(PolyswapPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        PolyswapPair(pair).initialize(token0, token1, isCurveBased);

        pairs[token0][token1] = pair;
        pairs[token1][token0] = pair;
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, allPairs.length);
    }
}
