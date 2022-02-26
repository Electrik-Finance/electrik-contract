require('ethers');
require('@openzeppelin/hardhat-upgrades');
// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task('accounts', 'Prints the list of accounts', async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
const { config } = require('./config');

const privateKey = config.privateKey;

module.exports = {
  defaultNetwork: 'hardhat',
  networks: {
    hardhat: {
      // mining: {
      //     auto: true,
      //     interval: 5000
      // },

      // accounts: getNetworkAccount(),
      accounts: {
        mnemonic: 'test test test test test test test test test test test junk',
        initialIndex: 0,
        accountsBalance: '10000000000000000000000000', // 10,000,000 ETH
      },
      // blockGasLimit: 30000000,
      gas: 8500000,
      timeout: 3000000,
      gasPrice: 25000000000,
    },
    baobab: {
      url: 'https://api.baobab.klaytn.net:8651',
      chainId: 1001,
      accounts: [`${privateKey}`],
      gas: 8500000,
      timeout: 3000000,
      gasPrice: 25000000000,
    },
    mainnet: {
      url: '',
      chainId: 8217, //Klaytn mainnet's network id
      accounts: [`${privateKey}`],
      gas: 8500000,
      timeout: 3000000,
      gasPrice: 25000000000,
    },
    // rinkeby: {
  },
  solidity: {
    version: '0.8.0',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  paths: {
    sources: './contracts',
    tests: './test',
    cache: './cache',
    artifacts: './artifacts',
  },
  mocha: {
    timeout: 20000,
  },
};
