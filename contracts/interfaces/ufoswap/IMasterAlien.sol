// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMasterAlien {
    // 0x2C127C4c43cbfAaaF217444CC1E1c52358480511
    function userInfo(address stakeToken, address user)
        external
        view
        returns (
            uint256 amount,
            uint256,
            uint256,
            address
        );

    function poolInfo(address stakeToken)
        external
        view
        returns (
            uint256 allocPoint,
            uint256,
            uint256,
            uint256,
            uint256 allocBps
        );

    function pendingUfo(address stakeToken, address user) external view returns (uint256);

    function ufoPerBlock() external view returns (uint256);

    function totalAllocPoint() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function poolLength() external view returns (uint256);

    function deposit(
        address _for,
        address _stakeToken,
        uint256 _amount
    ) external;

    function depositUfo(address _for, uint256 _amount) external;

    function emergencyWithdraw(address _for, address _stakeToken) external;

    function harvest(address _for, address _stakeToken) external;

    function withdraw(
        address _for,
        address _stakeToken,
        uint256 _amount
    ) external;

    function withdrawUfo(address _for, uint256 _amount) external;
}
