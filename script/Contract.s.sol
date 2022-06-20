// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
// import "forge-std/console.sol";

import {SingularityFactory} from "contracts/SingularityFactory.sol";
import {SingularityPool} from "contracts/SingularityPool.sol";
import {SingularityFactory} from "contracts/SingularityFactory.sol";
import {SingularityRouter} from "contracts/SingularityRouter.sol";
import {TestERC20} from "contracts/testing/TestERC20.sol";

contract StablecoinOracle {
    function getLatestRound(address) public view returns (uint256, uint256) {
        return (1 ether, block.timestamp);
    }
}

contract ContractScript is Script {
    function setUp() public {}

    function run() public {
        address origin = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        vm.startBroadcast(origin);
        // SingularityFactory factory = SingularityFactory(0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512);
        address oracle = address(new StablecoinOracle());
        SingularityFactory factory = new SingularityFactory("a", origin, oracle, origin);
        SingularityRouter router = new SingularityRouter(address(factory), address(1));
        factory.setOracle(oracle);
        factory.setRouter(address(router));

        address[1000] memory x;
        SingularityPool[1000] memory p;

        for (uint i=0;i<1000;i++) {
            x[i] = address(new TestERC20("a", "a", 18));
            TestERC20(x[i]).mint(origin, 10_000_000 ether);
            p[i] = SingularityPool(factory.createPool(x[i], true, 0.005 ether));
            TestERC20(x[i]).approve(address(p[i]), type(uint).max);
            TestERC20(x[i]).approve(address(router), type(uint).max);
            factory.setDepositCap(address(p[i]), type(uint).max);
            p[i].deposit(1_000_000 ether, origin);
        }

        for(uint i=0; i<1000; i+=2) {
            router.swapExactTokensForTokens(x[i], x[i+1], 1 ether, 0, origin, block.timestamp + 7 days);
        }

        factory.collectFees();

        vm.stopBroadcast();
    }
}
