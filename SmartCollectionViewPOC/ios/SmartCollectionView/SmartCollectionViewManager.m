#import "SmartCollectionViewManager.h"
#import "SmartCollectionView.h"
#import "SmartCollectionViewShadowView.h"
#import "SmartCollectionViewItemView.h"
#import "SmartCollectionViewLocalData.h"
#import <React/RCTUIManager.h>
#import <React/RCTBridge.h>
#import <React/RCTLog.h>

#ifdef DEBUG
//#define SCVManagerLog(fmt, ...) RCTLogInfo(@"[SCVManager] " fmt, ##__VA_ARGS__)
//#else
#define SCVManagerLog(fmt, ...)
#endif

// Reuse pool logs are always enabled (not conditional on DEBUG)
#define SCVReusePoolLog(fmt, ...) // RCTLogInfo(@"[SCV-ReusePool] " fmt, ##__VA_ARGS__)

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
RCT_EXPORT_VIEW_PROPERTY(shadowBufferMultiplier, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(initialMaxToRenderPerBatch, NSInteger)
RCT_EXPORT_VIEW_PROPERTY(initialOverscanCount, NSInteger)
RCT_EXPORT_VIEW_PROPERTY(initialOverscanLength, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(initialShadowBufferMultiplier, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(horizontal, BOOL)
RCT_EXPORT_VIEW_PROPERTY(estimatedItemSize, CGSize)
RCT_EXPORT_VIEW_PROPERTY(itemSpacing, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(totalItemCount, NSInteger)

// Custom property for itemTypes (dictionary of index -> itemType)
RCT_CUSTOM_VIEW_PROPERTY(itemTypes, NSDictionary, SmartCollectionView)
{
    if (json && [json isKindOfClass:[NSDictionary class]]) {
        NSDictionary *incoming = (NSDictionary *)json;
        
        NSMutableDictionary<NSNumber *, NSString *> *normalizedEntries = [NSMutableDictionary dictionary];
        NSMutableSet<NSNumber *> *indicesToRemove = [NSMutableSet set];
        
        [incoming enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            NSNumber *indexKey = nil;
            if ([key isKindOfClass:[NSNumber class]]) {
                indexKey = (NSNumber *)key;
            } else if ([key respondsToSelector:@selector(integerValue)]) {
                indexKey = @([key integerValue]);
            }
            
            if (!indexKey) {
                SCVReusePoolLog(@"⚠️  Ignoring itemTypes entry with non-numeric key: %@", key);
                return;
            }
            
            if (!obj || [obj isKindOfClass:[NSNull class]]) {
                [indicesToRemove addObject:indexKey];
                return;
            }
            
            if (![obj isKindOfClass:[NSString class]]) {
                SCVReusePoolLog(@"⚠️  Ignoring itemTypes value for index %@ due to unsupported class %@", indexKey, NSStringFromClass([obj class]));
                return;
            }
            
            normalizedEntries[indexKey] = (NSString *)obj;
        }];
        
        if (normalizedEntries.count == 0 && indicesToRemove.count == 0) {
            // Nothing to merge/remove
            return;
        }
        
        NSMutableDictionary<NSNumber *, NSString *> *merged = [NSMutableDictionary dictionaryWithDictionary:view.itemTypes ?: @{}];
        for (NSNumber *indexKey in indicesToRemove) {
            [merged removeObjectForKey:indexKey];
        }
        [normalizedEntries enumerateKeysAndObjectsUsingBlock:^(NSNumber *key, NSString *obj, BOOL *stop) {
            merged[key] = obj;
        }];
        
        view.itemTypes = [merged copy];
        SCVReusePoolLog(@"✅ itemTypes map updated: %lu entries (merged %lu new, removed %lu)",
                        (unsigned long)merged.count,
                        (unsigned long)normalizedEntries.count,
                        (unsigned long)indicesToRemove.count);
    } else if (!json) {
        // Clear if null/undefined
        view.itemTypes = nil;
        SCVReusePoolLog(@"⚠️  itemTypes map cleared (set to nil)");
    }
}

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
        if ([subview isKindOfClass:[SmartCollectionViewItemView class]]) {
            SmartCollectionViewItemView *itemView = (SmartCollectionViewItemView *)subview;
            itemView.parentCollectionView = smartView;
        }
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
        if ([subview isKindOfClass:[SmartCollectionViewItemView class]]) {
            SmartCollectionViewItemView *itemView = (SmartCollectionViewItemView *)subview;
            itemView.parentCollectionView = nil;
        }
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
