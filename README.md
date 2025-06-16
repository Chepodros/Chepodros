# Chepodros Token Contract - V2

## Overview

Chepodros is a satirical meme token created to highlight the absurdity of the cryptocurrency market, where numerous projects are launched with the goal of draining liquidity and disappearing. The Chepodros project seeks to provide a transparent and fun alternative, promoting fairness and safety for new investors while maintaining a humorous tone.

This contract is built on the ERC-20 standard, deployed on the Ethereum blockchain, and uses Uniswap V2 for liquidity management. The contract includes advanced features such as anti-bot protection, dynamic taxation, time-locked administrative controls, and more.

---

## Features

### 1. **ERC-20 Token**
   - Name: **Chepodros**
   - Symbol: **CHEPOS**
   - Total Supply: **21 billion tokens** (18 decimals)
   - Burnable Tokens (Burn Mechanism)
   - Manual trading control with the `openTrading()` function

### 2. **Tax Mechanism**
   - **Buy Tax:** 3%
   - **Sell Tax:** 7%
   - **Anti-bot Tax:** Starts at 50%, reduces by 10% per minute over 5 minutes

### 3. **Whitelist**
   - **Start Whitelist:** During initial trading phase, only whitelisted addresses can trade.
   - **Permanent Whitelist:** Excludes addresses from taxes (set by `excludedFromFees`).

### 4. **Time Locks**
   - Time-locked functions to prevent misuse:
     - Taxes Enabled (`taxesEnabled`)
     - Max Transaction Amount (`maxTxAmount`)
     - Max Wallet Amount (`maxWallet`)
     - Swap Gas Limit (`swapGasLimit`)
     - Tax Wallet (`taxWallet`)
     - Rescue Functions

### 5. **Anti-bot Protection**
   - **Transaction Limits:** Restrictions on the number of tokens per transaction (`maxTxAmount`) and wallet balance (`maxWallet`).
   - **Whitelist-based Trading:** Only whitelisted addresses can trade during the initial phase.
   - **Bot Protection Taxes:** Higher taxes on transactions in the early stages (anti-bot phase).

### 6. **Automatic Token Swaps**
   - Collected tax tokens are automatically swapped for ETH using Uniswap V2.
   - **Slippage Protection:** 5% minimum slippage for token swaps.

### 7. **Ownership and Governance**
   - **Transfer Ownership:** Ownership can be transferred to a multi-signature wallet using the `transferOwnership()` function.
   - **Manual Control:** Owner can enable/disable taxes, adjust limits, and set the tax wallet.

### 8. **Chainlink & 1inch Integration**
   - **Chainlink Price Feed** support for price-based swap protection.
   - **1inch Router** support for optimized token swapping.

### 9. **Security**
   - **ReentrancyGuard** to prevent reentrancy attacks during swaps.
   - Rescue functions for retrieving tokens and ETH accidentally sent to the contract.

---

## Deployment

1. Deploy this contract to a suitable Ethereum-based network (Ethereum, Binance Smart Chain, etc.).
2. Use Remix, Truffle, or Hardhat for deployment.
3. Configure the Uniswap V2 router and WETH address during initialization.

---

## Contract Functions

### 1. **openTrading()**
   - Enables trading after initial restrictions.
   - Can only be called by the owner.

### 2. **setTaxEnabled(bool)**
   - Enables or disables the tax mechanism.
   - Can only be called after the respective timelock.

### 3. **addToWhitelist(address[])**
   - Adds multiple addresses to the whitelist.

### 4. **removeFromWhitelist(address[])**
   - Removes multiple addresses from the whitelist.

### 5. **manualSwapAndSend()**
   - Manually swaps collected tax tokens for ETH and sends the resulting ETH to the tax wallet.

### 6. **setTaxWallet(address)**
   - Sets the address of the wallet that will receive the ETH collected from taxes.
   - Protected by a timelock.

### 7. **excludeFromFees(address)**
   - Excludes an address from tax calculations.
   - Can only be called by the contract owner.

### 8. **setSwapGasLimit(uint256)**
   - Sets the gas limit for swaps on Uniswap V2.
   - Can only be adjusted after a timelock.

---

## Contributing

Contributions are welcome! Feel free to fork this repository, make improvements, and submit pull requests. For any issues, create a GitHub issue for discussion.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Contact

For any questions or feedback, please contact us via GitHub Issues or email at [Chepodros@dev.email](mailto:Chepodros@dev.email).

