SmartCollectionView for React Native legacy architecture (0.72.3)

A native-driven, virtualization-focused collection view for React Native’s legacy architecture. It balances smoothness and memory with tiered layout caching, native scheduling, and a familiar JS API. Designed to be forward-compatible with view recycling and, later, Fabric.

---

High-level design

Goals

• Native scheduling: Make visibility, mounting, and layout decisions natively to avoid per-frame JS overhead.
• Tiered layout caching: Keep exact or estimated layout specs for a configurable buffer; evict cold items.
• JS policy, native mechanism: JS sets window sizes, overscan, buffers, and batching; native executes.
• FlatList-like API: Maintain familiar ergonomics and allow migration from JS virtualization.
• Forward-compatible recycling: Enable view reuse keyed by item type without fixed templates.
• Deterministic layouts: Use native layout providers for list/grid/waterfall with consistent outputs.


Core ideas

• Shadow-node mirror, not mutation: Compute layout with an internal Yoga context; don’t write to RN’s shadow tree. Use frames to position mounted subviews.
• Two-phase commit: Prepare operations asynchronously; apply UI mutations in a single runloop pass.
• Ranges as tiers: Visible (mounted views), Buffer (layout-only specs), Cold (metadata only).
• Key-based diffing: Cache and schedule by stable keys, not indices, to handle inserts/removals cleanly.
• Dual-channel events: Fast scroll events for visuals; coalesced range events for logic.


---

JS API surface

<SmartCollectionView
  data={data}
  keyExtractor={(item, index) => item.id}
  renderItem={({ item, index }) => <ItemView item={item} index={index} />}
  getItemType={(item, index) => item.type} // reuse ID / view type
  estimatedItemSize={({ item, index }) => ({ width: 100, height: 80 })}

  // Virtualization and layout policy
  windowSize={10}                 // “screens” (viewport multiples)
  overscanCount={8}               // extra items before/after viewport
  initialRenderCount={12}         // staged first paint (see defaults)
  batchRenderCount={6}
  layoutBufferScreens={3}         // preferred buffer sizing (screens)
  layoutBufferSize={50}           // optional count-based override

  // Layout provider presets
  layoutProvider={(index) => 'list' | 'grid' | 'waterfall'}

  // Events
  onVisibleRangeChange={({ first, last }) => {}}
  onScroll={({ offset, velocity }) => {}}
  onScrollEnd={() => {}}
  onPrefetch={({ first, last }) => {}}

  // Throttling and tuning
  scrollEventThrottle={16}        // ms, like ScrollView
  rangeEventThrottle={120}        // ms, coalesced visibility updates
  keepFocusedItemMounted={false}  // a11y pinning

  // Optional decorators
  ItemSeparatorComponent={Separator}
  ListHeaderComponent={Header}
  ListFooterComponent={Footer}

  ref={ref} // commands: scrollToIndex, scrollToOffset, reloadItems, invalidateItem
/>


• Conflict resolution: If both layoutBufferScreens and layoutBufferSize are set, prefer screens and warn.
• Keys/types: Require stable keys via keyExtractor; getItemType returns a finite set of strings for future recycling.


---

Architecture overview

Threads and ownership

• JS thread: Data source, renderItem tree creation, policy updates, commands.
• UI thread: Scroll handling, visibility computation, batch apply of mutations.
• Layout queue: Async layout generation (Yoga, provider frames), cache updates.


Native components

• Scheduler: Visibility tracking, range computation, operation planning, two-phase commit.
• Layout cache: Per-key layout specs (frames, validity, version, timestamps) with eviction.
• Mount controller: Attach/detach/bind views; no sync reads; prepares recycling hooks.
• Visibility tracker: Maps offset/viewport to visible indices; expands to buffers; optional prediction.
• Event bus: Coalesces and emits scroll, range, content size, prefetch events.


Data flow

• JS → native props: Data length, keys/types, estimates, policy knobs.
• Native → layout: Provider computes frames; cache stores specs; scheduler plans ops.
• Native apply: UI thread mounts/detaches/binds in batches; no per-frame JS.
• Native → JS events: Throttled onScroll, coalesced onVisibleRangeChange; debounced onScrollEnd.


---

Design decisions reflecting concerns

Layout queue threading model

• Read-only mirror: Do not touch RN’s main shadow tree. Compute frames via an internal Yoga context and deterministic layout providers.
• Atomicity: Produce immutable “commit packets” with sequence numbers; UI applies the latest only.
• Synchronization: Layout work on a dedicated queue; results consumed atomically by UI thread.


Mount/detach batching

• Two-phase commit: Prepare (async) and Apply (UI) to avoid partial states.
• No sync layout reads: Avoid convertPoint:toView: or forced measures during Apply; rely on precomputed frames.


Text run caching

• Phase 1: skip. Introduce later with a separate cache keyed by (attributedString fingerprint, constraint width, traitCollection). Independent memory budget and invalidation on font/locale/theme changes.


renderItem bridge overhead

• Stable instances: Keep mounted instances stable within the visible window; rebind props only.
• Prefer core native views: Encourage compositions of RCTView/RCTText/RCTImageView; avoid custom native views per item unless necessary.
• Instrumentation: Warn on slow renderItem; track bind latency by type.
• Future fast-path: Optional data-driven descriptors (Epoxy/Litho-like) to bind natively without JS tree regeneration.


Scroll event coalescing

• Dual-channel: scrollEventThrottle (default 16–33 ms) for visuals; rangeEventThrottle (default ~120 ms) for visibility logic. Debounce onScrollEnd.
• Configurable: Expose throttles; adapt on device performance.


Sticky headers

• Phase 1: exclude. Phase 2: add an overlay layer separate from virtualized content for continuous translations and correct z-ordering.


Accessibility

• Lifecycle: Reset traits/labels/hints/actions on reuse. Optional keepFocusedItemMounted to avoid focus drop during scroll.
• Testing: Include VoiceOver/TalkBack scenarios; ensure stable a11y trees and focus retention.


Defaults for buffers

• Screen-based first: layoutBufferScreens = 3 by default (above + below).
• Device adaptive: Phones ≥ 2 screens; tablets ≥ 3 screens. Count-based override via layoutBufferSize.


Separators

• ItemSeparatorComponent: Supported; treated as lightweight items with deterministic minimal layout until measured.


Prefetch

• onPrefetch(range): Emitted when buffer expands; include cancellation tokens if the range shifts before completion.


Key-based diff

• Cache by key, not index: Maintain key→index mapping; diff keys on data changes; remap indices for frames and mounted views.


---

Low-level design

Data structures

• ItemFrame• Key: Stable key from keyExtractor.
• Type: Reuse ID from getItemType.
• x, y, width, height: Content coordinates.
• estimated: Boolean; true until exact layout measured.
• baseline, margins: Optional text/layout metrics.
• version: Monotonic, bumps on data/style updates.

• LayoutSpec• key, type: Identity.
• frame: ItemFrame.
• validity: enum { Missing, Estimated, Exact }.
• yogaNodeRef / textRuns: Opaque handles or serialized minimal state.
• timestamp: For LRU and performance heuristics.

• Range• firstKey, lastKey: Bounds (internally tracked also as indices).
• kind: enum { Visible, Buffer, Cold }.

• Policy• windowSize, overscanCount
• initialRenderCount, batchRenderCount
• layoutBufferScreens, layoutBufferSize
• scrollEventThrottle, rangeEventThrottle
• predictionHorizonMs
• keepFocusedItemMounted

• Operation• type: Attach | Detach | Bind | AnimateSizeChange.
• key: Target item.
• payload: Frame, version, type-specific params.
• seq: Sequence number for atomic apply.



Interfaces

• Scheduler• setPolicy(policy: Policy): void
• onScroll(offset: number, velocity: number): void
• onDataChange(changedKeys: string[]): void
• onViewportChange(size: Size, insets: Insets): void
• prepareOperations(): OperationPacket // async
• applyOperations(packet: OperationPacket): void // UI thread
• getVisibleRange(): Range
• getBufferRange(): Range
• debugSnapshot(): SchedulerSnapshot

• LayoutCache• get(key: string): LayoutSpec | null
• put(spec: LayoutSpec): void
• invalidate(key: string, version?: number): void
• evict(keys: string[]): void
• stats(): { hits: number, misses: number, evictions: number }

• MountController• mount(keys: string[]): void
• detach(keys: string[]): void
• bind(key: string, spec: LayoutSpec, dataVersion: number): void
• isMounted(key: string): boolean
• mountedKeys(): string[]
• applyOperations(ops: Operation[], seq: number): void

• VisibilityTracker• computeVisibleRange(offset: number, viewport: Size): Range
• expandToBuffer(visible: Range, policy: Policy): Range
• predict(offset: number, velocity: number, horizonMs: number): Range

• EventBus• emitScroll(offset: number, velocity: number): void
• emitVisibleRange(range: Range): void
• emitContentSize(size: Size): void
• emitPrefetch(range: Range, token: string): void
• cancelPrefetch(token: string): void



Algorithms

Range computation

1. Inputs: content offset, viewport size, cumulative heights or provider mapping, policy.
2. Visible indices: Binary search on cumulative offsets to find first/last intersecting frames.
3. Buffer expansion: Add overscanCount and windowSize-based screens around visible bounds; clamp to data length.
4. Cold range: Outside buffer bounds; mark for eviction.


Layout precompute

1. For each key in buffer range:• If cache has Exact or Estimated: skip.
• Else compute via layout provider + Yoga; create LayoutSpec with Estimated=true initially if needed.

2. Eviction policy: If cache exceeds budget:• Sort candidates by distance from visible center; tie-break by LRU timestamp.
• Evict until within budget; retain minimal metadata (type, estimated size).



Mount scheduling

1. Diff: newlyVisible = visibleKeys − mountedKeys; newlyInvisible = mountedKeys − visibleKeys.
2. Detach first: Produce Detach ops for newlyInvisible (respect keepFocusedItemMounted if needed).
3. Attach in batches: Use initialRenderCount for first paint, then batchRenderCount.
4. Bind: For each attached key, Bind with cached frame; if Estimated→Exact transition occurs later, emit AnimateSizeChange.


Two-phase commit

• Prepare (async): Build OperationPacket { seq, ops[], contentSize?, eventsPending }.
• Apply (UI): Single applyOperations(packet) that performs mutations atomically. Ignore packets with seq < latest applied.


Event coalescing

• scrollEventThrottle: Emit onScroll at configured intervals; latest value wins within each window.
• rangeEventThrottle: Emit onVisibleRangeChange when bounds change; coalesce updates to the latest per window.
• onScrollEnd: Debounced after last scroll event.


---

Accessibility

• PrepareForReuse: Reset accessibilityTraits, labels, hints, actions, focusable state.
• Focus retention: Optional keepFocusedItemMounted keeps the currently focused item in the hierarchy slightly beyond the visible range to avoid focus loss.
• Tests: Include scenarios for VO/TalkBack navigation, rotor actions, and focus movement across virtualization boundaries.


---

Sticky headers (phase 2)

• Overlay layer: Maintain sticky headers in a separate mount surface above the scroll content.
• Continuous updates: Translate sticky header positions each scroll tick on UI thread without relayout.
• Z-order: Ensure headers overlay content without intercepting unintended gestures.


---

Defaults and tuning

• layoutBufferScreens: 3 by default; adaptive minimums based on device class.
• scrollEventThrottle: 16 ms default (or display refresh aligned).
• rangeEventThrottle: 120 ms default.
• initialRenderCount: Progressive first paint (e.g., 6 immediately, +6 next tick) before enabling full virtualization and buffer expansion.


---

Future extensions

• View recycling (phase 2): Reuse pool per type with PrepareForReuse, fast prop binding, animation policies for size changes.
• Text run caching (phase 2+): Dedicated cache with trait-based invalidation and a memory budget.
• Advanced layouts: Waterfall with variable spans, sections, sticky headers, orthogonal scrolling lanes.
• Fast-path descriptors: Optional data-driven item specs bound natively (Epoxy/Litho-like) for highly dynamic feeds.
• Fabric compatibility: Map scheduler operations to Fabric’s mounting transactions and ComponentDescriptors.


---

Pseudocode sketches

Scheduler main loop

onScroll(offset, velocity):
  visible = visibilityTracker.computeVisibleRange(offset, viewport)
  buffer   = visibilityTracker.expandToBuffer(visible, policy)
  cold     = complement(buffer)

  // Precompute missing specs for buffer
  enqueue layoutQueue.task(buffer.keys - layoutCache.keys):
    specs = provider.computeSpecs(keys, viewport, estimates)
    for spec in specs:
      layoutCache.put(spec)

  // Evict cold
  evictCandidates = layoutCache.keys ∩ cold.keys
  evictByDistanceThenLRU(evictCandidates, policy.bufferBudget)

  // Plan operations
  mounted = mountController.mountedKeys()
  toDetach = mounted - visible.keys
  toAttach = visible.keys - mounted

  ops = []
  for k in toDetach: ops.push(Detach(k))
  for k in batched(toAttach, batchSize(policy)): 
    spec = layoutCache.get(k) or makeEstimated(k)
    ops.push(Attach(k))
    ops.push(Bind(k, spec.frame, spec.version))

  packet = OperationPacket(seq++, ops)
  applyOnUI(packet)


Two-phase commit apply

applyOnUI(packet):
  if packet.seq <= latestAppliedSeq: return
  latestAppliedSeq = packet.seq

  mountController.applyOperations(packet.ops, packet.seq)

  // Coalesced events
  eventBus.emitVisibleRangeIfChanged()
  eventBus.emitScrollThrottled()


Key-based diff on data change

onDataChange(changedKeys):
  for key in changedKeys:
    layoutCache.invalidate(key, version+1)

  // Recompute visible/buffer decisions with updated specs
  prepareOperations()


---

Implementation milestones

1. Foundation (phase 1, no recycling)• LayoutCache with key-based entries, eviction (distance + LRU), versioning.
• VisibilityTracker with cumulative offsets and screen-based buffer expansion.
• Scheduler with two-phase commit and operation packets.
• MountController that applies Attach/Detach/Bind without sync reads.
• EventBus with dual-channel throttling; Prefetch callbacks.
• JS wrapper with prop validation, defaults, and dev instrumentation.

2. Stabilization• Instrument renderItem and bind latency; provide developer guidance.
• Handle estimate→exact transitions with optional native animations.
• A11y test suite and keepFocusedItemMounted behavior.

3. Recycling (optional)• ReusePool keyed by getItemType; size caps; PrepareForReuse protocol.
• Fast bind path; animation policies for size changes.

4. Advanced features• Sticky headers overlay, sections, grids/waterfalls.
• Prefetch cancellation tokens, heuristic buffer auto-tuning.

5. Fabric exploration• Map scheduler outputs to Fabric’s MountingCoordinator transactions.
• ComponentDescriptors for typed view reuse.