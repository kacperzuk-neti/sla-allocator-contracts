# SLA Allocator contracts

## Glossary
We expect following actors and contracts in the system:
1. **Client** - person that has data and wants to store it 
2. **SP** - person that runs a miner that can store data and mine blocks
3. **Miner** - instance of the [Miner Actor](https://github.com/filecoin-project/builtin-actors/tree/master/actors/miner)
4. **SLAAllocator** - singleton smart contract that grants DataCap (via **Client Smart Contract**) for **SPs** with correct beneficiary set
5. **Beneficiary** - smart contract (one per **Miner**) that manages payout of mining rewards to **SP**
7. **Client Smart Contract** - singleton smart contract that enforces restrictions on how DataCap can be spent by **Clients** and helps track metrics required by **Beneficiary** contract
8. **SLARegistry** - smart contract that tracks current SLA score for a **Client**/**Provider** pair. Any contract implementing the correct interface may be used - we will provide a reference one based on SLIs from CDP.
9. **Oracle** - smart contract that stores off-chain data regarding SLIs for providers. There may be many or none - **SLARegistry** contracts decide which oracles and how they want to use.
10. **Oracle Service** - off-chain service that submits transactions that update SLIs in the **Oracle**
11. **Beneficiary Factory** - singleton contract that deploys new instances of **Beneficiary** contract for storage providers, keeping a registry of those already deployed.

For now we enforce that SP works with just a single client.

## SLAAllocator

**SLAAllocator** contract acts as a Verified Registry Verifier. It has a right to mint DataCap to clients.
In practice, all mint allowance will immediately be used to mint DataCap to the **Client Smart Contract**. DataCap will be assigned to actual **Clients** as an allowance on the **Client Smart Contract**.

It will assign DC to a client under following conditions:
1. It has enough mint allowance.
2. Sender, assumed to be the **Client**, has SLAs registered with all **SPs** that will be used in a compatible **SLARegistry** contract
3. All **SPs** have a beneficiary set to an address contained in **Beneficiary Factory** registry, which effectively no quota (we require a very large quota to be set) and at least 5 year expiration time.
4. (temporary) **SPs** weren't registered with a different **Client** before.

There will be following roles in this contract:
* `ADMIN`, who can manage other roles and upgrade the contract
* `MANAGER`, who can call `mintDataCap(uint256 amount)`.

Expected interface:
```
interface SLAAllocator {
    struct SLA {
        address contract;
        FilActorId provider;
    }
    
    function initialize(address admin, address manager, address beneficiaryRegistry, address clientSmartContract) external;

    // use Verifreg powers to mint datacap to a client smart contract
    function mintDataCap(uint256 amount) external onlyRole(MANAGER_ROLE);
    
    // request datacap based on SLAs
    function requestDataCap(SLA[] slas, uint256 amount) external;
    
    // administrative
    function setBeneficiaryRegistry(address newBeneficiaryRegistry) external onlyRole(ADMIN_ROLE);
    function setClientSmartContract(address newClientSmartContract) external onlyRole(ADMIN_ROLE);
    // and functions inherited from OpenZeppelin's AccessControl and UUPSUpgradeable
}
```

Expected storage items:
```
mapping(FilActorId provider => address client) providerClients; // temporary
FilActorId[] providers; // temporary, for Oracle Service to know which providers to track
address beneficiaryRegistry;
address clientSmartContract;
mapping(address client => mapping(FilActorId provider => address contract)) slaContracts;
// and items inherited from OpenZeppelin's AccessControl and UUPSUpgradeable
```

## Client Smart Contract

**Client Smart Contract** acts as a Verified Registry Client. It has DataCap and may transfer it to Verifreg to create Allocations.

The main function it will implement is `transfer`, which copies the interface of DataCap and expects a transfer of DC to Verifreg with Verifreg-compatible operator data. See [FIDL Client Smart Contract](https://github.com/fidlabs/contract-metaallocator/blob/main/src/Client.sol#L71) for reference. It will transfer DataCap and create allocations under following conditions:
1. **Client Smart Contract** has enough DataCap
2. **Client** has enough allowance left to spend with given **SP**
3. **SP** has correct configuration of beneficiary (address from registry, unlimited quota, adequate expiration)

There will be following roles in this contract:
* `ADMIN`, who can manage other roles and upgrade the contract
* `ALLOCATOR`, who can manage allowances

Expected interface:
```
interface Client {
    function initialize(address admin, address slaAllocator, address beneficiaryRegistry) external;
    function transfer(DataCapTypes.TransferParams calldata params) external;
    function increaseAllowance(address client, FilActorId provider, uint256 amount) external onlyRole(ALLOCATOR_ROLE);
    function decreaseAllowance(address client, FilActorId provider, uint256 amount) external onlyRole(ALLOCATOR_ROLE);

    // administrative
    function setBeneficiaryRegistry(address newBeneficiaryRegistry) external onlyRole(ADMIN_ROLE);
    // and functions inherited from OpenZeppelin's AccessControl, UUPSUpgradeable and Multicall
}
```

Expected storage items:
```
address beneficiaryRegistry;
address slaAllocatorContract;
mapping(address client => mapping(address provider => uint256 amount)) allowances;
// and items inherited from OpenZeppelin's AccessControl, UUPSUpgradeable and Multicall
```

## Beneficiary

**Beneficiary** contract acts as the beneficiary for **Miner** - it receives mining rewards. It will enforce SLA rules by reducing the amount of rewards being paid out to **SP** in case SLAs are breached.

The main function implemented by the contract is `withdraw`. It allows withdrawing collected mining rewards based on the SLA. The SLA is calculated by:
1. Fetching **SP's** **Client** from **SLAAllocator**
2. Fetching **SLARegistry** address of the **Client** from **SLAAllocator**
3. Fetching SLA Score of the **Client** from **SLARegistrys**

There will be following roles in this contract:
* `ADMIN`, who can manage addresses and other roles
* `WITHDRAWER_ROLE`, who can withdraw rewards (subject to SLA)

Expected interface:
```
interface Beneficiary {
    function initialize(address admin, address provider, address slaAllocator, address burnAddress) external;
    function withdraw(FilAddress recipient) external onlyRole(WITHDRAWER_ROLE);
    
    receive();
    
    function changeBeneficiary(CommonTypes.FilActorId minerId, CommonTypes.FilAddresses newBeneficiary, uint256 newQuota, int64 newExpirationChainEpoch) external onlyRole(ADMIN_ROLE);

    // administrative
    function setSLAAllocator(address new) external onlyRole(ADMIN_ROLE);
    function setBurnAddress(address new) external onlyRole(ADMIN_ROLE);
    // and functions inherited from OpenZeppelin's AccessControl
}
```

Expected storage items:
```
address slaAllocatorContract;
address burnAddress;
// and items inherited from OpenZeppelin's AccessControl, UUPSUpgradeable and Multicall
```

**Beneficiary** will use [Beacon Proxy pattern](https://docs.openzeppelin.com/contracts-stylus/beacon-proxy) for upgradeability.

## SLARegistry

**SLARegistry** contains a registry of SLA's between **Clients** and **SPs** and implements a logic for evaluating them. Any **SLARegistry** implementing a *SLARegistryInterface* may be used.

```
interface SLARegistryInterface {
    // must revert if there's no agreement registered for given client/provider pair
    function score(address client, address provider) external;
}
```

**FIDLSLARegistry** will be a reference **SLARegistry** provided by FIDL. It will be upgradeable and will implement the following interface:
```
interface FIDLSLARegistry is SLARegistryInterface {
    function initialize(address admin, address oracle) external;

    // callable by the client or miner owner
    function registerSLA(address client, address provider, SLAParams slaParams) external;
}
```

## Oracle

**Oracle** is a contract that provides information about off-chain world. Details of logic and interface is between **Oracle** and **SLARegistry** - there are no requirements from SLA Allocator system.

**FIDLOracle** is a reference **Oracle** provided by FIDL that uses data from DataCapStats for SLIs. It will be upgradeable and implement a following interface:

```
interface FIDLOracle {
    struct SLIAttestation {
        uint256 lastUpdate;
        uint16 availability;
        uint16 latency;
        uint16 indexing;
        uint16 retention;
        uint16 bandwidth;
        uint16 stability;
    }
    function setSLI(address provider, SLIAttestation calldata slis) external onlyRole(ORACLE_ROLE);
}
```

Expected storage items:
```
mapping(address provider => SLIAttestation attestation) public attestations;
```

## Diagrams

A typical full flow from registering SLA to withdrawing mining rewards will look as follows:
```mermaid
sequenceDiagram
  actor Client
  participant SLARegistry@{ "type" : "collections" }
  participant SLAAllocator
  actor SP
  participant Beneficiary@{ "type" : "collections" }
  participant Oracle@{ "type" : "collections" }
  participant ClientSC as Client Smart Contract
  participant Miner@{ "type" : "collections" }

note over Client,DataCap: Tx 1: Register SLA
  Client->>SLARegistry: Submit SLA parameters + SP list

note over Client,DataCap: Tx 2: Request DC
  Client->>SLAAllocator: Request DC based on SLA aggreement from registry
  activate SLAAllocator
  SLAAllocator->>SLARegistry: Fetch SLA details

  SLAAllocator->>FVM: Verify SP beneficiary is setup correctly
  SLAAllocator->>ClientSC: Assign DC to Client/Provider pair
  deactivate SLAAllocator

note over Client,DataCap: Tx 3: Make DDO Allocation
  Client->>ClientSC: Make DDO Allocation
  activate ClientSC
  ClientSC->>ClientSC: Verify SP
  ClientSC->>DataCap: Make DDO Allocation
  deactivate ClientSC

note over Client,DataCap: Tx 4: Start mining
  SP->>Miner: Claim DC allocations & start mining
  Miner->>Beneficiary: Transfer mining rewards
  
note over Client,DataCap: Tx 5: Withdraw funds
  SP->>Beneficiary: Request withdrawal
  activate Beneficiary
  
  Beneficiary->>SLAAllocator: Fetch SP's client address
  Beneficiary->>SLAAllocator: Get SLA contract for client/provider pair
  Beneficiary->>SLARegistry: Compute SLA Score
  activate SLARegistry
  SLARegistry->>Oracle: Fetch SLIs
  SLARegistry-->>Beneficiary: Return SLAScore
  deactivate SLARegistry

  Beneficiary->>SP: Payout based on the SLA Score
  deactivate Beneficiary
```

Onboarding a new **SP** will require deploying a new instance of **Beneficiary**. **Beneficiary** must accept becoming a beneficiary for a miner. The proposed flow for MVP is as follows:

```mermaid
sequenceDiagram
  actor Gov as SLAAllocator Governance
  participant Factory as Beneficiary Factory

Gov->>Factory: Create New Beneficiary
create participant Beneficiary
Factory->>Beneficiary: Create
participant Miner
SP->>Miner: Propose Change Beneficiary
Gov->>Beneficiary: Accept Change Beneficiary Proposal
Beneficiary->>Miner: Accept Change Beneficiary Proposal
```
