# Placeholder/Speculative Rendering for SmartCollectionView

## Goal

Implement a custom view manager and shadow view for list child items that:
- Mounts placeholders (skeleton views) outside the overscan range
- Promotes placeholders to real content views when items enter overscan
- Defers expensive native subtree creation until necessary
- Preserves RN reconciliation invariants (tags, layout, props)
- Prepares for view recycling as a next optimization step

## Architecture Components

### Child Item Shadow View (SmartCollectionViewItemShadowView)

**Extends:** `RCTShadowView`

**Responsibilities:**
- Measurement and tracking overscan/speculative state
- Exposes flags: `isInOverscan`, `isInSpeculativeRange`
- Implements Yoga measure function using props (text length, image aspect, etc.) to return deterministic size

**Key Methods:**
```objc
- (CGSize)measureWithWidth:(CGFloat)width heightMode:(YGMeasureMode)heightMode;
- (BOOL)isInOverscanRange;
- (BOOL)isInSpeculativeRange;
```

### Child Item View Manager (SmartCollectionViewItemManager)

**Extends:** `RCTViewManager`

**Responsibilities:**
- Returns a container view (`SmartCollectionViewItemView`) with:
  - `placeholderView` (lightweight skeleton)
  - `contentView` (real content, recycled when possible)
- Controls promotion/demotion logic

**Key Methods:**
```objc
- (UIView *)view; // Returns SmartCollectionViewItemView
- (RCTShadowView *)shadowView; // Returns SmartCollectionViewItemShadowView
```

### Child Item View (SmartCollectionViewItemView)

**Extends:** `UIView`

**Two States:**
1. **Placeholder mounted** (outside overscan)
2. **Content mounted** (inside overscan)

**Requirements:**
- Must maintain stable `reactTag` and size across states
- Container view remains constant
- Children swapped inside container, not replaced wholesale

**Key Properties:**
```objc
@property (nonatomic, strong) UIView *placeholderView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, assign) BOOL isPlaceholderMode;
```

## Functional Requirements

### Shadow View

- Must compute size consistently from props, even if content not mounted
- Must expose overscan/speculative flags to native virtualization logic
- Must cache layout metrics (width, height) for reuse during promotion

### View Manager

- `-view` returns a container with placeholder mounted by default
- `-shadowView` returns `SmartCollectionViewItemShadowView`
- On overscan entry:
  - Promote placeholder → attach/recycle content view
  - Apply cached props to content view
- On overscan exit:
  - Demote content → detach content view, reattach placeholder
  - Return content view to pool (future recycling step)

### Placeholder

- Must be lightweight (single CALayer, minimal subviews)
- Must report same size as eventual content (from shadow node)
- Must disable user interaction and accessibility until promotion

### Promotion/Demotion

- Promotion must be synchronous when item enters overscan
- Demotion must recycle content view and restore placeholder
- Both must preserve RN reconciliation invariants:
  - Stable `reactTag`
  - Container view remains constant
  - Children swapped inside container, not replaced wholesale

## Caveats & Gotchas

### Bridge Batching

- UIManager flushes updates once per frame
- Coalesce "render more" requests to JS at most once per frame
- Don't send per-pixel scroll events

### Layout Stability

- Placeholder must use shadow node's measured size
- Avoid relayout/jank when promoting

### Event Correctness

- Disable gestures/taps on placeholders
- Enable only after promotion

### Accessibility

- Placeholder should expose minimal "loading" semantics
- Update traits/labels when content mounts

### Memory Bounds

- Cap speculative range to avoid memory spikes
- Pool size must be bounded (per item type)

### Consistency with RN Reconciliation

- RN expects native tree to match shadow tree
- Placeholders must be registered under correct `reactTag`
- Don't create unmanaged native nodes

## Integration Points

### With SmartCollectionViewScheduler

- Scheduler tracks `rangeToMount` (overscan range)
- Scheduler tracks `rangeToRequest` (shadow buffer range)
- Items in `rangeToMount` should have content views
- Items in `rangeToRequest` but outside `rangeToMount` can have placeholders

### With SmartCollectionViewMountController

- MountController handles promotion/demotion
- MountController manages placeholder pool
- MountController coordinates with content view recycling

### With SmartCollectionViewLayoutCache

- LayoutCache stores frames for both placeholder and content states
- Placeholder frames must match content frames (from shadow node)

## Implementation Steps

1. **Create SmartCollectionViewItemShadowView**
   - Extend `RCTShadowView`
   - Implement measure function using props
   - Track overscan/speculative state

2. **Create SmartCollectionViewItemView**
   - Container view with placeholder/content states
   - Promotion/demotion methods
   - Stable `reactTag` and size

3. **Create SmartCollectionViewItemManager**
   - View manager for item views
   - Shadow view manager for item shadow views
   - Promotion/demotion coordination

4. **Integrate with SmartCollectionView**
   - Update mount logic to handle placeholders
   - Coordinate with scheduler for range tracking
   - Update unmount logic to demote to placeholders

5. **Testing**
   - Verify placeholder size matches content size
   - Verify promotion happens at correct scroll position
   - Verify demotion recycles content views
   - Verify no layout jank during promotion/demotion

## Future Enhancements

- View recycling for content views
- Multiple placeholder types (skeleton, shimmer, etc.)
- Configurable placeholder appearance
- Metrics for promotion/demotion performance



