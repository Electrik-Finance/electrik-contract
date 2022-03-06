// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../../interfaces/klayswap/IKSLP.sol";
import "../../interfaces/klayswap/IKSP.sol";
import "../../interfaces/eklipse/IEklChef.sol";
import "./StratManager.sol";
import "./FeeManager.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract StrategyEklipse is Initializable, StratManager, FeeManager {
    address public native;
    address public output;
    address public want;
    address public lpToken0;
    address public lpToken1;
    address public ksp;
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
     * @param _vault address of parent vault.
     * @param _keeper address to use as alternative owner.
     * @param _strategist address where strategist fees go.
     * @param _ksp router to use for swaps
     * @param _electrikFeeRecipient address where to send electrik's fees.
     */

    function initialize(
        address _want,
        address _vault,
        address _ksp,
        address _masterchef,
        uint256 _poolId,
        address _keeper,
        address _strategist,
        address _electrikFeeRecipient,
        address[] memory _outputToNativeRoute, // governance tokenRoute ex) [ksp-> klay]
        address[] memory _outputToLp0Route,
        address[] memory _outputToLp1Route
    ) external initializer {
        keeper = _keeper;
        strategist = _strategist;
        vault = _vault;
        electrikFeeRecipient = _electrikFeeRecipient;
        __Ownable_init();
        __Pausable_init();
        withdrawalFee = 10;
        callFee = 111;
        electrikFee = MAX_FEE - STRATEGIST_FEE - callFee;

        want = _want;
        ksp = _ksp;
        masterchef = _masterchef;
        poolId = _poolId;
        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];

        if (_outputToNativeRoute.length == 2) outputToNativeRoute = new address[](0);
        for (uint256 i = 1; i < _outputToNativeRoute.length - 1; i++) {
            outputToNativeRoute.push(_outputToNativeRoute[i]);
        }

        lpToken0 = IKSLP(want).tokenA();
        require(_outputToLp0Route[0] == output, "outputToLp0Route[0] != output");
        require(_outputToLp0Route[_outputToLp0Route.length - 1] == lpToken0, "outputToLp0Route[last] != lpToken0");

        if (_outputToLp0Route.length == 2) outputToLp0Route = new address[](0);
        for (uint256 i = 1; i < _outputToLp0Route.length - 1; i++) {
            outputToLp0Route.push(_outputToLp0Route[i]);
        }
        lpToken1 = IKSLP(want).tokenB();
        require(_outputToLp1Route[0] == output, "outputToLp1Route[0] != output");
        require(_outputToLp1Route[_outputToLp1Route.length - 1] == lpToken1, "outputToLp1Route[last] != lpToken1");

        if (_outputToLp1Route.length == 2) outputToLp1Route = new address[](0);
        for (uint256 i = 1; i < _outputToLp1Route.length - 1; i++) {
            outputToLp1Route.push(_outputToLp1Route[i]);
        }
        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        if (wantBal > 0) {
            IEklChef(masterchef).deposit(poolId, wantBal);
        }
        emit Deposit(balanceOf());
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IEklChef(masterchef).withdraw(poolId, _amount - wantBal); // input 추가 !!!
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

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        IEklChef(masterchef).withdraw(poolId, 0);

        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            chargeFees(callFeeRecipient);
            addLiquidity();

            uint256 wantHarvested = balanceOfWant();
            deposit();
            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    function chargeFees(address callFeeRecipient) internal {
        uint256 toNative = (IERC20(output).balanceOf(address(this)) * 45) / 1000;

        IKSP(ksp).exchangeKctPos(output, toNative, native, 1, outputToNativeRoute);
        uint256 nativeBal = payable(address(this)).balance;
        uint256 callFeeAmount = (nativeBal * (callFee)) / (MAX_FEE);
        (bool sucCall, ) = payable(callFeeRecipient).call{value: callFeeAmount}("");
        require(sucCall, "callFee failed");
        uint256 electrikFeeAmount = (nativeBal * (electrikFee)) / (MAX_FEE);
        (bool sucFee, ) = payable(electrikFeeRecipient).call{value: electrikFeeAmount}("");
        require(sucFee, "electrikFee failed");
        uint256 strategistFee = (nativeBal * (STRATEGIST_FEE)) / (MAX_FEE);
        (bool sucStr, ) = payable(strategist).call{value: strategistFee}("");
        require(sucStr, "strategistFee failed");
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 outputHalf = IERC20(output).balanceOf(address(this)) / 2;
        if (lpToken0 != output) {
            IKSP(ksp).exchangeKctPos(output, outputHalf, lpToken0, 1, outputToLp0Route);
        }
        if (lpToken1 != output) {
            IKSP(ksp).exchangeKctPos(output, outputHalf, lpToken1, 1, outputToLp1Route);
        }
        if (lpToken0 == address(0)) {
            IERC20(lpToken1).approve(want, type(uint256).max);
            IKSLP(want).addKlayLiquidity{value: payable(address(this)).balance, gas: 500000}(
                IERC20(lpToken1).balanceOf(address(this))
            );
        } else if (lpToken1 == address(0)) {
            IERC20(lpToken0).approve(want, type(uint256).max);
            IKSLP(want).addKlayLiquidity{value: payable(address(this)).balance, gas: 500000}(
                IERC20(lpToken0).balanceOf(address(this))
            );
        } else {
            IERC20(lpToken0).approve(want, type(uint256).max);
            IERC20(lpToken1).approve(want, type(uint256).max);
            IKSLP(want).addKctLiquidity(IERC20(lpToken0).balanceOf(address(this)), IERC20(lpToken1).balanceOf(address(this)));
        }
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + (balanceOfPool());
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        (uint256 _amount, ) = IEklChef(masterchef).userInfo(poolId, address(this));
        return _amount;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256 reward) {
        return IEklChef(masterchef).pendingEKL(poolId, address(this));
    }

    // native reward amount for calling harvest
    function callReward() public view returns (uint256) {
        uint256 outputBal = rewardsAvailable();
        uint256 nativeOut;
        if (outputBal > 0) {
            if (outputToNativeRoute.length == 0) {
                address lp = IKSP(ksp).tokenToPool(output, native);
                try IKSLP(lp).estimatePos(output, outputBal) returns (uint256 amountOut) {
                    nativeOut = amountOut;
                } catch {}
            } else {
                address bToken = output;
                uint256 bAmount = outputBal;
                for (uint256 i = 0; i < outputToNativeRoute.length + 1; i++) {
                    address cToken = outputToNativeRoute.length == i ? address(0) : outputToNativeRoute[i];
                    address lp = IKSP(ksp).tokenToPool(bToken, cToken);
                    try IKSLP(lp).estimatePos(bToken, bAmount) returns (uint256 amountOut) {
                        bAmount = amountOut;
                        bToken = outputToNativeRoute.length == i ? address(0) : outputToNativeRoute[i];
                    } catch {}
                }
                nativeOut = bAmount;
            }
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
        IERC20(output).approve(ksp, type(uint256).max);
        if (lpToken0 != address(0)) {
            IERC20(lpToken0).approve(want, 0);
            IERC20(lpToken0).approve(want, type(uint256).max);
        }
        if (lpToken1 != address(0)) {
            IERC20(lpToken1).approve(want, 0);
            IERC20(lpToken1).approve(want, type(uint256).max);
        }
    }

    function _removeAllowances() internal {
        IERC20(want).approve(masterchef, 0);
        IERC20(output).approve(ksp, 0);
        if (lpToken0 != address(0)) {
            IERC20(lpToken0).approve(ksp, 0);
        }
        if (lpToken1 != address(0)) {
            IERC20(lpToken1).approve(ksp, 0);
        }
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

   
   
     function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(_token != address(want()), "!token");

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }
}
