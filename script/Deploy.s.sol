// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../test/MyERC20.sol";
import "../src/PolyswapPairFactory.sol";
import "../src/PolyswapRouter.sol";
import "../src/PolyswapPair.sol";

contract Deploy is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        MyERC20 token0 = new MyERC20("token0", "T0", 18);
        MyERC20 token1 = new MyERC20("token1", "T1", 18);

        MyERC20 token2 = new MyERC20("token2", "T2", 18);
        MyERC20 token3 = new MyERC20("token3", "T3", 18);

        PolyswapPairFactory factory = new PolyswapPairFactory();

        PolyswapRouter router = new PolyswapRouter(address(factory));

        address pairAddress1 = factory.createPair(address(token0), address(token1), false);
        PolyswapPair pair1 = PolyswapPair(pairAddress1);

        address pairAddress2 = factory.createPair(address(token2), address(token3), true);
        PolyswapPair pair2 = PolyswapPair(pairAddress2);

        token0.mint(msg.sender, 100 ether);
        token1.mint(msg.sender, 100 ether);
        token2.mint(msg.sender, 100 ether);
        token3.mint(msg.sender, 100 ether);

        token0.approve(address(router), 100 ether);
        token1.approve(address(router), 100 ether);
        token2.approve(address(router), 100 ether);
        token3.approve(address(router), 100 ether);

        router.addLiquidity(address(token0), address(token1), 50 ether, 50 ether, 0, 0, msg.sender, false);
        router.addLiquidity(address(token0), address(token1), 50 ether, 50 ether, 0, 0, msg.sender, true);

        // address[] memory path = new address[](2);
        // path[0] = address(token0);
        // path[1] = address(token1);
        // router.swapExactTokensForTokens(1 ether, 0, path, msg.sender, true);

        vm.stopBroadcast();
        console.log("token0 address: ", address(token0));
        console.log("token1 address: ", address(token1));
        console.log("token2 address: ", address(token2));
        console.log("token3 address: ", address(token3));
        console.log("factory address: ", address(factory));
        console.log("router address: ", address(router));
        console.log("token0/token1 address: ", address(pair1));
        console.log("token2/token3 address: ", address(pair2));
    }
}
