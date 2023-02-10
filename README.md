# dss-bridge

Connect an instance of MCD to a cross-chain guest instance. The `DomainHost` is designed to plug into the Host's dss instance and the `DomainGuest` controls the Guest dss instance on the remote chain. For example, `DomainHost` could be plugged into the MCD master instance on Ethereum and a `DomainGuest` controller would be plugged into the Optimism slave instance of MCD. This is recursive, so that when layer 3s come online we can use another Host/Guest pairing on the L2.

![dss-bridge](https://imgur.com/uEruNWB.png)

Each contract is abstract as it requires a chain-specific messaging service, so one of these needs to be extended for each unique message interface.

We assume any messaging bridge will guarantee messages will be executed exactly once, but does not enforce the ordering of messages. Messaging ordering for sensitive operations is enforced at the application layer (`DomainHost` or `DomainGuest`). If the messaging bridge does not protect against censorship then we cannot provide gaurantees that the bridge will function correctly.

## Supported Operations

### `DomainHost.deposit(address to, uint256 amount)`

Standard deposit mechanism. Locks local DAI and mints canonical DAI on the guest domain.

This will trigger a call to `DomainGuest.deposit(address to, uint256 amount)`.

### `DomainGuest.withdraw(address to, uint256 amount)`

Standard withdrawal mechanism. Burns local canonical DAI and unlocks the escrowed DAI on the host domain.

This will trigger a call to `DomainHost.withdraw(address to, uint256 amount)`.

### `DomainHost.lift(uint256 wad)`

Specify a new global debt ceiling for the remote domain. If the amount is an increase this will pre-mint ERC20 and stick it in the domain escrow, so the future minted DAI on the remote domain is backed. It will not remove escrow DAI upon lowering as that can potentially lead to unbacked DAI. Releasing pre-minted DAI from the escrow needs to be handled by the remote domain.

This will back the pre-minted DAI by `vat.gems` that represent shares to the remote domain.

This will trigger a call to `DomainGuest.lift(uint256 _lid, uint256 wad)`.

### `DomainGuest.surplus()`

Permissionless function which will push a surplus to the host domain if the delta is greater than the dust limit. It will exit the DAI, send it across the token bridge leaving it ready for being realized by governance.

This will trigger a call to `DomainHost.surplus(uint256 _lid, uint256 wad)` with `wad >= dust`.

### `DomainGuest.deficit()`

Permissionless function which will push a deficit to the host domain if the delta is greater than the dust limit. It will send a message to the host's domain informing it that the guest is insolvent and needs more DAI. Due to the fact the guest could be compromised we need the Host to authorize the recapitalization operation with a call to `DomainHost.rectify()`.

This will trigger a call to `DomainHost.deficit(uint256 _lid, uint256 wad)` with `wad >= dust`.

### `DomainHost.accrue(uint256 _grain)`

Authed function which will effectively move the accounted surplus to the buffer. It will generate new pre minted DAI if necessary to cover remote's debt (it is up to governance to pass the correct value).

### `DomainHost.rectify()`

Suck some DAI from the surplus buffer and send it to the Guest to cover the bad debt.

This will trigger a call to `DomainGuest.rectify(uint256 _lid, uint256 wad)`.

### `DomainHost.cage()`

Trigger shutdown of the remote domain. This will initiate an `end.cage()`. If you want to gracefully shutdown over a longer period you should call `DomainHost.lift(0)` to prevent new minting.

This will trigger a call to `DomainGuest.cage(uint256 _lid)`.

### `DomainGuest.tell()`

Grabs the final debt level of this `dss` instance during global settlement. The reported value is the `cure` to report back to the host domain.

This will trigger a call to `DomainHost.tell(uint256 _lid, uint256 value)`.

### `DomainHost.exit(address usr, uint256 wad)`

Used during global settlement to provide DAI holders with a share claim on the remote collateral. Mints a claim token on the remote domain which can be used in the remote `end` to get access to the collateral.

This will trigger a call to `DomainGuest.exit(address usr, uint256 claim)`. Where `claim` equals to `wad * debt / grain`.

### Teleport Functions

See the [dss-teleport respoitory](https://github.com/makerdao/dss-teleport) for more detailed information.

## Migration from Canonical DAI

The common strategy is to first deploy a canonical DAI bridge with direct minting rights on the guest domain DAI. This presents a problem because `dss-bridge` requires that `daiJoin` be the sole admin on `dai`. Since there may be in-flight messages to mint we cannot simply disable the canonical DAI bridge during upgrade nor do we want to do this as it will immediately break integrations.

A staged upgrade process is proposed:

1. `dss-bridge` along with all it's dependencies is deployed on the target chain with a debt ceiling of 0. This will give `daiJoin` minting rights on the existing `dai`. There is a problem though in that the `daiJoin` may not have enough `vat.dai` in it to call `daiJoin.join(...)` with existing DAI.

We then call `vat.swell(daiJoin, someLargeNumber)` to make sure existing holders of `dai` can exit via `dss-bridge`. At this point users will be able to enter and exit via either bridge.

2. We close out the canonical DAI bridge. This will restrict DAI minting to just `dss-bridge` at this point.

3. After all the in-transit transactions have cleared (keepers can force any stragglers) we de-auth the canonical bridge from `dai`. We then set `vat.dai(daiJoin)` based on this equation `vat.dai(daiJoin) + vat.dai(not in daijoin) = vat.surf` or `vat.dai(daiJoin) = vat.surf - vat.dai(not in daijoin)`. This equation holds because we have not activated any debt features of the `vat` yet, so it will purely be bridged dai moving around.

4. We can then increase the debt ceiling if desired.
