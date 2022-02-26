// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

interface INeuronMasterchef {

    function deposit(uint256 pId, uint256 amount) external;

    function withdraw(uint256 pId, uint256 amount) external;

    function emergencyWithdraw(uint256 pId) external;

    function pendingNeuron(uint256 pId, address user) external view returns (uint256);

    function totalAllocPoint() external view returns (uint256);

    function poolLength() external view returns (uint256);

    function poolInfo(uint256 pid)
        external
        view
        returns (
            address,
            address,
            uint256,
            uint256,
            uint256
        );

    function userInfo(uint256 pid, address user) external view returns (uint256, uint256);
}
