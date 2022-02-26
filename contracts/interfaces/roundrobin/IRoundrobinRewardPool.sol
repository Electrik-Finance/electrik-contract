// SPDX-License-Identifier: MIT

pragma solidity >=0.5.0;

interface IRoundrobinRewardPool {
  function preProductivityChanged(address _pair, address _user) external;

  function postProductivityChanged(address _pair, address _user) external;

  function claimRewards(address _pair) external;

  function claimableReward(address _pair, address _user)
    external
    view
    returns (uint256);
}
