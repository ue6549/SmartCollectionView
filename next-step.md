# Modularization and Performance Improvements Plan

## Overview

This plan has two phases:

1. **Phase 1: Modularization & Rearchitecture** - Split monolithic SmartCollectionView into focused components
2. **Phase 2: High Priority Performance Blockers** - Implement critical optimizations on the new architecture

## Phase 1: Modularization & Rearchitecture

### Current Problems

- **Monolithic Design**: All logic (layout, visibility, mounting, events) in one 1400+ line file
- **Mixed Concerns**: Layout computation, visibility tracking, mount/unmount all intertwined
- **Hard to Test**: Can't test components in isolation
- **Hard to Optimize**: Changes affect entire class
- **No Clear Separation**: Cache, scheduler, mount controller logic mixed together

### Target Architecture

Refactor into 5 focused components matching Requirements.md design:

1. **SmartCollectionViewScheduler** - Orchestrates operations, coordinates other components
2. **SmartCollectionViewLayoutCache** - Manages layout specs, eviction, validity states
3. **SmartCollectionViewMountController** - Handles mount/unmount operations, recycling
4. **SmartCollectionViewVisibilityTracker** - Computes visible ranges, binary search
5. **SmartCollectionViewEventBus** - Throttled, coalesced event emission

### Implementation Steps

#### Step 1.1: Create SmartCollectionViewLayoutCache

**Files to Create:**

- `SmartCollectionViewPOC/ios/SmartCollectionView/SmartCollectionViewLayoutCache.h`
- `SmartCollectionViewPOC/ios/SmartCollectionView/SmartCollectionViewLayoutCache.m`

**Responsibilities:**

- Store layout specs (frames, validity, version, timestamps)
- Provide get/put/invalidate methods
- Implement eviction logic (LRU + distance-based)
- Track cache statistics

**Interface:**

```objc
@protocol SmartCollectionViewLayoutCacheDelegate;

@interface SmartCollectionViewLayoutCache : NSObject
@property (nonatomic, weak) id<SmartCollectionViewLayoutCacheDelegate> delegate;
@property (nonatomic, assign) NSInteger maxCacheSize; // Configurable budget

- (SmartCollectionViewLayoutSpec *)specForKey:(NSString *)key;
- (void)putSpec:(SmartCollectionViewLayoutSpec *)spec forKey:(NSString *)key;
- (void)invalidateKey:(NSString *)key version:(NSInteger)version;
- (void)evictIfNeeded:(NSRange)visibleRange;
- (NSDictionary *)stats; // hits, misses, evictions
@end
```

**Migration Strategy:**

- Extract `_layoutCache` dictionary and related logic
- Move `performFullLayoutRecompute` cache updates here
- Move eviction logic (from Phase 2 Step 1.3) here
- SmartCollectionView calls cache methods instead of direct dictionary access

#### Step 1.2: Create SmartCollectionViewVisibilityTracker

**Files to Create:**

- `SmartCollectionViewPOC/ios/SmartCollectionView/SmartCollectionViewVisibilityTracker.h`
- `SmartCollectionViewPOC/ios/SmartCollectionView/SmartCollectionViewVisibilityTracker.m`

**Responsibilities:**

- Compute visible item range using binary search
- Expand visible range to buffer range (overscan)
- Track scroll offset and viewport
- Binary search on cumulative offsets

**Interface:**

```objc
@interface SmartCollectionViewVisibilityTracker : NSObject
- (void)setScrollOffset:(CGFloat)offset;
- (void)setViewportSize:(CGSize)size;
- (void)setCumulativeOffsets:(NSArray<NSNumber *> *)offsets;
- (void)setItemSizes:(NSArray<NSValue *> *)sizes; // For intersection calculation

- (NSRange)computeVisibleRange;
- (NSRange)expandToBuffer:(NSRange)visibleRange 
             overscanCount:(NSInteger)overscanCount
            overscanLength:(CGFloat)overscanLength;
@end
```

**Migration Strategy:**

- Extract `visibleItemRange` method
- Extract `computeRangeToLayout` logic
- Extract `getCumulativeOffsetAtIndex` helper
- Move binary search logic here
- SmartCollectionView calls tracker instead of computing directly

#### Step 1.3: Enhance SmartCollectionViewMountController

**Files to Modify:**

- `SmartCollectionViewPOC/ios/SmartCollectionView/SmartCollectionViewMountController.h`
- `SmartCollectionViewPOC/ios/SmartCollectionView/SmartCollectionViewMountController.m`

**Current State:**

- Basic mount/unmount exists but is underutilized
- Logic mostly in SmartCollectionView.m

**Enhancements:**

- Move all mount/unmount logic from SmartCollectionView.m
- Add wrapper recycling management
- Add batch mounting support
- Add mount state tracking

**Interface:**

```objc
@protocol SmartCollectionViewMountControllerDelegate;

@interface SmartCollectionViewMountController : NSObject
@property (nonatomic, weak) id<SmartCollectionViewMountControllerDelegate> delegate;
@property (nonatomic, strong) UIView *containerView;

- (void)mountItem:(UIView *)item atIndex:(NSInteger)index withFrame:(CGRect)frame;
- (void)unmountItemAtIndex:(NSInteger)index;
- (void)mountItemsBatch:(NSArray<NSNumber *> *)indices 
              withFrames:(NSDictionary<NSNumber *, NSValue *> *)frames
            withViews:(NSDictionary<NSNumber *, UIView *> *)views;
- (NSArray<NSNumber *> *)mountedIndices;
- (BOOL)isMountedAtIndex:(NSInteger)index;
- (void)updateFrameForItemAtIndex:(NSInteger)index frame:(CGRect)frame;
@end
```

**Migration Strategy:**

- Move `mountItemAtIndex:` from SmartCollectionView.m
- Move `unmountItemAtIndex:` from SmartCollectionView.m
- Move wrapper pool management
- Move `updateVisibleItems` mounting logic here
- SmartCollectionView delegates mounting to controller

#### Step 1.4: Create SmartCollectionViewEventBus

**Files to Create:**

- `SmartCollectionViewPOC/ios/SmartCollectionView/SmartCollectionViewEventBus.h`
- `SmartCollectionViewPOC/ios/SmartCollectionView/SmartCollectionViewEventBus.m`

**Responsibilities:**

- Throttle scroll events (default 16ms)
- Coalesce visibility range events (default 120ms)
- Debounce scroll end events
- Emit events to JS via callbacks

**Interface:**

```objc
@protocol SmartCollectionViewEventBusDelegate;

@interface SmartCollectionViewEventBus : NSObject
@property (nonatomic, weak) id<SmartCollectionViewEventBusDelegate> delegate;
@property (nonatomic, assign) NSTimeInterval scrollEventThrottle; // ms
@property (nonatomic, assign) NSTimeInterval rangeEventThrottle; // ms

- (void)onScroll:(CGFloat)offset velocity:(CGFloat)velocity;
- (void)onVisibleRangeChange:(NSRange)range;
- (void)onScrollEnd;
- (void)onScrollBeginDrag;
- (void)onScrollEndDrag;
- (void)onMomentumScrollBegin;
- (void)onMomentumScrollEnd;
@end
```

**Migration Strategy:**

- Extract event emission from `scrollViewDidScroll`
- Extract `requestItemsForVisibleRange` event logic
- Move all `self.onXxx` callback calls here
- SmartCollectionView calls event bus, bus handles throttling/coalescing

#### Step 1.5: Create SmartCollectionViewScheduler

**Files to Create:**

- `SmartCollectionViewPOC/ios/SmartCollectionView/SmartCollectionViewScheduler.h`
- `SmartCollectionViewPOC/ios/SmartCollectionView/SmartCollectionViewScheduler.m`

**Responsibilities:**

- Orchestrate layout, visibility, and mounting
- Coordinate between LayoutCache, VisibilityTracker, MountController
- Plan operations (what to mount/unmount)
- Manage policy (overscan, batch sizes, etc.)

**Interface:**

```objc
@protocol SmartCollectionViewSchedulerDelegate;

@interface SmartCollectionViewScheduler : NSObject
@property (nonatomic, weak) id<SmartCollectionViewSchedulerDelegate> delegate;
@property (nonatomic, strong) SmartCollectionViewLayoutCache *layoutCache;
@property (nonatomic, strong) SmartCollectionViewVisibilityTracker *visibilityTracker;
@property (nonatomic, strong) SmartCollectionViewMountController *mountController;
@property (nonatomic, strong) SmartCollectionViewEventBus *eventBus;

// Policy
@property (nonatomic, assign) NSInteger initialNumToRender;
@property (nonatomic, assign) NSInteger maxToRenderPerBatch;
@property (nonatomic, assign) NSInteger overscanCount;
@property (nonatomic, assign) CGFloat overscanLength;

- (void)onScrollOffsetChange:(CGFloat)offset;
- (void)onViewportChange:(CGSize)size;
- (void)onDataChange:(NSArray *)items; // Triggers layout recompute
- (void)update; // Main update loop - called after scroll/viewport/data changes
- (NSRange)visibleRange;
- (NSRange)bufferRange;
@end
```

**Migration Strategy:**

- Move orchestration logic from SmartCollectionView
- Move `updateVisibleItems` coordination here
- Move `mountVisibleItemsWithBatching` logic here
- SmartCollectionView delegates to scheduler for most operations

#### Step 1.6: Refactor SmartCollectionView to Use Components

**File to Modify:**

- `SmartCollectionViewPOC/ios/SmartCollectionView/SmartCollectionView.m`

**Changes:**

- Remove direct `_layoutCache` access - use `_scheduler.layoutCache`
- Remove `visibleItemRange` - use `_scheduler.visibilityTracker`
- Remove mount/unmount logic - use `_scheduler.mountController`
- Remove event emission - use `_scheduler.eventBus`
- Keep only: scroll delegate, prop setters, initialization, component coordination

**New Structure:**

```objc
@interface SmartCollectionView ()
@property (nonatomic, strong) SmartCollectionViewScheduler *scheduler;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *containerView;
// Minimal state - most in scheduler
@end

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self.scheduler.eventBus onScroll:offset velocity:velocity];
    [self.scheduler onScrollOffsetChange:offset];
    [self.scheduler update];
}
```

**File Size Reduction:**

- Current: ~1400 lines
- Target: ~300-400 lines (coordination + props)
- Components: ~200-300 lines each

#### Step 1.7: Update Integration Points

**Files to Modify:**

- `SmartCollectionViewPOC/ios/SmartCollectionView/SmartCollectionViewManager.m`
- `SmartCollectionViewPOC/ios/SmartCollectionView/SmartCollectionViewShadowView.m`

**Changes:**

- Ensure `setLocalData:forView:` still works with new architecture
- Update any direct cache/visibility access (should go through scheduler)
- Verify shadow view height calculation still works

### Testing Strategy

1. **Unit Tests**: Test each component in isolation
2. **Integration Tests**: Verify components work together
3. **Regression Tests**: Ensure existing functionality still works
4. **Performance Tests**: Verify no performance regression

### Migration Checklist

- [x] Create LayoutCache component, migrate cache logic
- [x] Create VisibilityTracker component, migrate visibility logic
- [x] Enhance SmartCollectionViewMountController, migrate mount/unmount logic
- [x] Create SmartCollectionViewEventBus, migrate event logic
- [x] Create SmartCollectionViewScheduler, migrate orchestration logic
- [ ] Refactor SmartCollectionView to use components
- [ ] Test all functionality still works
- [ ] Verify no performance regression
- [ ] Update documentation

### Additional Follow-ups
- Consider exposing a more granular public API with internal properties kept entirely private once refactor stabilises.

---

## Phase 2: High Priority Performance Blockers

### Overview

After modularization, implement the critical performance optimizations using the new component architecture.

### 1. View Recycling Optimization (Priority: Critical)

#### Implementation

**Files to Create:**

- `SmartCollectionViewPOC/ios/SmartCollectionView/SmartCollectionViewReusePool.h/m`

**Files to Modify:**

- `SmartCollectionViewPOC/src/components/SmartCollectionView.tsx` - Add getItemType prop
- `SmartCollectionViewPOC/ios/SmartCollectionView/SmartCollectionViewMountController.m` - Integrate reuse pool

**Changes:**

- MountController uses ReusePool for React children
- ReusePool keyed by item type
- PrepareForReuse protocol support
- Enqueue on unmount, dequeue on mount

**Integration:**

- MountController owns ReusePool instance
- Scheduler provides type information to MountController
- Views are reused across indices of same type

### 2. Key-Based Diffing (Priority: Critical)

#### Implementation

**Files to Modify:**

- `SmartCollectionViewPOC/src/components/SmartCollectionView.tsx` - Add keyExtractor prop
- `SmartCollectionViewPOC/ios/SmartCollectionView/SmartCollectionViewLocalData.h/m` - Add key to metadata
- `SmartCollectionViewPOC/ios/SmartCollectionView/SmartCollectionViewScheduler.m` - Add key mapping and diffing

**Changes:**

- Scheduler maintains `keyToIndex` and `indexToKey` mappings
- LayoutCache uses keys instead of indices
- Scheduler implements `diffKeysAndInvalidateCache:` method
- Called on data changes before layout recompute

**Integration:**

- VisibilityTracker still uses indices (for cumulative offsets)
- Scheduler converts between keys and indices
- LayoutCache is key-based
- MountController receives indices (for view lookup) and keys (for cache lookup)

#### Testing Strategy

**Test Cases:**

1. **Data Insertion**
   - Insert item at beginning: verify cache invalidation, remounts
   - Insert item in middle: verify cache invalidation, remounts
   - Insert item at end: verify cache invalidation, remounts

2. **Data Deletion**
   - Delete item at beginning: verify cache cleanup, unmounts
   - Delete item in middle: verify cache cleanup, unmounts
   - Delete item at end: verify cache cleanup, unmounts

3. **Data Reordering**
   - Swap two items: verify keys maintained, views reused
   - Reverse list: verify all keys maintained, views reused
   - Shuffle items: verify keys maintained, minimal remounts

4. **Data Updates**
   - Update item props: verify view updated, not remounted
   - Update item key: verify view remounted with new key

5. **Edge Cases**
   - Empty list → add items: verify initial mount
   - Full list → clear: verify all unmounts
   - Duplicate keys: verify error handling

**Metrics to Track:**

- Number of remounts vs. updates
- Cache hit rate before/after diffing
- Layout recompute time
- Memory usage

### 3. Placeholder/Speculative Rendering (Priority: High)

**See:** `placeholder-speculative-rendering.md` for detailed proposal.

#### Overview

Implement placeholder (skeleton) views outside the overscan range, promoting them to real content views when entering overscan. This defers expensive native subtree creation until necessary.

#### Implementation

**Files to Create:**

- `SmartCollectionViewPOC/ios/SmartCollectionView/SmartCollectionViewItemShadowView.h/m`
- `SmartCollectionViewPOC/ios/SmartCollectionView/SmartCollectionViewItemView.h/m`
- `SmartCollectionViewPOC/ios/SmartCollectionView/SmartCollectionViewItemManager.h/m`

**Files to Modify:**

- `SmartCollectionViewPOC/ios/SmartCollectionView/SmartCollectionViewMountController.m` - Handle promotion/demotion
- `SmartCollectionViewPOC/ios/SmartCollectionView/SmartCollectionViewScheduler.m` - Track placeholder ranges

**Changes:**

- Create item shadow view with measure function
- Create item view with placeholder/content states
- MountController handles promotion/demotion
- Scheduler tracks `rangeToMount` (content) vs `rangeToRequest` (placeholders)

**Integration:**

- Items in `rangeToMount` have content views
- Items in `rangeToRequest` but outside `rangeToMount` have placeholders
- Promotion happens synchronously when item enters overscan
- Demotion recycles content views and restores placeholders

### 4. Layout Cache Eviction (Priority: Medium)

#### Implementation

**File to Modify:**

- `SmartCollectionViewPOC/ios/SmartCollectionView/SmartCollectionViewLayoutCache.m`

**Changes:**

- Implement `evictIfNeeded:` method in LayoutCache component
- Use distance from visible center + LRU timestamp
- Set cache budget (3x visible range)
- Update `putSpec:forKey:` to track timestamps
- Call eviction automatically when cache exceeds budget

**Integration:**

- Scheduler calls `[layoutCache evictIfNeeded:visibleRange]` after layout updates
- No changes needed in SmartCollectionView (already uses scheduler)

#### Step 4.1: Create LayoutSpec with Validity States

**Files to Create:**

- `SmartCollectionViewPOC/ios/SmartCollectionView/SmartCollectionViewLayoutSpec.h`
- `SmartCollectionViewPOC/ios/SmartCollectionView/SmartCollectionViewLayoutSpec.m`

**Key Components:**

- `typedef NS_ENUM(NSInteger, LayoutValidity) { LayoutValidityMissing, LayoutValidityEstimated, LayoutValidityExact }`
- `@interface SmartCollectionViewLayoutSpec : NSObject`
  - `@property CGRect frame`
  - `@property LayoutValidity validity`
  - `@property NSInteger version`
  - `@property NSTimeInterval timestamp` (for LRU)
  - `@property NSString *key` (for key-based lookup)

**Integration:**

- LayoutCache stores LayoutSpec objects
- Layout computation creates specs with Estimated validity
- After measurement, upgrade to Exact validity

---

## Implementation Order

### Phase 1: Modularization (Weeks 1-2)

1. **Week 1: Core Components**

   - Day 1-2: Create LayoutCache component
   - Day 3-4: Create VisibilityTracker component
   - Day 5: Create EventBus component

2. **Week 2: Orchestration & Integration**

   - Day 1-2: Enhance MountController
   - Day 3-4: Create Scheduler component
   - Day 5: Refactor SmartCollectionView, test integration

### Phase 2: Performance Optimizations (Weeks 3-6)

3. **Week 3: View Recycling**

   - Create ReusePool component
   - Integrate with MountController
   - Add PrepareForReuse support
   - Test memory and performance

4. **Week 4: Key-Based Diffing**

   - Add keyExtractor to JS API
   - Implement key mapping in Scheduler
   - Update LayoutCache to use keys
   - Test data mutations (see testing strategy above)

5. **Week 5: Placeholder/Speculative Rendering**

   - Create SmartCollectionViewItemShadowView with measure function
   - Create SmartCollectionViewItemView with placeholder/content states
   - Create SmartCollectionViewItemManager
   - Integrate promotion/demotion with MountController
   - Test placeholder size matching, promotion timing, demotion recycling

6. **Week 6: Layout Cache Eviction**

   - Create LayoutSpec with validity states
   - Implement eviction in LayoutCache
   - Test memory stability

## Benefits of This Approach

1. **Cleaner Architecture**: Each component has single responsibility
2. **Easier Testing**: Components can be tested in isolation
3. **Easier Optimization**: Can optimize each component independently
4. **Better Maintainability**: Changes are localized to relevant components
5. **Matches Requirements.md**: Aligns with original design document
6. **Prepares for Future**: Makes it easier to add async layout queue, two-phase commit, etc.

## Success Criteria

**Phase 1:**

- ✅ SmartCollectionView reduced to ~300-400 lines
- ✅ 5 focused components created
- ✅ All existing functionality still works
- ✅ No performance regression

**Phase 2:**

- ✅ Views are reused, not recreated (Recycling)
- ✅ Data mutations work correctly with minimal remounts (Key-Based Diffing)
- ✅ Placeholders promote smoothly without layout jank (Placeholder/Speculative Rendering)
- ✅ Cache doesn't exceed 3x visible range (Layout Cache Eviction)
- ✅ Memory usage stays stable
- ✅ Performance metrics match or beat FlatList

## Files Summary

**Phase 1 New Files:**

- `SmartCollectionViewLayoutCache.h/m`
- `SmartCollectionViewVisibilityTracker.h/m`
- `SmartCollectionViewEventBus.h/m`
- `SmartCollectionViewScheduler.h/m` (new, enhanced from existing)

**Phase 1 Modified Files:**

- `SmartCollectionView.m` (major refactor)
- `SmartCollectionViewMountController.h/m` (enhancement)

**Phase 2 New Files:**

- `SmartCollectionViewReusePool.h/m` (Week 3: Recycling)
- `SmartCollectionViewItemShadowView.h/m` (Week 5: Placeholder)
- `SmartCollectionViewItemView.h/m` (Week 5: Placeholder)
- `SmartCollectionViewItemManager.h/m` (Week 5: Placeholder)
- `SmartCollectionViewLayoutSpec.h/m` (Week 6: Cache Eviction)

**Phase 2 Modified Files:**

- `SmartCollectionViewMountController.m` (add recycling, promotion/demotion)
- `SmartCollectionViewScheduler.m` (add key mapping, placeholder range tracking)
- `SmartCollectionViewLayoutCache.m` (add eviction)
- `SmartCollectionView.tsx` (add keyExtractor, getItemType)
- `SmartCollectionViewLocalData.h/m` (add key)

