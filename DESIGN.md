# Design Document: ElixirScope.Distributed (elixir_scope_distributed)

## 1. Purpose & Vision

**Summary:** Enables ElixirScope to function in a distributed Elixir/OTP environment by managing node discovery, event synchronization across nodes, distributed correlation ID consistency, and handling network partitions.

**(Greatly Expanded Purpose based on your existing knowledge of ElixirScope and CPG features):**

The `elixir_scope_distributed` library extends ElixirScope's observability and debugging capabilities to applications running across multiple Erlang nodes. Its primary mission is to create a cohesive, cluster-wide view of execution, allowing developers and AI to trace operations and data flows as they span node boundaries.

This library aims to:
*   **Manage Cluster Membership:** Provide mechanisms for ElixirScope instances on different nodes to discover and register with each other (`ElixirScope.Distributed.NodeCoordinator`).
*   **Synchronize Events Across Nodes:** Implement efficient strategies (`ElixirScope.Distributed.EventSynchronizer`) to exchange captured runtime events between nodes, allowing for a global view of event sequences. This involves handling event de-duplication and potential conflict resolution.
*   **Maintain Distributed Clock/Timestamp Consistency:** Utilize a logical or hybrid logical clock (`ElixirScope.Distributed.GlobalClock`) to ensure that timestamps from different nodes can be reasonably ordered and correlated, crucial for understanding causality in distributed traces.
*   **Propagate Correlation IDs Across Node Calls:** Ensure that ElixirScope's `correlation_id` (and potentially `ast_node_id` if relevant to the call) can be propagated during inter-node RPCs or message sends, allowing traces to be stitched together across the cluster.
*   **Handle Network Partitions:** Detect network partitions and manage ElixirScope's behavior gracefully, potentially buffering events locally and attempting resynchronization when connectivity is restored.
*   **Facilitate Distributed Queries:** (Potentially) Provide a layer for coordinating queries (via `elixir_scope_storage` or `elixir_scope_ast_repo`) across multiple nodes to gather a complete picture for distributed analysis.

While CPGs are typically generated on a per-application (or per-node codebase) basis, this library is vital if an operation being debugged involves calls between services running on different nodes where each service has its own CPG. The distributed correlation IDs and synchronized event streams would allow linking segments of execution traces across these different CPG contexts. For example, an AI could trace a request from an entry point on Node A (CPG-A) to a service call on Node B (CPG-B) and back.

This library will enable:
*   Tracing and debugging of distributed workflows that span multiple Elixir nodes.
*   A unified view of events from all nodes in a cluster within `TidewaveScope` (or a central ElixirScope UI).
*   `elixir_scope_correlator` and `elixir_scope_temporal_debug` to potentially build traces and reconstruct states that involve events from multiple nodes.
*   AI analysis (`elixir_scope_ai`) of distributed system behavior patterns.

## 2. Key Responsibilities

This library is responsible for:

*   **Node Coordination (`NodeCoordinator` GenServer):**
    *   Discovering other ElixirScope-enabled nodes in the cluster (e.g., via Erlang distribution, or a discovery service).
    *   Maintaining a list of active cluster members.
    *   Handling node-up and node-down events.
    *   Orchestrating event synchronization and distributed queries.
*   **Event Synchronization (`EventSynchronizer`):**
    *   Periodically exchanging new events with other nodes.
    *   Implementing an efficient delta-synchronization protocol to minimize network traffic.
    *   Handling event de-duplication and resolving potential conflicts (e.g., based on global clock timestamps).
    *   Storing received remote events into the local `elixir_scope_storage`.
*   **Global Clock Management (`GlobalClock` GenServer):**
    *   Implementing a logical or hybrid logical clock to provide consistent timestamping or ordering for events across the cluster.
    *   Periodically synchronizing clocks between nodes.
*   **Distributed Correlation ID Propagation:**
    *   Providing mechanisms or guidelines for instrumented code (or libraries like ` распределенGenServer`) to pass ElixirScope correlation IDs across node boundaries during RPCs or distributed messages.
*   **Partition Detection & Handling (within `NodeCoordinator`):**
    *   Monitoring connectivity to other nodes.
    *   Detecting network partitions.
    *   Implementing strategies for behavior during partitions (e.g., local event buffering, attempting resync on recovery).

## 3. Key Modules & Structure

The primary modules within this library will be:

*   `ElixirScope.Distributed.NodeCoordinator` (Main GenServer for cluster management)
*   `ElixirScope.Distributed.EventSynchronizer` (Logic for event exchange)
*   `ElixirScope.Distributed.GlobalClock` (GenServer for distributed timestamping/ordering)
*   `ElixirScope.Distributed.Transport` (Internal: handles actual RPC/message passing for sync, potentially abstracting different Erlang distribution mechanisms or custom protocols)
*   `ElixirScope.Distributed.Types` (Defines structs for inter-node messages, cluster state)

### Proposed File Tree:

```
elixir_scope_distributed/
├── lib/
│   └── elixir_scope/
│       └── distributed/
│           ├── node_coordinator.ex
│           ├── event_synchronizer.ex
│           ├── global_clock.ex
│           ├── transport.ex # Internal
│           └── types.ex
├── mix.exs
├── README.md
├── DESIGN.MD
└── test/
    ├── test_helper.exs
    └── elixir_scope/
        └── distributed/
            ├── node_coordinator_test.exs
            ├── event_synchronizer_test.exs
            └── global_clock_test.exs
```

**(Greatly Expanded - Module Description):**
*   **`ElixirScope.Distributed.NodeCoordinator` (GenServer):** This is the central point for managing ElixirScope's presence in a distributed environment. It handles node discovery (e.g., by monitoring `:net_kernel` events or a configured list of nodes), maintains the current cluster view, and initiates periodic tasks like event synchronization (by calling `EventSynchronizer`) and global clock updates. It also detects and logs network partitions.
*   **`ElixirScope.Distributed.EventSynchronizer`**: This module contains the logic for exchanging ElixirScope events between nodes. It would:
    1.  Query the local `elixir_scope_storage` for events created since the last successful sync with a particular remote node.
    2.  Use the `Transport` module to send these events to the remote node.
    3.  Receive events from the remote node in response.
    4.  Handle de-duplication (e.g., based on `event_id`) and store new remote events into the local `elixir_scope_storage`.
    5.  This module needs to be careful about event ordering using timestamps from `GlobalClock`.
*   **`ElixirScope.Distributed.GlobalClock` (GenServer):** Implements a distributed clocking mechanism. This could be a Lamport clock, vector clock, or a hybrid logical clock (HLC) to establish a partial or total order of events across the cluster. It periodically exchanges clock values with other nodes to maintain synchronization. Events captured by `elixir_scope_capture_core` would get a timestamp from this global clock in addition to their local monotonic timestamp.
*   **`ElixirScope.Distributed.Transport` (Internal):** An internal module that abstracts the actual network communication (e.g., Erlang's `:rpc` or custom GenServer calls over distributed Erlang) used by `EventSynchronizer` and `GlobalClock` to communicate with their counterparts on other nodes.
*   **`ElixirScope.Distributed.Types`**: Defines data structures for messages exchanged between nodes (e.g., sync requests, clock updates, cluster membership changes).

## 4. Public API (Conceptual)

Via `ElixirScope.Distributed.NodeCoordinator` (GenServer):

*   `start_link(opts :: keyword()) :: GenServer.on_start()`
    *   Options: `cluster_nodes_init :: list(atom())` (initial known nodes), `sync_interval_ms :: pos_integer()`.
*   `setup_cluster(nodes :: list(atom())) :: :ok` (Potentially a high-level setup function)
*   `register_node(node_to_add :: atom()) :: :ok | {:error, :already_exists | term()}`
*   `unregister_node(node_to_remove :: atom()) :: :ok | {:error, :not_found | term()}`
*   `get_cluster_nodes() :: {:ok, list(atom())}`
*   `force_event_sync() :: {:ok, map_of_sync_results_per_node}`
*   `query_distributed_events(filters :: map()) :: {:ok, list(ElixirScope.Events.t())}` (This would fan out queries to all nodes and merge results)
*   `get_distributed_status() :: {:ok, map_with_cluster_health_and_sync_status}`

Via `ElixirScope.Distributed.GlobalClock` (GenServer, mainly for internal use by capture, but might have some public access):
*   `now() :: global_timestamp_type` (where `global_timestamp_type` is a tuple like `{logical_ticks, physical_time_ns, node_id}`)
*   `compare_timestamps(ts1, ts2) :: :lt | :eq | :gt | :concurrent`

## 5. Core Data Structures

Defined in `ElixirScope.Distributed.Types`:

*   **`ClusterNodeInfo.t()`**: `%{node_id: atom(), status: :connected | :disconnected | :syncing, last_seen_global_clock: term(), last_successful_sync_local_time: integer()}`
*   **`EventSyncMessage.t()`**: `%{from_node: atom(), since_global_clock: term(), events_batch: [ElixirScope.Events.t()]}` (Events would be serialized for transit)
*   **`GlobalClockUpdate.t()`**: `%{node_id: atom(), clock_value: term()}`
*   `GlobalTimestamp.t()`: e.g., `{logical_counter :: integer(), physical_monotonic_ns :: integer(), node_id :: atom()}` (for HLCs)
*   Consumes/Produces: `ElixirScope.Events.t()` (serializing/deserializing for inter-node transfer).

## 6. Dependencies

This library will depend on the following ElixirScope libraries:

*   `elixir_scope_utils` (for utilities).
*   `elixir_scope_config` (for its operational parameters like sync intervals, timeouts).
*   `elixir_scope_events` (to serialize/deserialize events for transfer).
*   `elixir_scope_storage` (for `EventSynchronizer` to read local events and store remote events).
*   `elixir_scope_capture_core` (for `InstrumentationRuntime.DistributedReporting` to report node events, and for `GlobalClock` to be accessible by event capture mechanisms).

It will heavily depend on Elixir/OTP's distribution mechanisms (`Node`, `:rpc`, `:net_kernel`).

## 7. Role in TidewaveScope & Interactions

Within the `TidewaveScope` ecosystem, the `elixir_scope_distributed` library will:

*   Be optionally enabled and configured if `TidewaveScope` is intended to operate in or monitor a distributed Elixir application.
*   Allow `TidewaveScope` (via its MCP tools and underlying ElixirScope components) to present a unified view of events and traces from across the entire cluster.
*   Enable AI assistants to ask questions about distributed workflows, e.g., "Trace this request ID X as it moved from Node A to Service B on Node C."
*   The `GlobalClock` timestamps would be used by `elixir_scope_correlator` and `elixir_scope_temporal_debug` to correctly order and interpret events from different nodes.

## 8. Future Considerations & CPG Enhancements

*   **Distributed CPG Analysis:** While complex, future work could involve strategies for querying or even partially merging CPGs from different nodes to analyze distributed interactions at a static level. This library would provide the foundation for identifying which nodes (and thus which CPGs) are involved in a distributed trace.
*   **Dynamic Cluster Membership:** Integration with service discovery mechanisms (e.g., libcluster) for more dynamic cluster formation rather than static configuration.
*   **Advanced Conflict Resolution:** More sophisticated strategies for handling conflicting events or data if a simple timestamp-based approach proves insufficient during network partitions.
*   **Bandwidth Optimization:** Adaptive event batching, further compression, or Bloom filters to reduce the amount of data exchanged during synchronization.
*   **Security:** Secure communication channels for event synchronization if nodes are not within a trusted network.

## 9. Testing Strategy

Testing distributed systems is inherently complex.

*   **`ElixirScope.Distributed.GlobalClock` Unit Tests:**
    *   Test clock initialization and logical time increment.
    *   Test clock updates from remote timestamps, ensuring correct merging logic (e.g., Lamport or HLC rules).
    *   Test timestamp comparison.
*   **`ElixirScope.Distributed.EventSynchronizer` Unit Tests:**
    *   Mock `elixir_scope_storage` and the `Transport` module.
    *   Test fetching local events since a certain time.
    *   Test preparing events for sync (serialization, compression).
    *   Test storing received remote events, including de-duplication logic.
*   **`ElixirScope.Distributed.NodeCoordinator` GenServer Tests:**
    *   Test node registration and unregistration, verifying cluster state updates.
    *   Test handling of `:nodeup` and `:nodedown` messages.
    *   Test initiation of periodic syncs.
    *   Mock `EventSynchronizer` and `GlobalClock` to test coordination logic.
*   **Multi-Node Integration Tests (using `Node.start/3`, `Node.connect/1`):**
    1.  Set up a small local cluster of 2-3 Elixir nodes.
    2.  Start `elixir_scope_distributed` (and its dependencies like a mock storage) on each node.
    3.  Have `NodeCoordinator` on one node call `setup_cluster`.
    4.  Generate events on one node.
    5.  Trigger `force_event_sync` (or wait for periodic sync).
    6.  Verify that events from the first node appear in the mock storage of other nodes.
    7.  Simulate network partitions (e.g., `Node.disconnect/1`) and verify partition detection and recovery/resync behavior.
    8.  Test distributed queries.
*   **Test with varying network latencies and conditions (if possible, using tools to simulate network issues).**
