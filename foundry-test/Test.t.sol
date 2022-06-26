// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";

contract Ballot {
    constructor() {}

    uint256 m = 0;

    function x(uint256[] calldata t) external returns (uint256) {
        uint256 len = t.length;
        for(uint256 i=0; i<len; i++) {
            m += t[i];
        }
        return m;
    }
}

contract TTest {

    Ballot b;

    function setUp() public {
        b = new Ballot();
    }

    function testGas() public {
        uint256[] memory id = new uint256[](10);
        for (uint256 i=0;i<10;i++) {
            id[i] = i;
        }
        console.log(gasleft());
        b.x(id);
        console.log(gasleft());
    }
}