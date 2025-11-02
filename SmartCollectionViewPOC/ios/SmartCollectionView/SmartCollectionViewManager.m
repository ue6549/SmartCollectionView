#import "SmartCollectionViewManager.h"
#import "SmartCollectionView.h"
#import "SmartCollectionViewShadowView.h"
#import "SmartCollectionViewLocalData.h"
#import <React/RCTUIManager.h>
#import <React/RCTBridge.h>
#import <React/RCTLog.h>

#ifdef DEBUG
#define SCVManagerLog(fmt, ...) RCTLogInfo(@"[SCVManager] " fmt, ##__VA_ARGS__)
#else
#define SCVManagerLog(fmt, ...)
#endif

@implementation SmartCollectionViewManager

RCT_EXPORT_MODULE(SmartCollectionView)

- (UIView *)view
{
    SmartCollectionView *view = [[SmartCollectionView alloc] init];
    SCVManagerLog(@"Creating native view instance: %@", view);
    // BREAKPOINT: Set breakpoint here to verify view creation
    return view;
}

- (RCTShadowView *)shadowView
{
    SmartCollectionViewShadowView *shadowView = [[SmartCollectionViewShadowView alloc] init];
    SCVManagerLog(@"Creating shadow view instance: %@", shadowView);
    // BREAKPOINT: Set breakpoint here to verify shadow view creation
    return shadowView;
}

// Export properties
RCT_EXPORT_VIEW_PROPERTY(initialNumToRender, NSInteger)
RCT_EXPORT_VIEW_PROPERTY(maxToRenderPerBatch, NSInteger)
RCT_EXPORT_VIEW_PROPERTY(overscanCount, NSInteger)
RCT_EXPORT_VIEW_PROPERTY(overscanLength, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(horizontal, BOOL)
RCT_EXPORT_VIEW_PROPERTY(estimatedItemSize, CGSize)
RCT_EXPORT_VIEW_PROPERTY(totalItemCount, NSInteger)

// Export events
RCT_EXPORT_VIEW_PROPERTY(onRequestItems, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onVisibleRangeChange, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onScroll, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onScrollBeginDrag, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onScrollEndDrag, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onMomentumScrollBegin, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onMomentumScrollEnd, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onScrollEndDecelerating, RCTDirectEventBlock)

- (void)insertReactSubview:(UIView *)subview atIndex:(NSInteger)index
{
    // BREAKPOINT: Set breakpoint here - this confirms manager is receiving insert calls
    SCVManagerLog(@"🔥 insertReactSubview CALLED - index: %ld, subview: %@, tag: %@", (long)index, subview, subview.reactTag);
    
    // Get the parent view from the subview's reactSuperview
    UIView *parentView = subview.reactSuperview;
    SCVManagerLog(@"Parent view: %@, class: %@, isSmartCollectionView: %@", parentView, NSStringFromClass([parentView class]), [parentView isKindOfClass:[SmartCollectionView class]] ? @"YES" : @"NO");
    
    if ([parentView isKindOfClass:[SmartCollectionView class]]) {
        SmartCollectionView *smartView = (SmartCollectionView *)parentView;
        SCVManagerLog(@"✅ insertReactSubview - Registering child at index %ld, subview tag: %@, parent tag: %@", (long)index, subview.reactTag, smartView.reactTag);
        [smartView registerChildView:subview atIndex:index];
    } else {
        SCVManagerLog(@"❌ ERROR: insertReactSubview - parent is not SmartCollectionView, got: %@", NSStringFromClass([parentView class]));
    }
}

- (void)removeReactSubview:(UIView *)subview
{
    // Get the parent view from the subview's reactSuperview
    UIView *parentView = subview.reactSuperview;
    if ([parentView isKindOfClass:[SmartCollectionView class]]) {
        SmartCollectionView *smartView = (SmartCollectionView *)parentView;
        SCVManagerLog(@"removeReactSubview, subview tag: %@", subview.reactTag);
        [smartView unregisterChildView:subview];
    } else {
        SCVManagerLog(@"ERROR: removeReactSubview - parent is not SmartCollectionView, got: %@", NSStringFromClass([parentView class]));
    }
}

- (void)setLocalData:(id)localData forView:(SmartCollectionView *)view
{
    // BREAKPOINT: Set breakpoint here - this is the critical method we need to verify
    SCVManagerLog(@"🔥🔥🔥 setLocalData:forView: CALLED - view: %@, view.tag: %@, localData class: %@", view, view.reactTag, NSStringFromClass([localData class]));
    
    if (![localData isKindOfClass:[SmartCollectionViewLocalData class]]) {
        SCVManagerLog(@"❌ Ignoring unexpected local data class: %@", NSStringFromClass([localData class]));
        return;
    }

    SmartCollectionViewLocalData *typedData = (SmartCollectionViewLocalData *)localData;
    SCVManagerLog(@"✅ setLocalData version %ld, items %lu, calling updateWithLocalData on view %@", (long)typedData.version, (unsigned long)typedData.items.count, view);
    [view updateWithLocalData:typedData];
}

@end
