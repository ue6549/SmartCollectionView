#import "SmartCollectionViewShadowView.h"
#import <React/RCTLog.h>
#import <React/RCTShadowView+Layout.h>
#import "SmartCollectionViewLocalData.h"
#import "SmartCollectionViewManager.h"
#import "SmartCollectionView.h"
#import <React/RCTBridge.h>
#import <React/RCTBridge+Private.h>
#import <React/RCTUIManager.h>
#import <yoga/Yoga.h>

#ifdef DEBUG
//#define SCVShadowLog(fmt, ...) NSLog(@"[SCVShadow] " fmt, ##__VA_ARGS__)
//#else
#define SCVShadowLog(fmt, ...)
#endif

@interface SmartCollectionViewShadowView ()

@property (nonatomic, strong) NSMutableArray<RCTShadowView *> *mutableChildShadowViews;
@property (nonatomic, assign) BOOL needsLayoutUpdate;
@property (nonatomic, assign) NSInteger localDataVersion;
@property (nonatomic, assign) CGFloat currentMaxHeight;

@end

@implementation SmartCollectionViewShadowView

- (instancetype)init
{
    self = [super init];
    if (self) {
        _mutableChildShadowViews = [NSMutableArray array];
        _needsLayoutUpdate = YES;
        _localDataVersion = 0;
        _currentMaxHeight = 0;
        _horizontal = YES;
        _estimatedItemSize = CGSizeMake(100, 80);
        
        // Note: Cannot use measureFunc because Yoga doesn't allow nodes with
        // measure functions to have children. Instead, we calculate height
        // after Yoga lays out children in layoutSubviewsWithContext.
        
        SCVShadowLog(@"Initialized shadow view instance: %@", self);
        // BREAKPOINT: Set breakpoint here to verify shadow view creation
    }
    return self;
}

- (void)dealloc
{
    // No cleanup needed (no measureFunc)
}

- (NSArray<RCTShadowView *> *)childShadowViews
{
    return [_mutableChildShadowViews copy];
}

- (void)insertReactSubview:(RCTShadowView *)subview atIndex:(NSInteger)index
{
    [super insertReactSubview:subview atIndex:index];
    SCVShadowLog(@"insertReactSubview index %ld, subview tag: %@, my tag: %@", (long)index, subview.reactTag, self.reactTag);
    
    if (index < 0 || index > _mutableChildShadowViews.count) {
        index = _mutableChildShadowViews.count;
    }

    [_mutableChildShadowViews insertObject:subview atIndex:index];

    _needsLayoutUpdate = YES;
    
    // Mark ourselves as dirty to trigger layout recalculation when new children are added
    [self dirtyLayout];
    
    // Also mark parent to ensure layout cascade happens
    if (self.superview) {
        [self.superview dirtyLayout];
    }
    
    SCVShadowLog(@"Marked shadow view as dirty after adding child at index %ld (total children: %lu)", 
                 (long)index, (unsigned long)_mutableChildShadowViews.count);
}

- (void)removeReactSubview:(RCTShadowView *)subview
{
    [super removeReactSubview:subview];
    SCVShadowLog(@"removeReactSubview");
    
    NSInteger index = [_mutableChildShadowViews indexOfObject:subview];
    if (index != NSNotFound) {
        [_mutableChildShadowViews removeObjectAtIndex:index];
        _needsLayoutUpdate = YES;
        [self dirtyLayout];
    }
}

- (void)layoutSubviewsWithContext:(RCTLayoutContext)layoutContext
{
    [super layoutSubviewsWithContext:layoutContext];
    
    // Calculate max height from children after Yoga has laid them out
    // This allows us to measure children's actual sizes
    CGFloat newMaxHeight = [self calculateMaxItemHeight];
    
    SCVShadowLog(@"layoutSubviewsWithContext: currentMaxHeight=%.2f, newMaxHeight=%.2f, children=%lu", 
                 _currentMaxHeight, newMaxHeight, (unsigned long)_mutableChildShadowViews.count);
    
    // Check if we have children that haven't been laid out yet (zero height)
    // If so, we might need another layout pass to get their real sizes
    BOOL hasUnlaidOutChildren = NO;
    for (RCTShadowView *childShadow in _mutableChildShadowViews) {
        RCTLayoutMetrics metrics = childShadow.layoutMetrics;
        CGSize size = metrics.frame.size;
        if (CGSizeEqualToSize(size, CGSizeZero)) {
            size = metrics.contentFrame.size;
        }
        if (CGSizeEqualToSize(size, CGSizeZero)) {
            hasUnlaidOutChildren = YES;
            break;
        }
    }
    
    if (newMaxHeight > 0 && newMaxHeight != _currentMaxHeight) {
        SCVShadowLog(@"Max height changed: %.2f -> %.2f, setting height via property setter", _currentMaxHeight, newMaxHeight);
        _currentMaxHeight = newMaxHeight;
        
        // Use property setter instead of direct Yoga API - this should handle dirty marking automatically
        YGValue heightValue = {newMaxHeight, YGUnitPoint};
        self.height = heightValue;
        
        SCVShadowLog(@"Set height property to %.2f, marking dirty to trigger relayout", newMaxHeight);
        
        // Mark ourselves as dirty to ensure our height change triggers a relayout
        [self dirtyLayout];
        
        // Also mark parent as dirty to trigger parent layout update
        if (self.superview) {
            [self.superview dirtyLayout];
        }
    } else if (hasUnlaidOutChildren && _currentMaxHeight > 0) {
        // We have children that haven't been laid out yet, but we have a current height
        // Mark as dirty to force another layout pass where children should have valid sizes
        SCVShadowLog(@"⚠️  Has unlaid-out children, marking dirty to force another layout pass");
        [self dirtyLayout];
        if (self.superview) {
            [self.superview dirtyLayout];
        }
    } else if (_currentMaxHeight == 0 && newMaxHeight == 0 && _estimatedItemSize.height > 0) {
        // Use estimated height if no children yet
        SCVShadowLog(@"Using estimated height: %.2f", _estimatedItemSize.height);
        YGValue heightValue = {_estimatedItemSize.height, YGUnitPoint};
        self.height = heightValue;
        
        // Mark ourselves as dirty
        [self dirtyLayout];
        
        // Trigger layout update for initial height
        if (self.superview) {
            [self.superview dirtyLayout];
        }
    } else if (newMaxHeight == _currentMaxHeight && _currentMaxHeight > 0) {
        SCVShadowLog(@"Height unchanged at %.2f", _currentMaxHeight);
    }
    
    [self updateLocalDataIfNeeded];
}

- (void)dirtyLayout
{
    [super dirtyLayout];
    _needsLayoutUpdate = YES;
}

- (void)updateLocalDataIfNeeded
{
    if (!_needsLayoutUpdate) {
        return;
    }

    NSMutableArray<SmartCollectionViewItemMetadata *> *items = [NSMutableArray arrayWithCapacity:_mutableChildShadowViews.count];

    NSInteger index = 0;
    for (RCTShadowView *shadowView in _mutableChildShadowViews) {
        RCTLayoutMetrics metrics = shadowView.layoutMetrics;
        CGSize size = metrics.frame.size;

        if (CGSizeEqualToSize(size, CGSizeZero)) {
            // Fallback to intrinsic content size if available
            size = shadowView.layoutMetrics.contentFrame.size;
        }

        SmartCollectionViewItemMetadata *metadata = [[SmartCollectionViewItemMetadata alloc] initWithReactTag:shadowView.reactTag
                                                                                                            size:size
                                                                                                           index:index
                                                                                                          version:_localDataVersion];
        [items addObject:metadata];
        index++;
    }

    SmartCollectionViewLocalData *localData = [[SmartCollectionViewLocalData alloc] initWithItems:[items copy]
                                                                                        version:_localDataVersion++];

    SCVShadowLog(@"🔥 Publishing local data - version %ld, items %lu, my reactTag: %@", (long)localData.version, (unsigned long)localData.items.count, self.reactTag);
    if (localData.items.count > 0) {
        SmartCollectionViewItemMetadata *first = localData.items.firstObject;
        SCVShadowLog(@"First item tag %@ size %@", first.reactTag, NSStringFromCGSize(first.size));
    }

    // Instead of calling [self setLocalData:] which doesn't route to manager,
    // we'll access the manager directly via bridge and call its method
    SCVShadowLog(@"🔥 Publishing local data - attempting to route to native view via manager");
    
    // Get bridge to access manager
    RCTBridge *bridge = [RCTBridge currentBridge];
    if (!bridge) {
        SCVShadowLog(@"❌ ERROR: No current bridge available");
        _needsLayoutUpdate = NO;
        return;
    }
    
    // Get manager instance
    SmartCollectionViewManager *manager = [bridge moduleForClass:[SmartCollectionViewManager class]];
    if (!manager) {
        SCVShadowLog(@"❌ ERROR: Could not retrieve SmartCollectionViewManager from bridge");
        _needsLayoutUpdate = NO;
        return;
    }
    
    // Get UIManager to find native view by reactTag
    RCTUIManager *uiManager = bridge.uiManager;
    if (!uiManager) {
        SCVShadowLog(@"❌ ERROR: Could not retrieve UIManager from bridge");
        _needsLayoutUpdate = NO;
        return;
    }
    
    // Get native view by reactTag (on main queue)
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *nativeView = [uiManager viewForReactTag:self.reactTag];
        if (!nativeView) {
            SCVShadowLog(@"❌ ERROR: Could not find native view for reactTag %@", self.reactTag);
            return;
        }
        
        if (![nativeView isKindOfClass:[SmartCollectionView class]]) {
            SCVShadowLog(@"❌ ERROR: Native view is not SmartCollectionView, got: %@", NSStringFromClass([nativeView class]));
            return;
        }
        
        SCVShadowLog(@"✅ Found native view %@ for reactTag %@, calling manager.setLocalData:forView:", nativeView, self.reactTag);
        // Call manager's method directly - it will forward to native view's updateWithLocalData:
        [manager setLocalData:localData forView:(SmartCollectionView *)nativeView];
    });
    
    _needsLayoutUpdate = NO;
}

- (SmartCollectionViewLocalData *)localDataSnapshot
{
    [self updateLocalDataIfNeeded];
    
    // Access localData via RCTShadowView's mechanism
    id localDataObj = [self performSelector:@selector(localData)];
    if ([localDataObj isKindOfClass:[SmartCollectionViewLocalData class]]) {
        return localDataObj;
    }
    return nil;
}

- (CGFloat)calculateMaxItemHeight
{
    CGFloat maxHeight = 0;
    NSInteger itemsWithValidHeight = 0;
    
    // Iterate through child shadow views and find max height
    for (RCTShadowView *childShadow in _mutableChildShadowViews) {
        RCTLayoutMetrics metrics = childShadow.layoutMetrics;
        CGSize size = metrics.frame.size;
        
        if (CGSizeEqualToSize(size, CGSizeZero)) {
            // Try contentFrame if frame is zero
            size = metrics.contentFrame.size;
        }
        
        if (size.height > 0) {
            itemsWithValidHeight++;
            if (size.height > maxHeight) {
                maxHeight = size.height;
            }
        }
    }
    
    // Fallback to estimated size if no children or all have zero height
    if (maxHeight == 0 && _estimatedItemSize.height > 0) {
        maxHeight = _estimatedItemSize.height;
        SCVShadowLog(@"Using estimated height fallback: %.2f", maxHeight);
    }
    
    SCVShadowLog(@"calculateMaxItemHeight: maxHeight=%.2f (from %lu children, %ld with valid height)", 
                 maxHeight, (unsigned long)_mutableChildShadowViews.count, (long)itemsWithValidHeight);
    
    // If we have children but none have valid height yet, return 0
    // This will trigger the "hasUnlaidOutChildren" check in layoutSubviewsWithContext
    // which will mark as dirty and force another layout pass
    if (_mutableChildShadowViews.count > 0 && itemsWithValidHeight == 0) {
        SCVShadowLog(@"⚠️  All children have zero height (%lu children), returning 0 to trigger relayout check", 
                     (unsigned long)_mutableChildShadowViews.count);
        return 0; // Return 0 to trigger the unlaid-out children check
    }
    
    return maxHeight;
}

@end
