#import "SmartCollectionViewItemView.h"

#import "SmartCollectionView.h"
#import "SmartCollectionViewReusePool.h"

#import <React/UIView+React.h>

@interface SmartCollectionViewItemView ()

@property (nonatomic, strong) UIView *placeholderView;
@property (nonatomic, weak) UIView *trackedContentView;
@property (nonatomic, assign) BOOL isInPlaceholderMode;

@end

@implementation SmartCollectionViewItemView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.clipsToBounds = YES;
        _placeholderView = [[UIView alloc] initWithFrame:CGRectZero];
        _placeholderView.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1.0];
        _placeholderView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_placeholderView];
        _isInPlaceholderMode = YES;
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    self.placeholderView.frame = self.bounds;
}

- (void)didUpdateReactSubviews
{
    [super didUpdateReactSubviews];
    [self promoteContentIfAvailable];
}

- (void)enterPlaceholderMode
{
    self.isInPlaceholderMode = YES;
    if (self.placeholderView.superview == nil) {
        [self addSubview:self.placeholderView];
    }
    self.placeholderView.hidden = NO;
    self.placeholderView.frame = self.bounds;
}

- (void)promoteContentIfAvailable
{
    UIView *contentView = self.reactSubviews.firstObject;
    if (!contentView) {
        // No content yet, ensure placeholder is visible
        [self enterPlaceholderMode];
        return;
    }

    if (self.trackedContentView != contentView) {
        self.trackedContentView = contentView;
    }

    // Only hide placeholder if content is actually ready
    CGSize contentSize = contentView.frame.size;
    if (CGSizeEqualToSize(contentSize, CGSizeZero)) {
        contentSize = [contentView sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
    }
    
    // Only promote if content has valid size
    if (!CGSizeEqualToSize(contentSize, CGSizeZero) && contentSize.width > 0 && contentSize.height > 0) {
        if (self.placeholderView.superview) {
            self.placeholderView.hidden = YES;
        }
        self.isInPlaceholderMode = NO;
        [contentView setNeedsLayout];
        [contentView layoutIfNeeded];
    } else {
        // Content not ready yet, keep placeholder visible
        [self enterPlaceholderMode];
    }
}

@end

