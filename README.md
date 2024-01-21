# Decentralized Stablecoin (DSC)

1. Anchored / Pegged to US Dollar = 1 DSC = 1 USD
  - Using Chainlink Price Feeds to get the current price of ETH/USD and BTC/USD
  - Using the price, ETH & BTC are converted to USD accordingly
2. Algorithmic Minting Mechanism to ensure stability the ensure Decentralization
  - Minting can only happen if enough collateral is provided
3. Collateralized by exogenous Crypto Assets:
  - ETH (wrapped ETH)
  - BTC (Wrapped BTC)
  Wrapped means that the asset is locked in a smart contract and a token is minted on the Ethereum blockchain.
  So we are essentially dealing with the ERC20 versions of BTC and ETH.



## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
