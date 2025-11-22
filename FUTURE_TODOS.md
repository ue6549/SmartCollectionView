# Future Todos & Enhancements

This document tracks future improvements and enhancements for SmartCollectionView beyond the current POC scope.

## Performance Optimizations

### View Recycling
- Implement proper view recycling/reuse for wrapper views
- Maintain a pool of wrapper views that can be reused across different item indices
- Reduce allocation overhead during rapid scrolling
- Consider recycling React child views as well (more complex, requires careful state management)

### Unmounting Off-Screen Views
- Automatically unmount views that scroll out of the visible + buffer range
- Keep React child views in memory (as per current plan) but unmount wrapper views
- Implement proper cleanup and memory management
- Add configurable unmounting thresholds

### Max Height Optimization (#2 Enhancement)
- Update maxHeight calculation in `insertReactSubview:` instead of `layoutSubviewsWithContext:`
- Avoid one extra layout pass when new items mount
- More efficient but requires careful timing to ensure child layouts are complete
- Current implementation uses `layoutSubviewsWithContext:` which is easier but may cause extra passes

## Architecture Improvements

### LocalData Strategy Review
- Evaluate whether `localData` mechanism is still needed once measureFunc approach is working
- Consider if we can rely entirely on shadow view's child shadow views for sizing
- Determine if `localData` provides value beyond caching
- Possibly simplify or remove if redundant

### Shadow View to Manager Linkage
- Investigate why automatic `setLocalData:forView:` routing isn't working
- May be needed for other features beyond sizing
- Understanding this could unlock other React Native mechanisms

### UICollectionView Alternative Exploration
- Evaluate using UICollectionView as the underlying native component instead of UIScrollView
- Pros: Built-in cell recycling, automatic layout management, less code for layout logic
- Cons: Need to bridge React children into UICollectionViewCell pattern (significant challenge)
- Decision: Not pursuing for POC - sticking with UIScrollView approach
- May revisit after POC is stable if layout management complexity becomes an issue

## Layout Enhancements

### Layout Configuration Architecture
- **Current State**: `itemSpacing` is a top-level prop (works for POC with horizontal layout only)
- **Future Consideration**: When adding multiple layout types (vertical list, grids), evaluate layout configuration approach:
  - Option 1: Keep layout-specific props at top level (e.g., `itemSpacing`, `lineSpacing` for grids)
  - Option 2: Introduce `layoutConfig` object with layout-specific settings
  - Option 3: Layout provider pattern where each layout type manages its own config
- **Decision Needed**: Determine contract for how different layouts expose their configuration needs
- **Note**: `itemSpacing` currently represents spacing along main scrolling axis (horizontal for horizontal layout, vertical for vertical layout)

### Vertical List Layout
- Implement vertical scrolling list layout
- Single column, items stacked vertically
- Handle variable item widths
- Use `itemSpacing` for vertical spacing between items

### Horizontal Grid Layout
- Multi-row horizontal grid (e.g., 2 rows)
- Support configurable number of rows
- Efficient item positioning and row height calculation
- Main use case: product grids in horizontal scrolling containers
- **Spacing**: `itemSpacing` for horizontal spacing, `lineSpacing` (new prop) for vertical spacing between rows

### Vertical Grid Layout
- Multi-column vertical grid
- Support configurable number of columns
- Column width calculation
- Responsive grid based on container width
- **Spacing**: `itemSpacing` for vertical spacing, `lineSpacing` (new prop) for horizontal spacing between columns

### Custom Layout Providers
- Allow JS to provide custom layout calculation functions
- Support arbitrary positioning logic
- Enable complex layouts beyond standard list/grid
- Layout providers should define their own configuration contract

## Main App Integration

### RLV Integration
- Replace main vertical list with RecyclerListView
- Test with 1000+ items
- Performance comparison with FlatList

### Multi-Widget Feed
- Create Facebook-style feed with multiple widget types:
  - Horizontal product lists
  - Horizontal product grids
  - Vertical content blocks
  - Mixed layouts
- Test performance with complex, varied content

## Testing & Validation

### Performance Benchmarking
- Compare SmartCollectionView vs FlatList performance
- Memory usage comparison
- Scroll performance metrics
- Frame rate analysis under various conditions

### Edge Cases
- Very tall items
- Very wide items
- Mixed item sizes
- Rapid scrolling
- Large datasets (1000+ items)
- Dynamic item addition/removal

## Documentation

### API Documentation
- Complete API reference
- Usage examples for each layout type
- Best practices guide
- Performance tuning guide

### Architecture Documentation
- Detailed explanation of shadow view interception
- measureFunc approach documentation
- Layout calculation algorithms
- Virtualization strategy

