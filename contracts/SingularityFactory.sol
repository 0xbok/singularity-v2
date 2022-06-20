// SPDX-License-Identifier: No License

pragma solidity ^0.8.14;

import "./interfaces/ISingularityFactory.sol";
import "./SingularityPool.sol";

/**
 * @title Singularity Factory
 * @author Revenant Labs
 */
contract SingularityFactory is ISingularityFactory {
    // @audit info: missing documentation for public variables
    string public override tranche;
    address public override admin;
    address public override oracle;
    address public override feeTo;
    address public override router;
    uint256 public override protocolFeeShare = 55; // trading fee % that goes to protocol revenue ([0, 100])
    uint256 public override oracleSens = 60; // threshold (in seconds) since last oracle update to apply 2x trading fee

    PoolParams public override poolParams;

    mapping(address => address) public override getPool;
    address[] public override allPools;

    modifier onlyAdmin() {
        require(msg.sender == admin, "SingularityFactory: NOT_ADMIN");
        _;
    }

    // @audit gas: use custom errors or at least require string < 32bytes
    constructor(
        string memory _tranche,
        address _admin,
        address _oracle,
        address _feeTo
    ) {
        require(bytes(_tranche).length != 0, "SingularityFactory: TRANCHE_IS_EMPTY");
        require(_admin != address(0), "SingularityFactory: ADMIN_IS_0");
        require(_oracle != address(0), "SingularityFactory: ORACLE_IS_0");
        require(_feeTo != address(0), "SingularityFactory: FEE_TO_IS_0");
        tranche = _tranche;
        admin = _admin;
        oracle = _oracle;
        feeTo = _feeTo;
    }

    function allPoolsLength() external view override returns (uint256) {
        return allPools.length;
    }

    function poolCodeHash() external pure override returns (bytes32) {
        return keccak256(type(SingularityPool).creationCode);
    }

    /* ========== ADMIN FUNCTIONS ========== */

    /// @notice Creates pool for token
    /// @dev Only one pool can exist per token
    /// @param token The underlying token
    /// @param isStablecoin True if token is a stablecoin, otherwise false
    /// @param baseFee The base fee for the pool
    /// @return pool The address of the pool created
    function createPool(
        address token,
        bool isStablecoin,
        uint256 baseFee
    ) external override returns (address pool) {
        require(token != address(0), "SingularityFactory: ZERO_ADDRESS");
        require(baseFee != 0, "SingularityFactory: FEE_IS_0");
        require(getPool[token] == address(0), "SingularityFactory: POOL_EXISTS");

        // @audit gas: pass poolparams as calldata to SingularityPool instead of saving to storage.
        poolParams = PoolParams({factory: address(this), token: token, isStablecoin: isStablecoin, baseFee: baseFee});
        pool = address(new SingularityPool{salt: keccak256(abi.encodePacked(token))}());
        delete poolParams;
        getPool[token] = pool;
        allPools.push(pool);

        emit PoolCreated(token, isStablecoin, baseFee, pool, allPools.length);
    }

    // @audit info: use two step role change process
    function setAdmin(address _admin) external override onlyAdmin {
        require(_admin != address(0), "SingularityFactory: ZERO_ADDRESS");
        admin = _admin;
    }

    function setOracle(address _oracle) external override {
        require(_oracle != address(0), "SingularityFactory: ZERO_ADDRESS");
        oracle = _oracle;
    }

    function setFeeTo(address _feeTo) external override onlyAdmin {
        require(_feeTo != address(0), "SingularityFactory: ZERO_ADDRESS");
        feeTo = _feeTo;
    }

    function setRouter(address _router) external override onlyAdmin {
        require(_router != address(0), "SingularityFactory: ZERO_ADDRESS");
        router = _router;
    }

    function setProtocolFeeShare(uint256 _protocolFeeShare) external override onlyAdmin {
        require(_protocolFeeShare <= 100, "SingularityFactory: PROTOCOL_FEE_SHARE_GT_100");
        protocolFeeShare = _protocolFeeShare;
    }

    function setOracleSens(uint256 _oracleSens) external override onlyAdmin {
        require(_oracleSens != 0, "SingularityFactory: ORACLE_SENS_IS_0");
        oracleSens = _oracleSens;
    }

    // @audit issue: can run OOG if too many pools are created
    function collectFees() external override onlyAdmin {
        uint256 length = allPools.length;
        for (uint256 i; i < length; ) {
            ISingularityPool(allPools[i]).collectFees(feeTo);
            unchecked {
                ++i;
            }
        }
    }

    function setDepositCaps(address[] calldata tokens, uint256[] calldata caps) external override onlyAdmin {
        require(tokens.length == caps.length, "SingularityFactory: NOT_SAME_LENGTH");
        // @audit gas: reading from calldata is cheaper than from memory. Directly use tokens.length
        uint256 length = tokens.length;
        for (uint256 i; i < length; ) {
            address pool = getPool[tokens[i]];
            require(pool != address(0), "SingularityFactory: POOL_DOESNT_EXIST");
            ISingularityPool(pool).setDepositCap(caps[i]);
            unchecked {
                ++i;
            }
        }
    }

    function setDepositCap(address pool, uint256 cap) external {
        ISingularityPool(pool).setDepositCap(cap);
    }
    function setBaseFees(address[] calldata tokens, uint256[] calldata baseFees) external override onlyAdmin {
        require(tokens.length == baseFees.length, "SingularityFactory: NOT_SAME_LENGTH");
        // @audit gas: reading from calldata is cheaper than from memory. Directly use tokens.length
        uint256 length = tokens.length;
        for (uint256 i; i < length; ) {
            require(baseFees[i] != 0, "SingularityFactory: BASE_FEE_IS_0");
            address pool = getPool[tokens[i]];
            require(pool != address(0), "SingularityFactory: POOL_DOESNT_EXIST");
            ISingularityPool(pool).setBaseFee(baseFees[i]);
            unchecked {
                ++i;
            }
        }
    }

    function setPaused(address[] calldata tokens, bool[] calldata states) external override onlyAdmin {
        require(tokens.length == states.length, "SingularityFactory: NOT_SAME_LENGTH");
        // @audit gas: reading from calldata is cheaper than from memory. Directly use tokens.length
        uint256 length = tokens.length;
        for (uint256 i; i < length; ) {
            address pool = getPool[tokens[i]];
            require(pool != address(0), "SingularityFactory: POOL_DOESNT_EXIST");
            ISingularityPool(pool).setPaused(states[i]);
            unchecked {
                ++i;
            }
        }
    }

    // @audit issue: can run OOG if too many pools are created
    function setPausedForAll(bool state) external override onlyAdmin {
        uint256 length = allPools.length;
        for (uint256 i; i < length; ) {
            ISingularityPool(allPools[i]).setPaused(state);
            unchecked {
                ++i;
            }
        }
    }
}
