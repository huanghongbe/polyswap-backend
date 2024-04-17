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
        PolyswapPairFactory factory = new PolyswapPairFactory();
        PolyswapRouter router = new PolyswapRouter(address(factory));
        // address pairAddress = factory.createPair(address(token0), address(token1), false);
        // PolyswapPair pair = PolyswapPair(pairAddress);
        token0.mint(msg.sender, 10 ether);
        token1.mint(msg.sender, 10 ether);

        // token0.approve(address(router), 10 ether);
        // token1.approve(address(router), 10 ether);
        // router.addLiquidity(address(token0), address(token1), 10 ether, 10 ether, 0, 0, msg.sender, false);

        vm.stopBroadcast();
        console.log("token0 address: ", address(token0));
        console.log("token1 address: ", address(token1));
        console.log("factory address: ", address(factory));
        console.log("router address: ", address(router));
        // console.log("token0/token1 address: ", address(pair));
    }
}
