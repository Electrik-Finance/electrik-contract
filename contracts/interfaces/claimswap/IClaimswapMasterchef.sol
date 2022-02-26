// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IClaimswapMasterchef {
    function deposit(
        uint256 pId,
        uint256 amount,
        address to
    ) external;

    function withdraw(
        uint256 pId,
        uint256 amount,
        address to
    ) external;

    function userInfo(uint256 pid, address user)
        external
        view
        returns (
            uint256 amount,
            int256 rewardDebt,
            bool migrated
        );

    function poolInfo(uint256 _index)
        external
        view
        returns (
            uint256 accClaPerShare,
            uint256 lastRewardBlcok,
            uint256 allocPoint
        );

    function harvest(uint256 pId, address to) external;

    function emergencyWithdraw(uint256 pId, address to) external;

    function pendingCla(uint256 pId, address user) external view returns (uint256);

    function totalAllocPoint() external view returns (uint256);
}
