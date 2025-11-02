#import "HorizontalListLayoutProvider.h"
#import <React/RCTLog.h>

@implementation HorizontalListLayoutProvider

- (NSString *)layoutType {
    return @"horizontalList";
}

- (CGSize)contentSizeForItems:(NSArray<UIView *> *)items 
                    viewport:(CGSize)viewport
              scrollDirection:(BOOL)horizontal {
    
    if (items.count == 0) {
        return CGSizeZero;
    }
    
    // Calculate total width and max height for horizontal layout
    CGFloat totalWidth = 0;
    CGFloat maxHeight = 0;
    
    for (UIView *item in items) {
        // Force layout to get actual size
        [item setNeedsLayout];
        [item layoutIfNeeded];
        
        CGSize itemSize = item.frame.size;
        
        // If frame is zero, use estimated size
        if (itemSize.width == 0 || itemSize.height == 0) {
            itemSize = CGSizeMake(100, 80); // Default estimated size
        }
        
        totalWidth += itemSize.width;
        if (itemSize.height > maxHeight) {
            maxHeight = itemSize.height;
        }
        
        NSLog(@"HorizontalListLayoutProvider: Item size %@, totalWidth: %.2f, maxHeight: %.2f", 
              NSStringFromCGSize(itemSize), totalWidth, maxHeight);
    }
    
    CGSize contentSize = CGSizeMake(totalWidth, maxHeight);
    NSLog(@"HorizontalListLayoutProvider: Content size %@", NSStringFromCGSize(contentSize));
    
    return contentSize;
}

- (NSArray<NSValue *> *)layoutAttributesForElementsInRect:(CGRect)rect
                                                   items:(NSArray<UIView *> *)items
                                                viewport:(CGSize)viewport {
    
    NSMutableArray<NSValue *> *attributes = [NSMutableArray array];
    
    // Calculate cumulative positions for horizontal layout
    CGFloat currentX = 0;
    CGFloat maxHeight = 0;
    
    // First pass: calculate max height
    for (UIView *item in items) {
        [item setNeedsLayout];
        [item layoutIfNeeded];
        
        CGSize itemSize = item.frame.size;
        if (itemSize.width == 0 || itemSize.height == 0) {
            itemSize = CGSizeMake(100, 80);
        }
        
        if (itemSize.height > maxHeight) {
            maxHeight = itemSize.height;
        }
    }
    
    // Second pass: calculate frames and filter by rect
    for (NSInteger i = 0; i < items.count; i++) {
        UIView *item = items[i];
        [item setNeedsLayout];
        [item layoutIfNeeded];
        
        CGSize itemSize = item.frame.size;
        if (itemSize.width == 0 || itemSize.height == 0) {
            itemSize = CGSizeMake(100, 80);
        }
        
        CGRect frame = CGRectMake(currentX, 0, itemSize.width, maxHeight);
        
        // Check if this item intersects with the requested rect
        if (CGRectIntersectsRect(frame, rect)) {
            [attributes addObject:[NSValue valueWithCGRect:frame]];
            NSLog(@"HorizontalListLayoutProvider: Item %ld frame %@ intersects rect %@", 
                  (long)i, NSStringFromCGRect(frame), NSStringFromCGRect(rect));
        }
        
        currentX += itemSize.width;
    }
    
    NSLog(@"HorizontalListLayoutProvider: Found %ld items in rect %@", 
          (long)attributes.count, NSStringFromCGRect(rect));
    
    return [attributes copy];
}

- (CGRect)layoutAttributesForItemAtIndex:(NSInteger)index
                                    items:(NSArray<UIView *> *)items
                                 viewport:(CGSize)viewport {
    
    if (index < 0 || index >= items.count) {
        NSLog(@"HorizontalListLayoutProvider: Invalid index %ld for items count %ld", (long)index, (long)items.count);
        return CGRectZero;
    }
    
    NSLog(@"HorizontalListLayoutProvider: Calculating frame for item %ld, viewport: %@", 
          (long)index, NSStringFromCGSize(viewport));
    
    // Calculate cumulative positions for horizontal layout
    CGFloat currentX = 0;
    CGFloat maxHeight = 0;
    
    // First pass: calculate max height
    for (UIView *item in items) {
        [item setNeedsLayout];
        [item layoutIfNeeded];
        
        CGSize itemSize = item.frame.size;
        if (itemSize.width == 0 || itemSize.height == 0) {
            itemSize = CGSizeMake(100, 80);
        }
        
        if (itemSize.height > maxHeight) {
            maxHeight = itemSize.height;
        }
    }
    
    NSLog(@"HorizontalListLayoutProvider: Max height calculated: %.2f", maxHeight);
    
    // Second pass: find the specific item
    for (NSInteger i = 0; i <= index; i++) {
        UIView *item = items[i];
        [item setNeedsLayout];
        [item layoutIfNeeded];
        
        CGSize itemSize = item.frame.size;
        if (itemSize.width == 0 || itemSize.height == 0) {
            itemSize = CGSizeMake(100, 80);
        }
        
        if (i == index) {
            CGRect frame = CGRectMake(currentX, 0, itemSize.width, maxHeight);
            NSLog(@"HorizontalListLayoutProvider: Item %ld frame %@ (horizontal layout)", 
                  (long)index, NSStringFromCGRect(frame));
            return frame;
        }
        
        currentX += itemSize.width;
    }
    
    NSLog(@"HorizontalListLayoutProvider: Item %ld not found", (long)index);
    return CGRectZero;
}

@end
