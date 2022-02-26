// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPalaswapMasterchef {
    function poolLength() external view returns (uint256);

    function totalAllocPoint() external view returns (uint256);

    function rewardPerBlock() external view returns (uint256);

    function poolInfo(uint256 pid)
        external
        view
        returns (
            address lpToken,
            uint256 allocPoint,
            uint256 lastRewardBlock,
            uint256 accRewardPerShare
        );

    function userInfo(uint256 pid, address user)
        external
        view
        returns (
            uint256 amount,
            uint256 rewardDebt,
            uint256 lockUpEndBlock
        );

    function deposit(uint256 pid, uint256 amount) external;

    function withdraw(uint256 pid, uint256 amount) external;

    function emergencyWithdraw(uint256 pid) external;

    function pendingReward(uint256 pid, address user) external view returns (uint256);
}
