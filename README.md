# SLA Allocator contracts

## Glossary
We expect following actors and contracts in the system:
1. **Client** - person that has data and wants to store it 
2. **SP** - person that runs a miner that can store data and mine blocks
3. **Miner** - instance of the [Miner Actor](https://github.com/filecoin-project/builtin-actors/tree/master/actors/miner)
4. **SLAAllocator** - singleton smart contract that grants DataCap (via **Client Smart Contract**) for **SPs** with correct beneficiary set
5. **Allocator Service** - off-chain service that provides attestations of Gitcoin Passport and deal payment
6. **Beneficiary** - smart contract (one per **Miner**) that manages payout of mining rewards to **SP**
7. **Client Smart Contract** - singleton smart contract that enforces restrictions on how DataCap can be spent by **Clients** and helps track metrics required by **Beneficiary** contract
8. **SLARegistry** - smart contract that tracks current SLA score for a **Client**/**Provider** pair. Any contract implementing the correct interface may be used - we will provide a reference one based on SLIs from CDP.
9. **Oracle** - smart contract that stores off-chain data regarding SLIs for providers. There may be many or none - **SLARegistry** contracts decide which oracles and how they want to use.
10. **Oracle Service** - off-chain service that submits transactions that update SLIs in the **Oracle**
11. **Beneficiary Factory** - singleton contract that deploys new instances of **Beneficiary** contract for storage providers, keeping a registry of those already deployed.
  
## SLAAllocator

**SLAAllocator** contract acts as a Verified Registry Verifier. It has a right to mint DataCap to clients.
In practice, all mint allowance will immediately be used to mint DataCap to the **Client Smart Contract**. DataCap will be assigned to actual **Clients** as an allowance on the **Client Smart Contract**.

It will assign DC to a client under following conditions:
1. **SLAAllocator** has enough mint allowance.
2. Sender, assumed to be the **Client**, has SLAs registered with all **SPs** that will be used in a compatible **SLARegistry** contract
3. **SP** has beneficiary set to an address contained in **Beneficiary Factory** registry, with effectively no quota (we require a very large quota to be set).
4. For Passport-authenticated requests <= 1PiB:
    * score above 20 the client
    * one request per client per week
    * tx payment info is valid and matches size
    * tx payer is distinct from SP owner
5. For Passport-authenticated requests > 1PiB:
    * score above 20 for SP and client
    * distinct stamps between SP and client
    * one request per client per week
    * tx payment info is valid and matches size
    * tx payer is distinct from SP owner
5. For non-Passport-authenticated requests:
    * 5 requests per day GLOBALLY
    * <= 100TiB
    * tx payment info is valid and matches size
    * tx payer is distinct from SP owner

There will be following roles in this contract:
* `ADMIN`, who can manage other roles and upgrade the contract
* `MANAGER`, who can call `mintDataCap(uint256 amount)`.
* `ATTESTATOR`, who can sign attestations of passport scores, stamps and transaction info

// FIXME we must check past SLAs of the provider

Expected interface:
```
interface SLAAllocator {
    struct Signature {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct Passport {
        address subject;
        uint256 expiration_timestamp;
        uint64 score;
    };

    struct PassportSigned {
        Passport passport;
        Signature sig;
    }

    struct ManualAttestation {
        string opaque_data;
    }

    struct ManualAttestationSigned {
        ManualAttestation attestation;
        Signature sig;
    };

    struct PaymentTransaction {
        FilAddress from;
        FilAddress to;
        uint256 amount;
    }

    struct PaymentTransactionSigned {
        PaymentTransaction tx;
        Signature sig;
    }

    function initialize(address admin, address manager, address beneficiaryRegistry, address clientSmartContract, address attestator) external;

    // use Verifreg powers to mint datacap to a client smart contract
    function mintDataCap(uint256 amount) external onlyRole(MANAGER_ROLE);
    
    // request datacap based on SLAs
    function requestDataCap(FilActorId provider, address slaContract, uint256 amount, PaymentTransactionSigned tx) external;

    // request datacap based on SLAs and client's passport
    function requestDataCap(FilActorId provider, address slaContract, uint256 amount, PassportSigned clientPassport, PaymentTransactionSigned tx) external;

    // request datacap based on SLAs, client's passport and SP's passport
    function requestDataCap(FilActorId provider, address slaContract, uint256 amount, PassportSigned clientPassport, PassportSigned spPassport) external;

    // request datacap based on SLAs and manual attestation
    function requestDataCap(FilActorId provider, address slaContract, uint256 amount, ManualAttestationSigned attestation) external;
    
    // administrative
    function setBeneficiaryRegistry(address newBeneficiaryRegistry) external onlyRole(ADMIN_ROLE);
    function setClientSmartContract(address newClientSmartContract) external onlyRole(ADMIN_ROLE);
    // and functions inherited from OpenZeppelin's AccessControl and UUPSUpgradeable
}
```

Expected storage items:
```
address beneficiaryRegistry;
address clientSmartContract;
mapping(address client => mapping(address provider => address contract)) slaContracts;
// FIXME rate limiting storage items
// and items inherited from OpenZeppelin's AccessControl and UUPSUpgradeable
```

## Client Smart Contract

**Client Smart Contract** acts as a Verified Registry Client. It has a DataCap and may transfer it to Verifreg to create Allocations.

The main function it will implement is `transfer`, which copies the interface of DataCap and expects a transfer of DC to Verifreg with Verifreg-compatible operator data. See [FIDL Client Smart Contract](https://github.com/fidlabs/contract-metaallocator/blob/main/src/Client.sol#L71) for reference. It will transfer the DataCap and create allocations under following conditions:
1. **Client Smart Contract** has enough DataCap
2. **Client** has enough allowance left to spend with given **SP**
3. **SP** has correct configuration of beneficiary (address from registry, unlimited quota, adequate expiration)
It will also track how much given **Client** spent with given **SP** so that **Beneficiary** can reference it when calculating weights for payout.

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
struct SPClient {
    address client;
    uint256 amountSpent;
}

address beneficiaryRegistry;
address slaAllocatorContract;
mapping(address client => mapping(address provider => uint256 amount)) allowances;
mapping(address provider => SPClient[] client) spClients;
// and items inherited from OpenZeppelin's AccessControl, UUPSUpgradeable and Multicall
```

## Beneficiary

**Beneficiary** contract acts as the beneficiary for **Miner** - it receives mining rewards. It will enforce SLA rules by reducing the amount of rewards being paid out to **SP** in case SLAs are breached.

The main function implemented by the contract is `withdraw`. It allows withdrawing collected mining rewards based on the SLA. The SLA is calculated by:
1. Fetching list of **Clients** and how much they spent with **SP** from **Client Smart Contract**
2. Fetching **SLARegistry** address for each **Client** from **SLAAllocator**
3. Fetching SLA Score of each **Client** from **SLARegistries**
4. Calculating weighted average of scores based on how much each client spent with **SP**

There will be following roles in this contract:
* `ADMIN`, who can manage addresses and other roles
* `WITHDRAWER_ROLE`, who can withdraw rewards (subject to SLA)

Expected interface:
```
interface Beneficiary {
    function initialize(address admin, address provider, address clientSmartContract, address slaAllocator, address burnAddress) external;
    function withdraw(FilAddress recipient) external onlyRole(WITHDRAWER_ROLE);
    
    receive();
    
    function changeBeneficiary(CommonTypes.FilActorId minerId, CommonTypes.FilAddresses newBeneficiary, uint256 newQuota, int64 newExpirationChainEpoch) external onlyRole(ADMIN_ROLE);

    // administrative
    function setClientSmartContract(address new) external onlyRole(ADMIN_ROLE);
    function setSLAAllocator(address new) external onlyRole(ADMIN_ROLE);
    function setBurnAddress(address new) external onlyRole(ADMIN_ROLE);
    // and functions inherited from OpenZeppelin's AccessControl
}
```

Expected storage items:
```
address clientSmartContract;
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
  Beneficiary->>Miner: Withdraw mining rewards from Miner Actor
  activate Miner
  Miner-->>Beneficiary: Transfer funds
  deactivate Miner
  
  Beneficiary->>ClientSC: Fetch SP's clients & weights
  loop Repeat for all clients
  Beneficiary->>SLAAllocator: Get SLA contract for client/provider pair
  Beneficiary->>SLARegistry: Compute SLA Score
  activate SLARegistry
  SLARegistry->>Oracle: Fetch SLIs
  SLARegistry-->>Beneficiary: Return SLAScore
  deactivate SLARegistry
  end
  
  Beneficiary->>Beneficiary: Calculate weighted avg SLA score

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

## Known issues

1. Weights of clients should be updated when allocations are claimed, not when they're created. FIP-0109 will allow that.

## Unanswered questions

1. **SLAAllocator** rate-limit? How do we prevent draining all funds from the allocator/client smart contract? Someone may register SLAs, request datacap, make allocations and then do nothing with them.
3. Requirements on the beneficiary configuration during datacap allocation by **SLAAllocator**:
    1. Do we just hardcode a minimum expiration? If yes, how long? For MVP lets just require 5+ years.
    2. Do we maybe not require it at all at this time and only check it when making allocation with **Client Smart Contract**, making sure its set for at least as long as the deal will live?
4. When do we allow **SP** to exit the system and change beneficiary address to one that's not a **Beneficiary** contract? Do we force waiting for all deals to end? For MVP lets leave an admin method that will allow this.
5. Maybe we should drop **SLAAllocator** and implement all logic in **Client Smart Contract**?
6. Should we check SLA score when allocating DC / making allocations? If yes, how do we handle the beginning, when there may be no data yet to correctly calculate score?
7. Can SLA be changed once registered? Who's authorized to do that?
8. When deals are finished, we should reduce the weight we give to given client when calculating SLA score for payout. How do we do that? Does FIP-0109 help here?
9. Should we verify that beneficiary address is configured correctly when withdrawing rewards from **Beneficiary**?
10. Who should handle changeBeneficiary process in **Beneficiary**? For now lets leave it to admin (a.k.a. slaAllocator governance team probably)
11. Standardize on either `address` or `FilActorId` - which one?
12. Miner rewards are released even 180 days after deal ends - do we handle it in any special way?
13. Withdrawals from Miner to Beneficiary, withdrawals from Beneficiary to SP and changes in SLA score are now all independent of each other - do we enforce anything here? Maybe some automatic withdrawals? Potential issue I see is providers failing SLAs for a year, but not withdrawing, then improving for a week and withdrawing all at once.
