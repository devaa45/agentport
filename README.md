# AgentPort

The daily port of call for Agent ID holders, on BNB Chain.

AgentPort is a small hall with one simple idea: showing up counts. If your wallet holds an [Agent ID](https://www.binance.com/en/support/announcement/detail/95f5dbe0ea674a48a739b59e046648bf), you can check in once a day (UTC), keep a streak going, and collect Port Stamps at 1, 3, 7 and 14 total check-ins.

Port Stamps are non-transferable tokens. Like the Agent ID itself, a stamp stays with the wallet that earned it. A streak cannot be bought, sold, or moved — it can only be built, one day at a time. That is what makes Agent ID the right foundation for it: the identity is non-transferable, so the reputation attached to it is real.

## How Agent ID is used

Agent ID is not decoration here; it is the door and the ledger key.

- **Access control.** `checkIn()` and `claimStamp()` both ask the Agent ID contract (`0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`) whether the caller holds an Agent ID (`balanceOf > 0`). No Agent ID, no check-in.
- **Identity-bound reputation.** Streaks and stamps are recorded against the wallet that holds the Agent ID, and stamps cannot be transferred away from it.

## The contract

`contracts/AgentPort.sol` — one contract, no dependencies.

- No owner, no admin keys, no upgrade path.
- Holds no funds, charges no fees, never asks for token approvals, and cannot move anything out of a user's wallet.
- The only writes are check-in records and stamp mints.
- Stamp artwork and metadata are generated on-chain (SVG + JSON data URIs), so a stamp renders anywhere with no server involved.

Deployed on BNB Chain at: **0x9e4fb7f4ee8cfc85effbb4625700c6fed2ba1cf7** (CREATE2, deterministic deployment proxy). Source verified on BscScan.

## The website

`web/index.html` — a single static page. Connect a wallet that holds an Agent ID (the Binance Wallet browser works well), check in, and claim stamps as they unlock. The page talks to the contract through a public BSC RPC for reads and through your own wallet for writes. Nothing is collected or stored server-side; there is no server.

## Tests

Foundry tests live in `test/AgentPort.t.sol` and cover the Agent ID gate, one-check-in-per-day, streak building and breaking, stamp claims and their limits, non-transferability, and the metadata output.

```
forge test
```

## Notes for reviewers

- Check-in days follow UTC (`block.timestamp / 86400`).
- One project rule we were careful about: this page never asks anyone to scan a QR code or type a pairing code to sign in. You connect with your own wallet, and every transaction is shown and confirmed in that wallet.
- Stamps have no monetary value, and nothing here promises returns. It is a harbour log, not an investment.

## License

MIT
