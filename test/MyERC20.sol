// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

import "../src/tokens/ERC20.sol";

contract MyERC20 is ERC20 {
    constructor(string memory _name, string memory _symbol, uint8 _decimals) ERC20(_name, _symbol, _decimals) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
