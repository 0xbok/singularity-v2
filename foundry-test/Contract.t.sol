// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "contracts/SingularityPool.sol";
import "contracts/SingularityOracle.sol";
import "contracts/SingularityFactory.sol";
import "contracts/SingularityRouter.sol";
import "contracts/testing/TestChainlinkFeed.sol";
import "contracts/testing/TestERC20.sol";
import "contracts/testing/TestWFTM.sol";

contract ContractTest is Test {

    WFTM public wftm;
    TestERC20 public eth;
    TestERC20 public usdc;
    TestERC20 public dai;

    SingularityOracle public oracle;
    SingularityFactory public factory;
    SingularityRouter public  router;

    SingularityPool public wftmPool;
    SingularityPool public ethPool;
    SingularityPool public usdcPool;
    // SingularityPool daiPool;

    TestChainlinkFeed public wftmFeed;
    TestChainlinkFeed public ethFeed;
    TestChainlinkFeed public usdcFeed;
    TestChainlinkFeed public daiFeed;

    // fee receiver
    address otherAddr = genAddr("otherAddr");

    function setUp() public {

        // deploy test tokens
        wftm = new WFTM();
        eth = new TestERC20("Ethereum", "ETH", 18);
        eth.mint(address(this), 100000 * (10 ** eth.decimals()));

        usdc = new TestERC20("USC Coin", "USDC", 6);
        usdc.mint(address(this), 100000 * (10 ** usdc.decimals()));

        dai = new TestERC20("Dai Stablecoin", "DAI", 21);
        dai.mint(address(this), 100000 * (10 ** dai.decimals()));

        // deploy oracle
        oracle = new SingularityOracle(address(this));
        oracle.setPusher(address(this), true);

        address[] memory assetArray = new address[](4);
        assetArray[0] = address(wftm);
        assetArray[1] = address(eth);
        assetArray[2] = address(usdc);
        assetArray[3] = address(dai);

        uint256[] memory priceArray = new uint256[](4);
        priceArray[0] = 2;
        priceArray[1] = 2000;
        priceArray[2] = 1;
        priceArray[3] = 1;

        // update prices
        oracle.pushPrices(
            assetArray,
            priceArray
        );

        wftmFeed = new TestChainlinkFeed(2 * (10 ** 8));
        oracle.setChainlinkFeed(address(wftm), address(wftmFeed));

        ethFeed = new TestChainlinkFeed(2000 * (10 ** 8));
        oracle.setChainlinkFeed(address(eth), address(ethFeed));

        usdcFeed = new TestChainlinkFeed(1 * (10 ** 8));
        oracle.setChainlinkFeed(address(usdc), address(usdcFeed));

        daiFeed = new TestChainlinkFeed(1 * (10 ** 8));
        oracle.setChainlinkFeed(address(dai), address(daiFeed));

        // deploy factory
        factory = new SingularityFactory("Tranche A", address(this), address(oracle), otherAddr);

        // deploy router
        router = new SingularityRouter(address(factory), address(wftm));
        factory.setRouter(address(router));

        // create pools
        wftmPool = SingularityPool(factory.createPool(address(wftm), false, 0.0015e18));
        ethPool = SingularityPool(factory.createPool(address(eth), false, 0.0015e18));
        usdcPool = SingularityPool(factory.createPool(address(usdc), false, 0.0004e18));
        // daiPool = SingularityPool(factory.createPool(address(dai), false, 0.0004e18));

        address[] memory assetArray1 = new address[](3);
        assetArray1[0] = address(wftm);
        assetArray1[1] = address(eth);
        assetArray1[2] = address(usdc);

        uint256[] memory capArray = new uint256[](3);
        capArray[0] = type(uint256).max;
        capArray[1] = type(uint256).max;
        capArray[2] = type(uint256).max;

        // set deposit caps
        factory.setDepositCaps(
            assetArray1,
            capArray
        );
        // approve pools
        wftm.approve(address(wftmPool), type(uint256).max);
        eth.approve(address(ethPool), type(uint256).max);
        usdc.approve(address(usdcPool), type(uint256).max);

        // approve router
        wftm.approve(address(router), type(uint256).max);
        eth.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
        dai.approve(address(router), type(uint256).max);

        wftmPool.approve(address(router), type(uint256).max);
        ethPool.approve(address(router), type(uint256).max);
        usdcPool.approve(address(router), type(uint256).max);
    }

    function genAddr(bytes memory str) internal pure returns (address) {
        return address(bytes20(keccak256(str)));
    }

    function testCorrectViewReturnValues() public {
        assertEq(factory.tranche(), "Tranche A");
    }
}
