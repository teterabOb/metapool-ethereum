# Metapool Ethereum Staking

## Introduction

Metapool product for staking on Ethereum, receiving in exchange mpETH.

Allows users to stake ETH or WETH, instant redeem of mpETH (with a small fee) or delayed redeem (1 to 7 days) and add liquidity with ETH or WETH (for instant redeem).

### Goerli Testnet Deploys

> **_NOTE:_** Goerli is no longer supported, use `Sepolia` testnet.

| Contract          | Address                                    |
|-------------------|--------------------------------------------|
| Staking           | [0x748c905130CC15b92B97084Fd1eEBc2d2419146f](https://goerli.etherscan.io/address/0x748c905130CC15b92B97084Fd1eEBc2d2419146f) |
| LiquidUnstakePool | [0x37774000C885e9355eA7C6B025EbF1704141093C](https://goerli.etherscan.io/address/0x37774000C885e9355eA7C6B025EbF1704141093C) |
| Withdrawal        | [0x1A8c25ADc96Fb62183C4CB5B9F0c47746B847e05](https://goerli.etherscan.io/address/0x1A8c25ADc96Fb62183C4CB5B9F0c47746B847e05) |

## Contracts

### Staking

Main contract responsible of managing the staking of ETH/WETH and redeem of mpETH

### LiquidUnstakePool

Liquidity pool to allow users to immediately exchange mpETH for ETH, without any delay but with a small fee.
Also users can provide liquidity with ETH or WETH. This ETH will be slowly converted to mpETH through swaps and the Staking contract can also use this ETH (with some limitations) to create new validators, minting new mpETH for liquidity providers.

### Withdrawal

Manage the delayed mpETH redeem of users. Send ETH from rewards and validators disassemble to users.
Users request the withdraw in the Staking contract and, one epoch later (one week) complete the withdraw on this contract.

## Setup .env files
This project use multiple .env files
- `.env` for common variables to all network
- `.env.<network>` for network specific variables

For testing with hardhat generated accounts, the `.env` only requires:
```
NETWORK="Network used for all commands"
```
If NETWORK is not set, hardhat will try to use the `Sepolia` network.

For production you will need extra variables. Check `.env.sample` for a list of all variables 

Above this, each network requires a `.env.<network>` file with the following variables:
```
RPC_ENDPOINT="RPC endpoint URL"
BLOCK_NUMBER="Block number to fork"
```

# MNEMONIC Configuration for Contract Compilation

To successfully compile contracts, it's necessary to configure the MNEMONIC. This should be stored in a text file following the specific path: `~/.config/mp-eth-mnemonic.txt`. This setup is crucial for the correct functioning of the Hardhat configuration file (`hardhat.config.ts`). Without this configuration, running the command `npm run compile` will result in an error.

## Importance of MNEMONIC Security

**Note:** It is a recommended practice to keep the MNEMONIC outside of the project to prevent its exposure. In UNIX/LINUX-based systems, it's common to store sensitive configuration values in a `.config` folder at the server's root or the user's directory. This helps to securely centralize the security configuration.

## Customizing the MNEMONIC Configuration

If you prefer, you have the option to modify how the MNEMONIC is loaded into the project. By default, the MNEMONIC is read from the aforementioned file, but you can change this to read from an environment variable instead. To do this, follow these steps:

1. Locate line 21 in the `lib/env.ts` file.
2. Replace the line that directly assigns the MNEMONIC:
   ```typescript
   MNEMONIC: mnemonic,
   ```
   With one that uses an environment variable:
    ```typescript
   MNEMONIC: process.env.MNEMONIC,
   ```
3. Ensure you add the MNEMONIC value to your .env file before making this change.
4. Comment the line 11 to avoid an error.
    ```typescript
    const mnemonic = fs.readFileSync(path.join(os.homedir(), ".config/mp-eth-mnemonic.txt")).toString()
    ```
   
Alternatively, if you prefer to keep the original method, simply ensure to create the `mp-eth-mnemonic.txt` file in the `.config` folder at the root of your machine.

## Commands
Note: 
- All commands also compile the contracts
### Compile contracts
`npm run compile`

### Run tests
`npm test`

### Deploy
`npm run deploy <network>`

### Verify contracts
`npm run verify <network>`

### Upgrade implementations
`TARGET=Staking npm run upgrade <network>`

### Transfer proxies admin to multisig
`npm run transfer_to_multisig <network>`

This only transfer the admin permission to upgrade the contracts implementations, not the `ADMIN_ROLE`

