#import "SmartCollectionViewShadowView.h"
#import <React/RCTLog.h>
#import <React/RCTShadowView+Layout.h>
#import "SmartCollectionViewLocalData.h"
#import <yoga/Yoga.h>

#ifdef DEBUG
#define SCVShadowLog(fmt, ...) NSLog(@"[SCVShadow] " fmt, ##__VA_ARGS__)
#else
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
    [self dirtyLayout];
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
    
    if (newMaxHeight > 0 && newMaxHeight != _currentMaxHeight) {
        SCVShadowLog(@"Max height changed: %.2f -> %.2f, setting Yoga height", _currentMaxHeight, newMaxHeight);
        _currentMaxHeight = newMaxHeight;
        
        // Set height on Yoga node
        YGNodeStyleSetHeight(self.yogaNode, newMaxHeight);
        
        // Trigger layout update by marking parent as dirty (safe approach)
        // This will cause React Native to recalculate layout for this subtree
        if (self.superview) {
            [self.superview dirtyLayout];
            SCVShadowLog(@"Marked parent shadow view as dirty to trigger layout update");
        }
    } else if (_currentMaxHeight == 0 && newMaxHeight == 0 && _estimatedItemSize.height > 0) {
        // Use estimated height if no children yet
        SCVShadowLog(@"Using estimated height: %.2f", _estimatedItemSize.height);
        YGNodeStyleSetHeight(self.yogaNode, _estimatedItemSize.height);
        
        // Trigger layout update for initial height
        if (self.superview) {
            [self.superview dirtyLayout];
        }
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

    // BREAKPOINT: Set breakpoint here - right before calling setLocalData
    // This should trigger manager's setLocalData:forView: if linkage is working
    SCVShadowLog(@"🔥 About to call [self setLocalData:] - this should route to manager's setLocalData:forView:");
    [self setLocalData:localData];
    SCVShadowLog(@"🔥 Finished calling [self setLocalData:]");
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
    
    // Iterate through child shadow views and find max height
    for (RCTShadowView *childShadow in _mutableChildShadowViews) {
        RCTLayoutMetrics metrics = childShadow.layoutMetrics;
        CGSize size = metrics.frame.size;
        
        if (CGSizeEqualToSize(size, CGSizeZero)) {
            // Try contentFrame if frame is zero
            size = metrics.contentFrame.size;
        }
        
        if (size.height > maxHeight) {
            maxHeight = size.height;
        }
    }
    
    // Fallback to estimated size if no children or all have zero height
    if (maxHeight == 0 && _estimatedItemSize.height > 0) {
        maxHeight = _estimatedItemSize.height;
    }
    
    return maxHeight;
}

@end
