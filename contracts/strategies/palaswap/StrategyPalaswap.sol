// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../../interfaces/palaswap/IPalaswapRouter.sol";
import "../../interfaces/palaswap/IPalaswapPair.sol";
import "../../interfaces/palaswap/IPalaswapMasterchef.sol";
import "./StratManager.sol";
import "./FeeManager.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract StrategyPalaswap is Initializable, StratManager, FeeManager {

    address public native;

    address public output;
    address public want;
    address public lpToken0;
    address public lpToken1;

    address public masterchef;
    uint256 public poolId;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    address[] public outputToNativeRoute;
    address[] public outputToLp0Route;
    address[] public outputToLp1Route;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);

    receive() external payable {}

    /**
     * @dev Initializes the strategy contract.
     * @param _want The token that the strategy will aggregate.
     * @param _masterchef The address of the reward pool contract.
     * @param _poolId The id of the reward pool contract.
     * @param _vault address of parent vault.
     * @param _unirouter The address of the router contract.
     * @param _keeper address to use as alternative owner.
     * @param _strategist address where strategist fees go.
     * @param _unirouter router to use for swaps
     * @param _electrikFeeRecipient address where to send electrik's fees.
     */
    function initialize(
        address _want,
        address _masterchef,
        uint256 _poolId,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _electrikFeeRecipient,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToLp0Route,
        address[] memory _outputToLp1Route
    ) external initializer {
        keeper = _keeper;
        strategist = _strategist;
        unirouter = _unirouter;
        vault = _vault;
        electrikFeeRecipient = _electrikFeeRecipient;
        __Ownable_init();
        __Pausable_init();
        withdrawalFee = 10;
        callFee = 111;
        electrikFee = MAX_FEE - STRATEGIST_FEE - callFee;

        want = _want;
        masterchef = _masterchef;
        poolId = _poolId;

        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        outputToNativeRoute = _outputToNativeRoute;

        lpToken0 = IPalaswapPair(want).token0();
        require(_outputToLp0Route[0] == output, "outputToLp0Route[0] != output");
        require(_outputToLp0Route[_outputToLp0Route.length - 1] == lpToken0, "outputToLp0Route[last] != lpToken0");
        outputToLp0Route = _outputToLp0Route;

        lpToken1 = IPalaswapPair(want).token1();
        require(_outputToLp1Route[0] == output, "outputToLp1Route[0] != output");
        require(_outputToLp1Route[_outputToLp1Route.length - 1] == lpToken1, "outputToLp1Route[last] != lpToken1");
        outputToLp1Route = _outputToLp1Route;

        _giveAllowances();
    }

    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        if (wantBal > 0) {
            IPalaswapMasterchef(masterchef).deposit(poolId, wantBal);
        }
        emit Deposit(balanceOf());
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IPalaswapMasterchef(masterchef).withdraw(poolId, _amount - wantBal);
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = (wantBal * withdrawalFee) / WITHDRAWAL_MAX;
            wantBal = wantBal - withdrawalFeeAmount;
        }

        IERC20(want).transfer(vault, wantBal);

        emit Withdraw(wantBal);
    }

    function beforeDeposit() external override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
    }

    function harvest() external virtual {
        _harvest(tx.origin);
    }

    function harvest(address callFeeRecipient) external virtual {
        _harvest(callFeeRecipient);
    }

    function managerHarvest() external onlyManager {
        _harvest(tx.origin);
    }

    function _harvest(address callFeeRecipient) internal whenNotPaused {
        IPalaswapMasterchef(masterchef).deposit(poolId, 0);
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            chargeFees(callFeeRecipient);
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        } else {
          panic();
        }
    } 

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        uint256 toNative = (IERC20(output).balanceOf(address(this)) * 45) / 1000;
        IPalaswapRouter(unirouter).swapExactTokensForTokens(toNative, 0, outputToNativeRoute, address(this), block.timestamp);

        uint256 nativeBal = IERC20(native).balanceOf(address(this));

        uint256 callFeeAmount = (nativeBal * (callFee)) / (MAX_FEE);
        IERC20(native).transfer(callFeeRecipient, callFeeAmount);

        uint256 electrikFeeAmount = (nativeBal * (electrikFee)) / (MAX_FEE);
        IERC20(native).transfer(electrikFeeRecipient, electrikFeeAmount);

        uint256 strategistFee = (nativeBal * (STRATEGIST_FEE)) / (MAX_FEE);
        IERC20(native).transfer(strategist, strategistFee);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal returns (uint256 addedLiquidity) {
        uint256 beforeLiquidity = IERC20(want).balanceOf(address(this));

        uint256 outputHalf = IERC20(output).balanceOf(address(this)) / 2;

        if (lpToken0 != output) {
            IPalaswapRouter(unirouter).swapExactTokensForTokens(outputHalf, 0, outputToLp0Route, address(this), block.timestamp);
        }

        if (lpToken1 != output) {
            IPalaswapRouter(unirouter).swapExactTokensForTokens(outputHalf, 0, outputToLp1Route, address(this), block.timestamp);
        }

        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        IPalaswapRouter(unirouter).addLiquidity(lpToken0, lpToken1, lp0Bal, lp1Bal, 1, 1, address(this), block.timestamp);

        uint256 added = IERC20(want).balanceOf(address(this)) - beforeLiquidity;
        return added;
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    // chef amount
    function balanceOfPool() public view returns (uint256) {
        (uint256 _amount, , ) = IPalaswapMasterchef(masterchef).userInfo(poolId, address(this));
        return _amount;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return IPalaswapMasterchef(masterchef).pendingReward(poolId, address(this));
    }

    // native reward amount for calling harvest
    function callReward() public view returns (uint256) {
        uint256 outputBal = rewardsAvailable();
        uint256 nativeOut;
        if (outputBal > 0) {
            try IPalaswapRouter(unirouter).getAmountsOut(outputBal, outputToNativeRoute) returns (uint256[] memory amountOut) {
                nativeOut = amountOut[amountOut.length - 1];
            } catch {}
        }

        return (((nativeOut * 45) / 1000) * callFee) / MAX_FEE;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(10);
        }
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IPalaswapMasterchef(masterchef).emergencyWithdraw(poolId, address(this));

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IPalaswapMasterchef(masterchef).emergencyWithdraw(poolId, address(this));
    }

    function pause() public onlyManager {
        _pause();

        _removeAllowances();
    }

    function unpause() external onlyManager {
        _unpause();

        _giveAllowances();

        deposit();
    }

    function _giveAllowances() internal {
        IERC20(want).approve(masterchef, type(uint256).max);
        IERC20(output).approve(unirouter, type(uint256).max);

        IERC20(lpToken0).approve(unirouter, 0);
        IERC20(lpToken0).approve(unirouter, type(uint256).max);

        IERC20(lpToken1).approve(unirouter, 0);
        IERC20(lpToken1).approve(unirouter, type(uint256).max);
    }

    function _removeAllowances() internal {
        IERC20(want).approve(masterchef, 0);
        IERC20(output).approve(unirouter, 0);
        IERC20(lpToken0).approve(unirouter, 0);
        IERC20(lpToken1).approve(unirouter, 0);
    }

    function outputToNative() external view returns (address[] memory) {
        return outputToNativeRoute;
    }

    function outputToLp0() external view returns (address[] memory) {
        return outputToLp0Route;
    }

    function outputToLp1() external view returns (address[] memory) {
        return outputToLp1Route;
    }

      function inCaseTokensGetStuck(address _token) external onlyManager {
        require(_token != address(want()), "!token");

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(msg.sender, amount);
    }
}
