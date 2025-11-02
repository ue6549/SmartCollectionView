#import "SmartCollectionViewMountController.h"
#import <React/RCTLog.h>

@implementation SmartCollectionViewMountController

- (instancetype)initWithContainerView:(UIView *)containerView {
    self = [super init];
    if (self) {
        _containerView = containerView;
        _mountedIndices = [NSMutableSet set];
        _mountedViews = [NSMutableDictionary dictionary];
        
        NSLog(@"SmartCollectionViewMountController initialized with container view");
    }
    return self;
}

- (void)mountItem:(UIView *)item atIndex:(NSInteger)index withFrame:(CGRect)frame {
    if (!_containerView || [_mountedIndices containsObject:@(index)]) {
        NSLog(@"SmartCollectionViewMountController: Skipping mount - containerView: %@, already mounted: %@", 
              _containerView ? @"YES" : @"NO", [_mountedIndices containsObject:@(index)] ? @"YES" : @"NO");
        return;
    }
    
    // Set frame and add to container
    item.frame = frame;
    [_containerView addSubview:item];
    
    // Track mounted state
    [_mountedIndices addObject:@(index)];
    _mountedViews[@(index)] = item;
    
    NSLog(@"SmartCollectionViewMountController: Mounted item at index %ld with frame %@ (horizontal layout)", 
          (long)index, NSStringFromCGRect(frame));
}

- (void)unmountItemAtIndex:(NSInteger)index {
    NSNumber *indexNum = @(index);
    
    if (![_mountedIndices containsObject:indexNum]) {
        return;
    }
    
    UIView *item = _mountedViews[indexNum];
    if (item) {
        [item removeFromSuperview];
        [_mountedViews removeObjectForKey:indexNum];
    }
    
    [_mountedIndices removeObject:indexNum];
    
    NSLog(@"SmartCollectionViewMountController: Unmounted item at index %ld", (long)index);
}

- (void)unmountAllItems {
    for (NSNumber *indexNum in [_mountedIndices copy]) {
        [self unmountItemAtIndex:[indexNum integerValue]];
    }
    
    NSLog(@"SmartCollectionViewMountController: Unmounted all items");
}

- (BOOL)isItemMountedAtIndex:(NSInteger)index {
    return [_mountedIndices containsObject:@(index)];
}

- (UIView *)mountedViewAtIndex:(NSInteger)index {
    return _mountedViews[@(index)];
}

- (NSArray<NSNumber *> *)allMountedIndices {
    return [_mountedIndices allObjects];
}

- (void)mountItems:(NSArray<UIView *> *)items 
           indices:(NSArray<NSNumber *> *)indices 
           frames:(NSArray<NSValue *> *)frames {
    
    if (items.count != indices.count || items.count != frames.count) {
        NSLog(@"SmartCollectionViewMountController: Array count mismatch in batch mount");
        return;
    }
    
    for (NSInteger i = 0; i < items.count; i++) {
        UIView *item = items[i];
        NSInteger index = [indices[i] integerValue];
        CGRect frame = [frames[i] CGRectValue];
        
        [self mountItem:item atIndex:index withFrame:frame];
    }
    
    NSLog(@"SmartCollectionViewMountController: Batch mounted %ld items", (long)items.count);
}

- (void)unmountItemsAtIndices:(NSArray<NSNumber *> *)indices {
    for (NSNumber *indexNum in indices) {
        [self unmountItemAtIndex:[indexNum integerValue]];
    }
    
    NSLog(@"SmartCollectionViewMountController: Batch unmounted %ld items", (long)indices.count);
}

@end
