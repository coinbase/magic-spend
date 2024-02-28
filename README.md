> [!IMPORTANT]  
> The code in this repository is still under audit. It is not yet recommended for production use.

# Magic Spend

Magic Spend is a contract that allows onchain accounts to present valid Withdraw Requests and receive funds. A Withdraw Request is defined as 

```solidity
struct WithdrawRequest {
    bytes signature;
    address asset;
    uint256 amount;
    uint256 nonce;
    uint48 expiry;
 }
```

Where signature is an [EIP-191](https://eips.ethereum.org/EIPS/eip-191) compliant signature of the message 
```solidity
abi.encode(
  <Magic Spend Contract Address>,
  <Account>,
  <Chain ID>,
  withdrawRequest.asset,
  withdrawRequest.amount,
  withdrawRequest.nonce,
  withdrawRequest.expiry
)
```

Magic Spend is an [ERC-4337](https://eips.ethereum.org/EIPS/eip-4337) compliant paymaster (EntryPoint [v0.6](https://github.com/eth-infinitism/account-abstraction/releases/tag/v0.6.0)) and also enables withdraw requests with asset ETH (`address(0)`) to be used to pay transaction gas. 

This contract is part of a broader Magic Spend product from Coinbase, which as a whole allows Coinbase users to seamlessly use their assets onchain. 

<img width="661" alt="Diagram of Coinbase user making use of Magic Spend" src="https://github.com/coinbase/magic-spend/assets/6678357/42d3a8fc-a376-4139-9ea9-040cf094d74b">

## Detailed Flows 
When the withdrawing account is an ERC-4337 compliant smart contract (like [Coinbase Smart Wallet](https://github.com/coinbase/smart-wallet)), there are three different ways the Magic Spend smart contract can be used
1. Pay gas only
2. Transfer funds during execution only
3. Pay gas and transfer funds during execution

### Pay gas only

<img width="901" alt="Pay gas only flow diagram" src="https://github.com/coinbase/magic-spend/assets/6678357/21274fb0-b901-4e20-bc1c-f320caa76e5b">

1. A ERC-4337 UserOperation is submitted to the bundler. The paymasterAndData field includes the Magic Spend address and the withdrawal request.
2. Bundler (EOA) calls EntryPoint smart contract. 
3. Entrypoint first calls to `UserOperation.sender`, a smart contract wallet (SCW), to validate the user operation. 
4. Entrypoint decrements the paymaster’s deposit in the Entrypoint. If the paymaster’s deposit is less than the gas cost, the transaction will revert. 
5. EntryPoint calls the Magic Spend contract to run validations on the withdrawal, including checking the signature and ensuring withdraw.value is greater than transaction max gas cost.
6. Entrypoint calls to SCW with `UserOperation.calldata`
7. SCW does arbitrary operation, invoked by `UserOperation.calldata`. 
8. Entrypoint makes post-op call to Magic Spend, with actual gas used in transaction. 
9. Magic Spend sends the SCW any withdraw.value minus actual gas used.
10. Entrypoint refunds the paymaster if actual gas < estimated gas from (4.)
11. Entrypoint pays bundler for tx gas

### Transfer funds during execution only

<img width="600" alt="Diagram of 'Transfer funds during execution only' flow" src="https://github.com/coinbase/magic-spend/assets/6678357/124548ca-209d-41ac-844a-cbf5717a702e">

This is the simplest flow. The Magic Spend account is agnostic to any details of this transaction, even whether or not the caller is a SCW. It simply validates the withdraw and transfers funds if valid. 

### Pay gas and transfer funds during execution

<img width="898" alt="Pay gas and transfer funds during execution" src="https://github.com/coinbase/magic-spend/assets/6678357/4b81fea7-9b45-4cfd-acdb-66f88f6bc642">


This flow is like "Pay gas only” with the addition of (7.) and (8.). Here, the SCW also requests funds during execution. In this flow, a user might be, for example, trying to mint an NFT and needs funds for the mint. 

## Deployments

| Network   | Contract Address                        |
|-----------|-----------------------------------------|
| Base Sepolia | 0x619CcD22eF045De3b63d3D03224BFF5491cd5D11 |


## Developing 
After you clone the repo, you can run the tests using Forge, from [Foundry](https://github.com/foundry-rs/foundry?tab=readme-ov-file)
```bash
forge test
```

You can run the echinda tests with this make command
```bash
make echidna-test
```
