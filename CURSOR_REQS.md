# SmartCollectionView - Cursor Requirements

## Project Overview

A native-driven collection view for React Native that solves FlatList limitations on iOS, particularly `removeClippedSubviews` issues. Built using shadow node manipulation to intercept RN's view hierarchy and implement true native virtualization with UICollectionView-like performance.

## Core Architecture

### Shadow Node Interception Approach
- Intercept child view insertions/removals in custom view manager
- Store virtual items without mounting to actual view hierarchy
- Compute layouts natively and mount only visible items
- Implement recycling for memory efficiency

### Key Benefits
- True native performance (no bridge overhead for virtualization)
- Proper iOS `removeClippedSubviews` equivalent
- UICollectionView-like recycling capabilities
- Variable height support with automatic container sizing

## Technical Specifications

### Platform & Versions
- **Platform**: iOS only (initial POC)
- **React Native**: 0.72.3
- **Build Tool**: React Native CLI
- **Language**: TypeScript
- **Architecture**: Legacy (0.72.3)

### Layout Support
- **Vertical List**: Single column, vertical scroll
- **Horizontal List**: Single row, horizontal scroll  
- **Horizontal Grid**: Multiple rows, horizontal scroll
- **Custom Layouts**: Future extensibility for RN-provided layouts

### Performance Requirements
- Support large datasets (1000+ items)
- Smooth 60fps scrolling
- Memory efficient with recycling
- Automatic height adjustment for variable content

## POC Application Requirements

### Main App Structure
```
Vertical List (RLV)
├── Horizontal List Widget (10 items, 1 row)
├── Horizontal Grid Widget (20 items, 2 rows)
├── Horizontal List Widget (10 items, 1 row)
└── Horizontal Grid Widget (20 items, 2 rows)
```

### Product Card Design
Each product card contains (with optional elements):
- **Image**: Using react-native-fast-image for caching
- **Title**: Always present
- **Subtitle**: Optional
- **MRP**: Original price
- **Selling Price**: Current price
- **Discount**: Percentage off
- **Rating**: Optional star rating
- **Tag/Highlight**: Optional ("Selling Fast", "Top Deal", etc.)

### Data Structure
```typescript
interface ProductCard {
  id: string;
  title: string;
  subtitle?: string;
  imageUrl: string;
  mrp: number;
  sellingPrice: number;
  discount?: number;
  rating?: number;
  tag?: string;
}
```

### Mock Data Generation
- Use random image API (e.g., picsum.photos)
- Generate realistic product data
- Vary optional fields to create variable heights
- 10 items per horizontal list, 20 items per horizontal grid

## Implementation Phases

### Phase 1: Foundation (2-3 weeks)
**Goal**: Basic shadow node interception and simple list layout

#### Week 1: Project Setup
- Create RN 0.72.3 project with TypeScript
- Set up native iOS module structure
- Implement basic SmartCollectionView component
- Create mock data generator

#### Week 2: Shadow Node Interception
- Implement custom view manager
- Override `insertReactSubview` and `removeReactSubview`
- Create virtual item storage system
- Basic layout computation

#### Week 3: Mounting System
- Implement visibility detection
- Mount/unmount items based on scroll position
- Basic frame positioning
- Test with simple horizontal list

### Phase 2: Horizontal List Widget (2-3 weeks)
**Goal**: Complete horizontal list with variable heights

#### Week 1: Layout Engine
- Implement efficient layout computation algorithm
- Support variable item heights
- Automatic container height calculation
- Smooth scrolling implementation

#### Week 2: Product Card Component
- Create ProductCard component with all fields
- Implement react-native-fast-image integration
- Handle optional fields gracefully
- Test with mock data

#### Week 3: Integration & Testing
- Integrate horizontal list widget
- Performance testing with 10 items
- Memory usage optimization
- Bug fixes and polish

### Phase 3: Horizontal Grid (2-3 weeks)
**Goal**: Multi-row horizontal grid layout

#### Week 1: Grid Layout Algorithm
- Implement multi-row layout computation
- Support 2-row grid initially
- Efficient item positioning
- Row height calculation

#### Week 2: Grid Integration
- Extend SmartCollectionView for grid support
- Test with 20 items in 2 rows
- Performance optimization
- Memory management

#### Week 3: Polish & Testing
- End-to-end testing
- Performance benchmarking
- Edge case handling
- Documentation

### Phase 4: Main App Integration (1-2 weeks)
**Goal**: Complete POC application

#### Week 1: RLV Integration
- Implement main vertical list using RLV
- Add multiple horizontal widgets
- Test complete app flow
- Performance validation

#### Week 2: Final Polish
- UI/UX improvements
- Performance optimization
- Bug fixes
- Documentation

## Technical Implementation Details

### Shadow Node Interception
```objc
@interface SmartCollectionViewManager : RCTViewManager
@end

@implementation SmartCollectionViewManager

- (void)insertReactSubview:(UIView *)subview atIndex:(NSInteger)index {
    // Store in virtual collection, don't mount
    [self.virtualCollection addItem:subview atIndex:index];
    [self recomputeLayout];
}

- (void)removeReactSubview:(UIView *)subview {
    [self.virtualCollection removeItem:subview];
    [self recomputeLayout];
}

@end
```

### Efficient Layout Computation
```objc
- (void)recomputeLayout {
    // Only recompute visible + buffer items
    NSRange visibleRange = [self computeVisibleRange];
    NSRange bufferRange = [self expandRange:visibleRange withBuffer:5];
    
    for (NSInteger i = bufferRange.location; i < NSMaxRange(bufferRange); i++) {
        [self computeLayoutForItemAtIndex:i];
    }
}
```

### Variable Height Support
```objc
- (CGFloat)computeItemHeightAtIndex:(NSInteger)index {
    UIView *item = self.virtualItems[index];
    // Use estimated size from RN props
    CGSize estimatedSize = [self getEstimatedSizeForItem:item];
    
    // If item is mounted, use actual size
    if (item.superview) {
        return item.frame.size.height;
    }
    
    return estimatedSize.height;
}
```

## Performance Considerations

### Layout Computation Optimization
- Only compute layouts for visible + buffer items
- Cache computed layouts
- Invalidate cache on data changes
- Use estimated sizes for unmounted items

### Memory Management
- Implement view recycling for production
- Proper cleanup of unmounted items
- Memory usage monitoring
- Leak detection

### Smooth Scrolling
- 60fps target
- Minimize layout computations during scroll
- Use CADisplayLink for smooth animations
- Optimize frame updates

## Success Criteria

### Functional Requirements
- ✅ Horizontal list with 10 variable-height items
- ✅ Horizontal grid with 20 items in 2 rows
- ✅ Smooth scrolling at 60fps
- ✅ Automatic height adjustment
- ✅ Memory efficient operation

### Performance Requirements
- ✅ Support 1000+ items without performance degradation
- ✅ Memory usage < 50MB for 100 items
- ✅ Scroll performance comparable to UICollectionView
- ✅ No memory leaks

### Developer Experience
- ✅ Simple API similar to FlatList
- ✅ TypeScript support
- ✅ Good documentation
- ✅ Easy integration

## Future Extensions

### Phase 5+: Advanced Features
- Vertical grid layouts
- Custom layout providers from RN
- View recycling optimization
- Android support
- Fabric compatibility

### Production Features
- Accessibility support
- Error boundaries
- Performance monitoring
- Developer tools
- Migration guide from FlatList

## Risk Mitigation

### Technical Risks
- **Shadow node lifecycle**: Keep shadow nodes alive, only mount/unmount views
- **Layout invalidation**: Use scroll events and data change notifications
- **Memory leaks**: Proper cleanup in recycling system
- **Performance**: Extensive profiling and optimization

### Implementation Risks
- **Complexity**: Start simple, add features incrementally
- **Compatibility**: Test with various RN versions
- **Maintenance**: Clear documentation and examples
- **Adoption**: Provide migration tools and guides

## Conclusion

This approach combines the best of native iOS performance with React Native's component model. By intercepting shadow nodes and implementing native virtualization, we can achieve UICollectionView-like performance while maintaining RN's developer experience.

The phased approach allows for incremental development and validation, starting with a simple horizontal list and expanding to more complex layouts and features.
