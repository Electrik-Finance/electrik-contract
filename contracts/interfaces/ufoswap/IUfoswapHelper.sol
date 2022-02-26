// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUfoswapHelper {
    function stake(address _stakeToken, uint256 _amount) external;

    function emergencyWithdraw(address _stakeToken) external;

    function harvest(address _stakeToken) external;

    function unstake(address _stakeToken, uint256 _amount) external;
}
