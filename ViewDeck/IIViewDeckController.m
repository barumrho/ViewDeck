//
//  IIViewDeckController.m
//  IIViewDeck
//
//  Copyright (C) 2011, Tom Adriaenssen
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of
//  this software and associated documentation files (the "Software"), to deal in
//  the Software without restriction, including without limitation the rights to
//  use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
//  of the Software, and to permit persons to whom the Software is furnished to do
//  so, subject to the following conditions:
// 
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

#import <objc/runtime.h>
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>

#import "IIViewDeckController.h"

#define DURATION_FAST 0.3
#define DURATION_SLOW 0.3
#define SLIDE_DURATION(animated,duration) ((animated) ? (duration) : 0)
#define OPEN_SLIDE_DURATION(animated) SLIDE_DURATION(animated,DURATION_FAST)
#define CLOSE_SLIDE_DURATION(animated) SLIDE_DURATION(animated,DURATION_SLOW)

@interface UIViewController(UIViewDeckItem_Internal)
- (void)setViewDeckController:(IIViewDeckController *)viewDeckController;
@end

@interface IIViewDeckController()<UIGestureRecognizerDelegate>
@property(nonatomic, strong) UIView *referenceView;
@property(nonatomic, readonly) CGRect referenceBounds;
@property(nonatomic, strong) NSMutableArray *panners;
@property(nonatomic, unsafe_unretained) CGFloat originalShadowRadius;
@property(nonatomic, unsafe_unretained) CGFloat originalShadowOpacity;
@property(nonatomic, strong) UIColor *originalShadowColor;
@property(nonatomic, unsafe_unretained) CGSize originalShadowOffset;
@property(nonatomic, strong) UIBezierPath *originalShadowPath;
@property(nonatomic, strong) UIButton *centerTapper;
@property(nonatomic, strong) UIView *centerView;
@property(nonatomic, readonly) UIView *slidingControllerView;

// Use these methods to access views to access view properties
// Accessing them through controller.view will load them when it's not necessary
@property(nonatomic, readonly) UIView *centerControllerView;
@property(nonatomic, readonly) UIView *leftControllerView;
@property(nonatomic, readonly) UIView *rightControllerView;

@property(nonatomic, readonly) BOOL isShowingLeftController;
@property(nonatomic, readonly) BOOL isShowingRightController;

- (void)loadLeftControllerView;
- (void)loadRightControllerView;

- (void)cleanup;

- (BOOL)closeLeftViewAnimated:(BOOL)animated options:(UIViewAnimationOptions)options completion:(void(^)(IIViewDeckController *controller))completed;
- (void)openLeftViewAnimated:(BOOL)animated options:(UIViewAnimationOptions)options completion:(void(^)(IIViewDeckController *controller))completed;
- (BOOL)closeRightViewAnimated:(BOOL)animated options:(UIViewAnimationOptions)options completion:(void(^)(IIViewDeckController *controller))completed;
- (void)openRightViewAnimated:(BOOL)animated options:(UIViewAnimationOptions)options completion:(void(^)(IIViewDeckController *controller))completed;

- (CGRect)slidingRectForOffset:(CGFloat)offset;

- (void)setSlidingAndReferenceViews;
- (void)applyShadowToSlidingView;
- (void)restoreShadowToSlidingView;
- (void)arrangeViewsAfterRotation;

- (void)centerViewVisible;
- (void)centerViewHidden;

- (void)addPanners;
- (void)removePanners;

- (BOOL)checkDelegate:(SEL)selector animated:(BOOL)animated;
- (void)performDelegate:(SEL)selector animated:(BOOL)animated;

- (BOOL)mustRelayAppearance;
@end 


@implementation IIViewDeckController {
    BOOL _animating;
    BOOL _viewAppeared;
    CGFloat _panOrigin;
    CGFloat _preRotationWidth, _leftWidth, _rightWidth;
    
    BOOL _isCenterControllerDelegate;
    BOOL _isLeftControllerDelegate;
    BOOL _isRightControllerDelegate;
    
    BOOL _shouldOpenLeft;
    BOOL _shouldOpenRight;
}

@synthesize panningMode = _panningMode;
@synthesize panners = _panners;
@synthesize referenceView = _referenceView;
@synthesize centerController = _centerController;
@synthesize leftController = _leftController;
@synthesize rightController = _rightController;
@synthesize leftLedge = _leftLedge;
@synthesize rightLedge = _rightLedge;
@synthesize leftSideViewSize = _leftSideViewSize;
@synthesize rightSideViewSize = _rightSideViewSize;
@synthesize resizesCenterView = _resizesCenterView;
@synthesize originalShadowOpacity = _originalShadowOpacity;
@synthesize originalShadowPath = _originalShadowPath;
@synthesize originalShadowRadius = _originalShadowRadius;
@synthesize originalShadowColor = _originalShadowColor;
@synthesize originalShadowOffset = _originalShadowOffset;
@synthesize delegate = _delegate;
@synthesize navigationControllerBehavior = _navigationControllerBehavior;
@synthesize panningView = _panningView; 
@synthesize centerhiddenInteractivity = _centerhiddenInteractivity;
@synthesize centerTapper = _centerTapper;
@synthesize centerView = _centerView;
@synthesize rotationBehavior = _rotationBehavior;
@synthesize enabled = _enabled;
@synthesize elastic = _elastic;

#pragma mark - Initalisation and deallocation

- (id)initWithCenterViewController:(UIViewController *)centerController {
    self = [super init];
    if (self) {
        _elastic = YES;
        _panningMode = IIViewDeckFullViewPanning;
        _navigationControllerBehavior = IIViewDeckNavigationControllerContained;
        _centerhiddenInteractivity = IIViewDeckCenterHiddenUserInteractive;
        self.rotationBehavior = IIViewDeckRotationKeepsLedgeSizes;
        _resizesCenterView = NO;
        self.panners = [NSMutableArray array];
        self.enabled = YES;

        self.centerController = centerController;
        self.leftLedge = 44;
        self.rightLedge = 44;
    }

    return self;
}

- (void)cleanup {
    self.referenceView = nil;
    self.centerView = nil;
    self.centerTapper = nil;
}

- (void)dealloc {
    [self cleanup];

    self.centerController.viewDeckController = nil;
    self.centerController = nil;
    self.leftController.viewDeckController = nil;
    self.leftController = nil;
    self.rightController.viewDeckController = nil;
    self.rightController = nil;
    self.panners = nil;
}

#pragma mark - Memory management

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    
    [self.centerController didReceiveMemoryWarning];
    [self.leftController didReceiveMemoryWarning];
    [self.rightController didReceiveMemoryWarning];
}

#pragma mark - Bookkeeping

- (CGRect)referenceBounds {
    return self.referenceView.bounds;
}

- (CGRect)slidingRectForOffset:(CGFloat)offset {
    CGRect bounds = self.referenceView.bounds;
    bounds.origin.x += offset;
    if (self.resizesCenterView) {
        bounds.size.width -= ABS(offset);
        
        if (offset > 0) {
            bounds.origin.x = 0;
        }
    }
    
    return bounds;
}

#pragma mark - ledges

- (void)setLeftLedge:(CGFloat)leftLedge {
    leftLedge = MAX(leftLedge, MIN(self.referenceBounds.size.width, leftLedge));
    if (_viewAppeared && self.slidingControllerView.frame.origin.x == self.referenceBounds.size.width - _leftLedge) {
        if (leftLedge < _leftLedge) {
            [UIView animateWithDuration:CLOSE_SLIDE_DURATION(YES) animations:^{
                self.slidingControllerView.frame = [self slidingRectForOffset:self.referenceBounds.size.width - leftLedge];
            }];
        } else if (leftLedge > _leftLedge) {
            [UIView animateWithDuration:OPEN_SLIDE_DURATION(YES) animations:^{
                self.slidingControllerView.frame = [self slidingRectForOffset:self.referenceBounds.size.width - leftLedge];
            }];
        }
    }

    if (!self.leftSideViewSize) {
        self.leftSideViewSize = self.referenceBounds.size.width - leftLedge;
    }

    _leftLedge = leftLedge;
}

- (void)setRightLedge:(CGFloat)rightLedge {
    rightLedge = MAX(rightLedge, MIN(self.referenceBounds.size.width, rightLedge));
    if (_viewAppeared && self.slidingControllerView.frame.origin.x == _rightLedge - self.referenceBounds.size.width) {
        if (rightLedge < _rightLedge) {
            [UIView animateWithDuration:CLOSE_SLIDE_DURATION(YES) animations:^{
                self.slidingControllerView.frame = [self slidingRectForOffset:rightLedge - self.referenceBounds.size.width];
            }];
        } else if (rightLedge > _rightLedge) {
            [UIView animateWithDuration:OPEN_SLIDE_DURATION(YES) animations:^{
                self.slidingControllerView.frame = [self slidingRectForOffset:rightLedge - self.referenceBounds.size.width];
            }];
        }
    }

    if (!self.rightSideViewSize) {
        self.rightSideViewSize = self.referenceBounds.size.width - rightLedge;
    }

    _rightLedge = rightLedge;
}

#pragma mark - View lifecycle

- (void)loadView {
    self.view = [[UIView alloc] init];
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view.autoresizesSubviews = YES;
    self.view.clipsToBounds = YES;
    
    self.centerView = [[UIView alloc] init];
    self.centerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.centerView.autoresizesSubviews = YES;
    self.centerView.clipsToBounds = YES;
    [self.view addSubview:self.centerView];
    [self.centerView addSubview:self.centerController.view];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.originalShadowRadius = 0;
    self.originalShadowOpacity = 0;
    self.originalShadowColor = nil;
    self.originalShadowOffset = CGSizeZero;
    self.originalShadowPath = nil;
}

- (void)viewDidUnload {
    _viewAppeared = NO;
    [self cleanup];
    [super viewDidUnload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    [self.view addObserver:self forKeyPath:@"bounds" options:NSKeyValueChangeSetting context:nil];

    if (!_viewAppeared) {
        [self setSlidingAndReferenceViews];
        
        self.centerView.frame = self.referenceBounds;
        self.centerController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.centerController.view.frame = self.referenceBounds;
        self.slidingControllerView.frame = self.referenceBounds;
        self.slidingControllerView.hidden = NO;
        
        [self applyShadowToSlidingView];
        _viewAppeared = YES;
    } else {
        [self arrangeViewsAfterRotation];
    }
    
    [self addPanners];

    if (self.slidingControllerView.frame.origin.x == 0) 
        [self centerViewVisible];
    else
        [self centerViewHidden];
   
    [self.centerController viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.centerController viewDidAppear:animated];
    [self.view setNeedsLayout];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.centerController viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [self removePanners];

    [self closeLeftView];
    [self closeRightView];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.view removeObserver:self forKeyPath:@"bounds"];
    [self.centerController viewDidDisappear:animated];
}

#pragma mark - rotation
- (NSUInteger)supportedInterfaceOrientations {
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        return UIInterfaceOrientationMaskAll;
    } else {
        return UIInterfaceOrientationMaskPortrait;
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    _preRotationWidth = self.referenceBounds.size.width;
    
    if (self.rotationBehavior == IIViewDeckRotationKeepsViewSizes) {
        self.centerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }

    if (self.rotationBehavior == IIViewDeckRotationKeepsViewSizes) {
        if (self.leftController.isViewLoaded) {
            _leftWidth = self.leftController.view.frame.size.width;
        }
        
        if (self.rightController.isViewLoaded) {
            _rightWidth = self.rightController.view.frame.size.width;
        }
    }
    
    BOOL should = YES;
    if (self.centerController) {
        should = [self.centerController shouldAutorotateToInterfaceOrientation:interfaceOrientation];
    }

    return should;
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    [super willAnimateRotationToInterfaceOrientation:toInterfaceOrientation duration:duration];

    [self arrangeViewsAfterRotation];
    
    [self.centerController willAnimateRotationToInterfaceOrientation:toInterfaceOrientation duration:duration];
    [self.leftController willAnimateRotationToInterfaceOrientation:toInterfaceOrientation duration:duration];
    [self.rightController willAnimateRotationToInterfaceOrientation:toInterfaceOrientation duration:duration];
}


- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
    [self restoreShadowToSlidingView];
    
    [self.centerController willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
    [self.leftController willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
    [self.rightController willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
    [self applyShadowToSlidingView];

    [self.centerController didRotateFromInterfaceOrientation:fromInterfaceOrientation];
    [self.leftController didRotateFromInterfaceOrientation:fromInterfaceOrientation];
    [self.rightController didRotateFromInterfaceOrientation:fromInterfaceOrientation];
}

- (void)arrangeViewsAfterRotation {
    if (_preRotationWidth <= 0) return;
    
    CGFloat offset = self.slidingControllerView.frame.origin.x;
    if (self.rotationBehavior == IIViewDeckRotationKeepsLedgeSizes) {
        if (offset > 0) {
            offset = self.referenceBounds.size.width - _preRotationWidth + offset;
        } else if (offset < 0) {
            offset = offset + _preRotationWidth - self.referenceBounds.size.width;
        }
        self.slidingControllerView.frame = [self slidingRectForOffset:offset];
        self.centerController.view.frame = self.referenceBounds;
    } else {
        self.leftLedge = self.referenceBounds.size.width - self.leftSideViewSize;
        self.rightLedge = self.referenceBounds.size.width - self.rightSideViewSize;
    }
    
    _preRotationWidth = 0;
}

#pragma mark - controller state

- (BOOL)leftControllerIsClosed {
    return !self.leftController || CGRectGetMinX(self.slidingControllerView.frame) <= 0;
}

- (BOOL)rightControllerIsClosed {
    return !self.rightController || CGRectGetMaxX(self.slidingControllerView.frame) >= self.referenceBounds.size.width;
}

- (void)showCenterView {
    [self showCenterView:YES];
}

- (void)showCenterView:(BOOL)animated {
    [self showCenterView:animated completion:nil];
}

- (void)showCenterView:(BOOL)animated  completion:(void(^)(IIViewDeckController *controller))completed {
    if (!self.leftController.view.hidden) 
        [self closeLeftViewAnimated:animated completion:completed];
    if (!self.rightController.view.hidden) 
        [self closeRightViewAnimated:animated completion:completed];
}

- (void)toggleLeftView {
    if (_animating) return;
    [self toggleLeftViewAnimated:YES];
}

- (void)openLeftView {
    [self openLeftViewAnimated:YES];
}

- (void)closeLeftView {
    [self closeLeftViewAnimated:YES];
}

- (void)toggleLeftViewAnimated:(BOOL)animated {
    [self toggleLeftViewAnimated:animated completion:nil];
}

- (void)toggleLeftViewAnimated:(BOOL)animated completion:(void (^)(IIViewDeckController *))completed {
    if ([self leftControllerIsClosed]) 
        [self openLeftViewAnimated:animated completion:completed];
    else
        [self closeLeftViewAnimated:animated completion:completed];
}

- (void)openLeftViewAnimated:(BOOL)animated {
    [self openLeftViewAnimated:animated completion:nil];
}

- (void)openLeftViewAnimated:(BOOL)animated completion:(void (^)(IIViewDeckController *))completed {
    [self openLeftViewAnimated:animated options:UIViewAnimationOptionCurveEaseInOut completion:completed];
}


- (void)openLeftViewAnimated:(BOOL)animated options:(UIViewAnimationOptions)options completion:(void (^)(IIViewDeckController *))completed {
    if (!self.leftController || CGRectGetMinX(self.slidingControllerView.frame) == self.leftLedge) return;
    
    // check the delegate to allow opening
    if (![self checkDelegate:@selector(viewDeckControllerWillOpenLeftView:animated:) animated:animated]) return;
    // also close the right view if it's open. Since the delegate can cancel the close, check the result.
    if (![self closeRightViewAnimated:animated options:options completion:completed]) return;
    
    [self loadLeftControllerView];
    [self.leftController viewWillAppear:YES];
    [UIView animateWithDuration:OPEN_SLIDE_DURATION(animated) delay:0 options:options | UIViewAnimationOptionLayoutSubviews | UIViewAnimationOptionBeginFromCurrentState animations:^{
        _animating = YES;
        self.leftController.view.hidden = NO;
        if (self.rotationBehavior == IIViewDeckRotationKeepsViewSizes) {
            self.slidingControllerView.frame = [self slidingRectForOffset:self.leftSideViewSize];
        } else {
            self.slidingControllerView.frame = [self slidingRectForOffset:self.referenceBounds.size.width - self.leftLedge];
        }
        [self centerViewHidden];
    } completion:^(BOOL finished) {
        [self.leftController viewDidAppear:YES];
        _animating = NO;
        if (completed) completed(self);
        [self performDelegate:@selector(viewDeckControllerDidOpenLeftView:animated:) animated:animated];
    }];
}

- (void)closeLeftViewAnimated:(BOOL)animated {
    [self closeLeftViewAnimated:animated completion:nil];
}

- (void)closeLeftViewAnimated:(BOOL)animated completion:(void (^)(IIViewDeckController *))completed {
    [self closeLeftViewAnimated:animated options:UIViewAnimationOptionCurveEaseInOut completion:completed];
}

- (BOOL)closeLeftViewAnimated:(BOOL)animated options:(UIViewAnimationOptions)options completion:(void (^)(IIViewDeckController *))completed {
    if (self.leftControllerIsClosed) return YES;

    // check the delegate to allow closing
    if (![self checkDelegate:@selector(viewDeckControllerWillCloseLeftView:animated:) animated:animated]) return NO;

    [self.leftController viewWillDisappear:YES];
    [UIView animateWithDuration:CLOSE_SLIDE_DURATION(animated) delay:0 options:options | UIViewAnimationOptionLayoutSubviews animations:^{
        _animating = YES;
        self.slidingControllerView.frame = [self slidingRectForOffset:0];
        [self centerViewVisible];
    } completion:^(BOOL finished) {
        [self.leftController viewDidDisappear:YES];
        _animating = NO;
        self.leftController.view.hidden = YES;
        if (completed) completed(self);
        [self performDelegate:@selector(viewDeckControllerDidCloseLeftView:animated:) animated:animated];
        [self performDelegate:@selector(viewDeckControllerDidShowCenterView:animated:) animated:animated];
    }];
    
    return YES;
}

- (void)closeLeftViewBouncing:(void(^)(IIViewDeckController *controller))bounced {
    [self closeLeftViewBouncing:bounced completion:nil];
}

- (void)closeLeftViewBouncing:(void(^)(IIViewDeckController *controller))bounced completion:(void (^)(IIViewDeckController *))completed {
    if (self.leftControllerIsClosed) return;
    
    // check the delegate to allow closing
    if (![self checkDelegate:@selector(viewDeckControllerWillCloseLeftView:animated:) animated:YES]) return;
    
    [self.leftController viewWillDisappear:YES];
    // first open the view completely, run the block (to allow changes) and close it again.
    [UIView animateWithDuration:OPEN_SLIDE_DURATION(YES) delay:0 options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionLayoutSubviews animations:^{
        _animating = YES;
        self.slidingControllerView.frame = [self slidingRectForOffset:self.referenceBounds.size.width];
    } completion:^(BOOL finished) {
        // run block if it's defined
        if (bounced) bounced(self);
        if (self.delegate && [self.delegate respondsToSelector:@selector(viewDeckController:didBounceWithClosingController:)]) 
            [self.delegate viewDeckController:self didBounceWithClosingController:self.leftController];
        
        [UIView animateWithDuration:CLOSE_SLIDE_DURATION(YES) delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionLayoutSubviews animations:^{
            self.slidingControllerView.frame = [self slidingRectForOffset:0];
            [self centerViewVisible];
        } completion:^(BOOL finished) {
            [self.leftController viewDidDisappear:YES];
            _animating = NO;
            self.leftController.view.hidden = YES;
            if (completed) completed(self);
            [self performDelegate:@selector(viewDeckControllerDidCloseLeftView:animated:) animated:YES];
            [self performDelegate:@selector(viewDeckControllerDidShowCenterView:animated:) animated:YES];
        }];
    }];
}


- (void)toggleRightView {
    if (_animating) return;
    [self toggleRightViewAnimated:YES];
}

- (void)openRightView {
    [self openRightViewAnimated:YES];
}

- (void)closeRightView {
    [self closeRightViewAnimated:YES];
}

- (void)toggleRightViewAnimated:(BOOL)animated {
    [self toggleRightViewAnimated:animated completion:nil];
}

- (void)toggleRightViewAnimated:(BOOL)animated completion:(void (^)(IIViewDeckController *))completed {
    if ([self rightControllerIsClosed]) 
        [self openRightViewAnimated:animated completion:completed];
    else
        [self closeRightViewAnimated:animated completion:completed];
}

- (void)openRightViewAnimated:(BOOL)animated {
    [self openRightViewAnimated:animated completion:nil];
}

- (void)openRightViewAnimated:(BOOL)animated completion:(void (^)(IIViewDeckController *))completed {
    [self openRightViewAnimated:animated options:UIViewAnimationOptionCurveEaseInOut completion:completed];
}

- (void)openRightViewAnimated:(BOOL)animated options:(UIViewAnimationOptions)options completion:(void (^)(IIViewDeckController *))completed {
    if (!self.rightController || CGRectGetMaxX(self.slidingControllerView.frame) == self.rightLedge) return;

    // check the delegate to allow opening
    if (![self checkDelegate:@selector(viewDeckControllerWillOpenRightView:animated:) animated:animated]) return;
    // also close the left view if it's open. Since the delegate can cancel the close, check the result.
    if (![self closeLeftViewAnimated:animated options:options completion:completed]) return;
    

    [self loadRightControllerView];    
    [self.rightController viewWillAppear:YES];
    [UIView animateWithDuration:OPEN_SLIDE_DURATION(animated) delay:0 options:options | UIViewAnimationOptionLayoutSubviews animations:^{
        _animating = YES;
        self.rightController.view.hidden = NO;
        if (self.rotationBehavior == IIViewDeckRotationKeepsViewSizes) {
            self.slidingControllerView.frame = [self slidingRectForOffset:-self.rightSideViewSize];
        } else {
            self.slidingControllerView.frame = [self slidingRectForOffset:self.rightLedge - self.referenceBounds.size.width];
        }
        [self centerViewHidden];
    } completion:^(BOOL finished) {
        [self.rightController viewDidAppear:YES];
        _animating = NO;
        if (completed) completed(self);
        [self performDelegate:@selector(viewDeckControllerDidOpenRightView:animated:) animated:animated];
    }];
}

- (void)closeRightViewAnimated:(BOOL)animated {
    [self closeRightViewAnimated:animated completion:nil];
}

- (void)closeRightViewAnimated:(BOOL)animated completion:(void (^)(IIViewDeckController *))completed {
    [self closeRightViewAnimated:animated options:UIViewAnimationOptionCurveEaseInOut completion:completed];
}

- (BOOL)closeRightViewAnimated:(BOOL)animated options:(UIViewAnimationOptions)options completion:(void (^)(IIViewDeckController *))completed {
    if (self.rightControllerIsClosed) return YES;
    
    // check the delegate to allow closing
    if (![self checkDelegate:@selector(viewDeckControllerWillCloseRightView:animated:) animated:animated]) return NO;
    
    [self.rightController viewWillDisappear:YES];
    [UIView animateWithDuration:CLOSE_SLIDE_DURATION(animated) delay:0 options:options | UIViewAnimationOptionLayoutSubviews animations:^{
        _animating = YES;
        self.slidingControllerView.frame = [self slidingRectForOffset:0];
        [self centerViewVisible];
    } completion:^(BOOL finished) {
        [self.rightController viewDidDisappear:YES];
        _animating = NO;
        if (completed) completed(self);
        self.rightController.view.hidden = YES;
        [self performDelegate:@selector(viewDeckControllerDidCloseRightView:animated:) animated:animated];
        [self performDelegate:@selector(viewDeckControllerDidShowCenterView:animated:) animated:animated];
    }];
    
    return YES;
}

- (void)closeRightViewBouncing:(void(^)(IIViewDeckController *controller))bounced {
    [self closeRightViewBouncing:bounced completion:nil];
}

- (void)closeRightViewBouncing:(void(^)(IIViewDeckController *controller))bounced completion:(void (^)(IIViewDeckController *))completed {
    if (self.rightControllerIsClosed) return;
    
    // check the delegate to allow closing
    if (![self checkDelegate:@selector(viewDeckControllerWillCloseRightView:animated:) animated:YES]) return;
    
    [self.rightController viewWillDisappear:YES];
    [UIView animateWithDuration:OPEN_SLIDE_DURATION(YES) delay:0 options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionLayoutSubviews animations:^{
        _animating = YES;
        self.slidingControllerView.frame = [self slidingRectForOffset:-self.referenceBounds.size.width];
    } completion:^(BOOL finished) {
        if (bounced)  bounced(self);
        if (self.delegate && [self.delegate respondsToSelector:@selector(viewDeckController:didBounceWithClosingController:)]) 
            [self.delegate viewDeckController:self didBounceWithClosingController:self.rightController];

        [UIView animateWithDuration:CLOSE_SLIDE_DURATION(YES) delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionLayoutSubviews animations:^{
            self.slidingControllerView.frame = [self slidingRectForOffset:0];
            [self centerViewVisible];
        } completion:^(BOOL finished) {
            [self.rightController viewDidDisappear:YES];
            _animating = NO;
            self.rightController.view.hidden = YES;
            if (completed) completed(self);
            [self performDelegate:@selector(viewDeckControllerDidCloseRightView:animated:) animated:YES];
            [self performDelegate:@selector(viewDeckControllerDidShowCenterView:animated:) animated:YES];
        }];
    }];
}


#pragma mark - center view hidden stuff

- (void)centerViewVisible {
    [self removePanners];
    if (self.centerTapper) {
        [self.centerTapper removeTarget:self action:@selector(centerTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.centerTapper removeFromSuperview];
    }
    self.centerTapper = nil;
    [self addPanners];
}

- (void)centerViewHidden {
    if (IIViewDeckCenterHiddenIsInteractive(self.centerhiddenInteractivity)) 
        return;

    [self removePanners];
    if (!self.centerTapper) {
        self.centerTapper = [UIButton buttonWithType:UIButtonTypeCustom];
        self.centerTapper.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.centerTapper.frame = [self.centerView bounds];
        [self.centerView addSubview:self.centerTapper];
        [self.centerTapper addTarget:self action:@selector(centerTapped) forControlEvents:UIControlEventTouchUpInside];
        self.centerTapper.backgroundColor = [UIColor clearColor];
        
    }
    self.centerTapper.frame = [self.centerView bounds];
    [self addPanners];
}

- (void)centerTapped {
    if (IIViewDeckCenterHiddenCanTapToClose(self.centerhiddenInteractivity)) {
        if (self.leftController && CGRectGetMinX(self.slidingControllerView.frame) > 0) {
            if (self.centerhiddenInteractivity == IIViewDeckCenterHiddenNotUserInteractiveWithTapToClose) 
                [self closeLeftView];
            else
                [self closeLeftViewBouncing:nil];
        }
        if (self.rightController && CGRectGetMinX(self.slidingControllerView.frame) < 0) {
            if (self.centerhiddenInteractivity == IIViewDeckCenterHiddenNotUserInteractiveWithTapToClose) 
                [self closeRightView];
            else
                [self closeRightViewBouncing:nil];
        }

    }
}

#pragma mark - Panning

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    _panOrigin = self.slidingControllerView.frame.origin.x;
    return self.enabled;
}

- (void)panned:(UIPanGestureRecognizer *)panner {
    if (!_enabled) return;
    
    CGPoint pan = [panner translationInView:self.referenceView];
    CGFloat x = pan.x + _panOrigin;
    
    if (!self.leftController) x = MIN(0, x);
    if (!self.rightController) x = MAX(0, x);
    
    if ([panner state] == UIGestureRecognizerStateBegan) {
        [self loadLeftControllerView];
        [self loadRightControllerView];
        
        _shouldOpenLeft = [self checkDelegate:@selector(viewDeckControllerWillOpenLeftView:animated:) animated:NO];
        _shouldOpenRight = [self checkDelegate:@selector(viewDeckControllerWillOpenRightView:animated:) animated:NO];
    }
    
    if (x > 0 && !_shouldOpenLeft) {
        x = 0;
    } else if (x < 0 && !_shouldOpenRight) {
        x = 0;
    }

    CGFloat w = self.referenceBounds.size.width;
    CGFloat lx = MAX(MIN(x, w - self.leftLedge), -w + self.rightLedge);

    if (self.elastic) {
        CGFloat dx = ABS(x) - ABS(lx);
        if (dx > 0) {
            dx = dx / logf(dx + 1) * 2;
            x = lx + (x < 0 ? -dx : dx);
        }
    } else {
        x = lx;
    }

    self.slidingControllerView.frame = [self slidingRectForOffset:x];
    self.rightController.view.hidden = x >= 0;
    self.leftController.view.hidden = x <= 0;
    
    if ([self.delegate respondsToSelector:@selector(viewDeckController:didPanToOffset:)]) {
        [self.delegate viewDeckController:self didPanToOffset:x];
    }
    
    if (panner.state == UIGestureRecognizerStateEnded) {
        CGFloat lw3 = (w-self.leftLedge) / 3.0;
        CGFloat rw3 = (w-self.rightLedge) / 3.0;
        CGFloat velocity = [panner velocityInView:self.referenceView].x;
        if (ABS(velocity) < 500) {
            // small velocity, no movement
            if (x >= w - self.leftLedge - lw3) {
                [self openLeftViewAnimated:YES options:UIViewAnimationOptionCurveEaseOut completion:nil];
            } else if (x <= self.rightLedge + rw3 - w) {
                [self openRightViewAnimated:YES options:UIViewAnimationOptionCurveEaseOut completion:nil];
            } else {
                [self showCenterView:YES];
            }
        } else if (velocity < 0) {
            // swipe to the left
            if (x < 0) {
                [self openRightViewAnimated:YES options:UIViewAnimationOptionCurveEaseOut completion:nil];
            } else {
                [self showCenterView:YES];
            }
        } else if (velocity > 0) {
            // swipe to the right
            if (x > 0) {
                [self openLeftViewAnimated:YES options:UIViewAnimationOptionCurveEaseOut completion:nil];
            } else {
                [self showCenterView:YES];
            }
        }
    }
}


- (void)addPanner:(UIView*)view {
    if (!view) return;
    
    UIPanGestureRecognizer *panner = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)];
    panner.cancelsTouchesInView = YES;
    panner.delegate = self;
    [view addGestureRecognizer:panner];
    [self.panners addObject:panner];
}


- (void)addPanners {
    [self removePanners];

    switch (_panningMode) {
        case IIViewDeckNoPanning: 
            break;
            
        case IIViewDeckFullViewPanning:
            [self addPanner:self.slidingControllerView];
            // also add to disabled center
            if (self.centerTapper)
                [self addPanner:self.centerTapper];
            // also add to navigationbar if present
            if (self.navigationController && !self.navigationController.navigationBarHidden && self.navigationControllerBehavior == IIViewDeckNavigationControllerContained) 
                [self addPanner:self.navigationController.navigationBar];
            break;
            
        case IIViewDeckNavigationBarPanning:
            if (self.navigationController && !self.navigationController.navigationBarHidden) {
                [self addPanner:self.navigationController.navigationBar];
            }
            
            if (self.centerController.navigationController && !self.centerController.navigationController.navigationBarHidden) {
                [self addPanner:self.centerController.navigationController.navigationBar];
            }
            
            if ([self.centerController isKindOfClass:[UINavigationController class]] && !((UINavigationController*)self.centerController).navigationBarHidden) {
                [self addPanner:((UINavigationController*)self.centerController).navigationBar];
            }
            break;
        case IIViewDeckPanningViewPanning:
            if (_panningView) {
                [self addPanner:self.panningView];
            }
            break;
    }
}


- (void)removePanners {
    for (UIGestureRecognizer *panner in self.panners) {
        [panner.view removeGestureRecognizer:panner];
    }
    
    [self.panners removeAllObjects];
}

#pragma mark - Delegate convenience methods

- (BOOL)checkDelegate:(SEL)selector animated:(BOOL)animated {
    BOOL ok = YES;
    
    if ([self.delegate respondsToSelector:selector]) {
        ok = ok && (BOOL)objc_msgSend(self.delegate, selector, self, animated);
    }
    if (_isLeftControllerDelegate && [self.leftController respondsToSelector:selector]) {
        ok = ok && (BOOL)objc_msgSend(self.leftController, selector, self, animated);
    }
    if (_isRightControllerDelegate && [self.rightController respondsToSelector:selector]) {
        ok = ok && (BOOL)objc_msgSend(self.rightController, selector, self, animated);
    }
    if (_isCenterControllerDelegate && [self.centerController respondsToSelector:selector]) {
        ok = ok && (BOOL)objc_msgSend(self.centerController, selector, self, animated);
    }

    return ok;
}

- (void)performDelegate:(SEL)selector animated:(BOOL)animated {
    if ([self.delegate respondsToSelector:selector]) {
        objc_msgSend(self.delegate, selector, self, animated);
    }
    if (_isLeftControllerDelegate && [self.leftController respondsToSelector:selector]) {
        objc_msgSend(self.leftController, selector, self, animated);
    }
    if (_isRightControllerDelegate && [self.rightController respondsToSelector:selector]) {
        objc_msgSend(self.rightController, selector, self, animated);
    }
    if (_isCenterControllerDelegate && [self.centerController respondsToSelector:selector]) {
        objc_msgSend(self.centerController, selector, self, animated);
    }
}


#pragma mark - Properties
- (BOOL)isShowingLeftController {
    return self.slidingControllerView.frame.origin.x > 0;
}

- (BOOL)isShowingRightController {
    return self.slidingControllerView.frame.origin.x < 0;
}

- (void)loadLeftControllerView {
    [self.referenceView insertSubview:self.leftController.view belowSubview:self.slidingControllerView];
    self.leftController.view.frame = self.referenceBounds;
    self.leftController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.leftController.view.hidden = YES;
}

- (void)loadRightControllerView {
    [self.referenceView insertSubview:self.rightController.view belowSubview:self.slidingControllerView];
    self.rightController.view.frame = self.referenceBounds;
    self.rightController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.rightController.view.hidden = YES;
}

- (UIView *)centerControllerView {
    if (self.centerController.isViewLoaded) {
        return self.centerController.view;
    }
    
    return nil;
}
- (UIView *)leftControllerView {
    if (self.leftController.isViewLoaded) {
        return self.leftController.view;
    }
    
    return nil;
}

- (UIView *)rightControllerView {
    if (self.rightController.isViewLoaded) {
        return self.rightController.view;
    }
    
    return nil;
}

- (BOOL)mustRelayAppearance {
    return ![UIViewController instancesRespondToSelector:@selector(automaticallyForwardAppearanceAndRotationMethodsToChildViewControllers)];
}

- (void)setTitle:(NSString *)title {
    self.centerController.title = title;
}

- (NSString *)title {
    return self.centerController.title;
}

- (void)setPanningMode:(IIViewDeckPanningMode)panningMode {
    if (_viewAppeared) {
        [self removePanners];
        _panningMode = panningMode;
        [self addPanners];
    }
    else
        _panningMode = panningMode;
}

- (void)setPanningView:(UIView *)panningView {
    if (_panningView != panningView) {
        _panningView = panningView;
        if (_viewAppeared && _panningMode == IIViewDeckPanningViewPanning) {
            [self addPanners];
        }
    }
}

- (void)setNavigationControllerBehavior:(IIViewDeckNavigationControllerBehavior)navigationControllerBehavior {
    NSAssert(!_viewAppeared, @"Cannot set navigationcontroller behavior when the view deck is already showing.");
    _navigationControllerBehavior = navigationControllerBehavior;
}

- (void)setLeftController:(UIViewController *)leftController {
    if (_viewAppeared) {
        if (_leftController == leftController) return;
        
        if (_leftController) {
            if (self.isShowingLeftController) {
                [_leftController viewWillDisappear:NO];
            }
            [self.leftControllerView removeFromSuperview];
            if (self.isShowingLeftController) {
                [_leftController viewDidDisappear:NO];
            }

            _leftController.viewDeckController = nil;
        }
        
        if (leftController) {
            if (leftController == self.centerController) self.centerController = nil;
            if (leftController == self.rightController) self.rightController = nil;

            leftController.viewDeckController = self;
            if (self.isShowingLeftController) {
                [_leftController viewWillAppear:NO];
            }
            [self.referenceView insertSubview:leftController.view belowSubview:self.slidingControllerView];
            leftController.view.hidden = self.slidingControllerView.frame.origin.x <= 0;
            leftController.view.frame = self.referenceBounds;
            leftController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            
            if (self.isShowingLeftController) {
                [_leftController viewDidAppear:NO];
            }
        }
    }

    _leftController.viewDeckController = nil;
    _leftController = leftController;
    _leftController.viewDeckController = self;
    _isLeftControllerDelegate = [_leftController conformsToProtocol:@protocol(IIViewDeckControllerDelegate)];
}



- (void)setCenterController:(UIViewController *)centerController {
    if (!_viewAppeared) {
        _centerController.viewDeckController = nil;
        _centerController = centerController;
        _centerController.viewDeckController = self;
        _isCenterControllerDelegate = [_centerController conformsToProtocol:@protocol(IIViewDeckControllerDelegate)];
        return;
    }

    if (_centerController == centerController) return;
    
    [self removePanners];
    CGRect currentFrame = self.referenceBounds;
    if (_centerController) {
        [self restoreShadowToSlidingView];
        currentFrame = _centerController.view.frame;
        if (self.mustRelayAppearance) [_centerController viewWillDisappear:NO];
        [_centerController.view removeFromSuperview];
        _centerController.viewDeckController = nil;
        if (self.mustRelayAppearance) [_centerController viewDidDisappear:NO];
        _centerController = nil;
    }
    
    if (centerController) {
        if (centerController == self.leftController) self.leftController = nil;
        if (centerController == self.rightController) self.rightController = nil;

        UINavigationController *navController = [centerController isKindOfClass:[UINavigationController class]] 
            ? (UINavigationController*)centerController 
            : nil;
        BOOL barHidden = NO;
        if (navController != nil && !navController.navigationBarHidden) {
            barHidden = YES;
            navController.navigationBarHidden = YES;
        }

        _centerController = centerController;
        _centerController.viewDeckController = self;

        centerController.view.frame = currentFrame;
        centerController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        centerController.view.hidden = NO;
        if (self.mustRelayAppearance) [self.centerController viewWillAppear:NO];
        [self.centerView addSubview:centerController.view];
        
        if (barHidden) {
            navController.navigationBarHidden = NO;
        }
        
        [self addPanners];
        [self applyShadowToSlidingView];
        if (self.mustRelayAppearance) [self.centerController viewDidAppear:NO];
    }
    
    _isCenterControllerDelegate = [_centerController conformsToProtocol:@protocol(IIViewDeckControllerDelegate)];
}

- (void)setRightController:(UIViewController *)rightController {
    if (_viewAppeared) {
        if (_rightController == rightController) return;
        
        if (_rightController) {
            if (self.isShowingRightController) {
                [_rightController viewWillDisappear:NO];
            }
            [self.rightControllerView removeFromSuperview];
            if (self.isShowingRightController) {
                [_rightController viewDidDisappear:NO];
            }
            _rightController.viewDeckController = nil;
        }
        
        if (rightController) {
            if (rightController == self.centerController) self.centerController = nil;
            if (rightController == self.leftController) self.leftController = nil;
            
            rightController.viewDeckController = self;
            if (self.isShowingRightController) {
                [_rightController viewWillAppear:NO];
            }
            [self.referenceView insertSubview:rightController.view belowSubview:self.slidingControllerView];
            rightController.view.hidden = self.slidingControllerView.frame.origin.x >= 0;
            rightController.view.frame = self.referenceBounds;
            rightController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            
            if (self.isShowingRightController) {
                [_rightController viewDidAppear:NO];
            }
        }
    }

    _rightController.viewDeckController = nil;
    _rightController = rightController;
    _rightController.viewDeckController = self;
    _isRightControllerDelegate = [_rightController conformsToProtocol:@protocol(IIViewDeckControllerDelegate)];
}

- (void)setSlidingAndReferenceViews {
    if (self.navigationControllerBehavior == IIViewDeckNavigationControllerIntegrated) {
        NSAssert(!!self.navigationController, @"ViewDeckController must be inside a UINavigationController");
        self.referenceView = [self.navigationController.view superview];
    } else {
        self.referenceView = self.view;
    }
}

- (UIView *)slidingControllerView {
    if (self.navigationControllerBehavior == IIViewDeckNavigationControllerIntegrated) {
        NSAssert(!!self.navigationController, @"ViewDeckController must be inside a UINavigationController");
        return self.navigationController.view;
    } else {
        return self.centerView;
    }
}

#pragma mark - observation

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"bounds"]) {
        CGFloat offset = self.slidingControllerView.frame.origin.x;
        self.slidingControllerView.frame = [self slidingRectForOffset:offset];
        self.slidingControllerView.layer.shadowPath = [UIBezierPath bezierPathWithRect:self.referenceBounds].CGPath;
        UINavigationController *navController = [self.centerController isKindOfClass:[UINavigationController class]] 
            ? (UINavigationController *)self.centerController 
            : nil;
        if (navController != nil && !navController.navigationBarHidden) {
            navController.navigationBarHidden = YES;
            navController.navigationBarHidden = NO;
        }
    }
}

#pragma mark - Shadow

- (void)restoreShadowToSlidingView {
    UIView *shadowedView = self.slidingControllerView;
    if (!shadowedView) return;

    shadowedView.layer.shadowRadius = self.originalShadowRadius;
    shadowedView.layer.shadowOpacity = self.originalShadowOpacity;
    shadowedView.layer.shadowColor = [self.originalShadowColor CGColor]; 
    shadowedView.layer.shadowOffset = self.originalShadowOffset;
    shadowedView.layer.shadowPath = [self.originalShadowPath CGPath];
}

- (void)applyShadowToSlidingView {
    UIView *shadowedView = self.slidingControllerView;
    if (!shadowedView) return;

    self.originalShadowRadius = shadowedView.layer.shadowRadius;
    self.originalShadowOpacity = shadowedView.layer.shadowOpacity;
    self.originalShadowColor = shadowedView.layer.shadowColor ? [UIColor colorWithCGColor:self.slidingControllerView.layer.shadowColor] : nil;
    self.originalShadowOffset = shadowedView.layer.shadowOffset;
    self.originalShadowPath = shadowedView.layer.shadowPath ? [UIBezierPath bezierPathWithCGPath:self.slidingControllerView.layer.shadowPath] : nil;

    if ([self.delegate respondsToSelector:@selector(viewDeckController:applyShadow:withBounds:)]) {
        [self.delegate viewDeckController:self applyShadow:shadowedView.layer withBounds:self.referenceBounds];
    } else {
        shadowedView.layer.masksToBounds = NO;
        shadowedView.layer.shadowRadius = 10;
        shadowedView.layer.shadowOpacity = 1;
        shadowedView.layer.shadowColor = [[UIColor blackColor] CGColor];
        shadowedView.layer.shadowOffset = CGSizeZero;
        shadowedView.layer.shadowPath = [[UIBezierPath bezierPathWithRect:self.referenceBounds] CGPath];
    }
}

@end

#pragma mark -

@implementation UIViewController(UIViewDeckItem) 
@dynamic viewDeckController;

static char *viewDeckControllerKey = "ViewDeckController";

- (IIViewDeckController *)viewDeckController {
    id result = objc_getAssociatedObject(self, viewDeckControllerKey);
    if (!result && self.navigationController) 
        return [self.navigationController viewDeckController];

    return result;
}

- (void)setViewDeckController:(IIViewDeckController *)viewDeckController {
    if (!self.parentViewController) {
        [self setValue:viewDeckController forKey:@"parentViewController"];
    } else if (viewDeckController == nil && [self.parentViewController isKindOfClass:[IIViewDeckController class]]) {
        [self setValue:nil forKey:@"parentViewController"];
    }
    objc_setAssociatedObject(self, viewDeckControllerKey, viewDeckController, OBJC_ASSOCIATION_RETAIN);
}


@end

