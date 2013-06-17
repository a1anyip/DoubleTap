//
//  DoubleTap
//
//  Created by Alan Yip on 1 Oct 2012
//
//  Started project on 1 Oct 2012
//  Continued project on 16 Jun 2013
//
//  Copyright 2012-2013 Alan Yip. All rights reserved.
//

#import "objc/objc.h"
#import "objc/runtime.h"

#define PREF_PATH									@"/var/mobile/Library/Preferences/cc.tweak.doubletap.plist"

#ifndef kCFCoreFoundationVersionNumber_iOS_5_0
#define kCFCoreFoundationVersionNumber_iOS_5_0		675.00
#endif

#ifndef kCFCoreFoundationVersionNumber_iOS_6_0
#define kCFCoreFoundationVersionNumber_iOS_6_0		793.00
#endif

#define IS_IOS5										(kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_5_0 && !IS_IOS6)
#define IS_IOS6										(kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_6_0)
#define ObserverParameters							CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo

/* Notifications */
#define kPreferenceChangedNotification				CFSTR("cc.tweak.doubletap.preferencechanged")
#define kEnableZoomNotification						CFSTR("kEnableZoomNotification")

#define kOrientationPortraitNotification			CFSTR("kOrientationPortraitNotification")
#define kOrientationPortraitUpsideDownNotification	CFSTR("kOrientationPortraitUpsideDownNotification")
#define kOrientationLandscapeLeftNotification		CFSTR("kOrientationLandscapeLeftNotification")
#define kOrientationLandscapeRightNotification		CFSTR("kOrientationLandscapeRightNotification")
#define kOrientationLockNotification				CFSTR("kOrientationLockNotification")

#define kVolumeHUDShowNotification					CFSTR("kVolumeHUDShowNotification")
#define kVolumeHUDHideNotification					CFSTR("kVolumeHUDHideNotification")

#define SWIPE_RANGE									100.0

// Variables
static BOOL isSpringBoard							= NO;

static BOOL isLandscape								= NO;
static BOOL shouldFlipCoordinate					= NO; // for upside down and landscape orientation

static BOOL toggleOrientationLockEnabled			= YES;
static int swipeAction								= 1; // none / brightness / volume
static BOOL hideHUD									= NO;

static BOOL _swiping								= NO;
static CGPoint _swipingCoordinates					= CGPointZero;
static CGPoint _swipingInitialCoordinates			= CGPointZero;
static CGFloat _swipingInitialValue					= 0.0;

// Function declaration
static inline void toggleOrientationLock();
static inline void setShowVolumeHUD(BOOL enabled);
static inline void reloadPref(ObserverParameters);

// Class declarations

// For iOS 5: SpringBoard
@interface SpringBoard

// Only available in iOS 5
- (void)setZoomTouchEnabled:(BOOL)enabled;

@end

// For iOS 5 and 6: SpringBoard
@interface SBOrientationLockManager

+ (id)sharedInstance;
- (BOOL)isLocked;
- (void)unlock;
- (void)lock;

@end

// For iOS 5 and 6: ZoomTouch.bundle
@interface ZOTWorkSpace

+ (void)enableZoom;
+ (id)workspace;

@end

@interface ZOTWorkspace

+ (void)enableZoom;
+ (id)workspace;

@end

@interface ZOTEvent

- (CGPoint)location;
- (int)handEventType;
- (unsigned int)fingerCount;

@end

@interface AVSystemController

+ (id)sharedAVSystemController;

- (BOOL)getActiveCategoryVolume:(float*)volume andName:(id*)name;
- (BOOL)setActiveCategoryVolumeTo:(float)to;

@end

@interface UIApplication (Private)

- (void)setSystemVolumeHUDEnabled:(BOOL)enabled forAudioCategory:(NSString *)category;

@end

// ZoomTouch group
%group ZoomTouch

%hook ZOTEventFactory

- (void)_handleEvent:(ZOTEvent *)event {
	
	// disabled swipe action
	if (swipeAction == 0) {
		_swiping = NO;
		_swipingInitialCoordinates = CGPointZero;
		_swipingInitialValue = 0.0;
		_swipingCoordinates = CGPointZero;
		return %orig;
	}
	
	// event type
	// 1: touch down (begin)
	// 2: move
	int type = [event handEventType];
	int fingers = [event fingerCount];
	
	CGFloat scale = [UIScreen mainScreen].scale;
	CGPoint location = [event location];
	location.x = round(location.x / scale);
	location.y = round(location.y / scale);
	
	// when moving with three fingers
	if (type == 2 && fingers == 3) {
		if (!_swiping) { // if just start to move, then set the values of start y and initial brightness
			_swipingInitialCoordinates = location;
			
			if (swipeAction == 1) {
				// record initial brightness
				_swipingInitialValue = [UIScreen mainScreen].brightness;
			} else if (swipeAction == 2) {
				
				// record initial volume
				float volume;
				[[objc_getClass("AVSystemController") sharedAVSystemController] getActiveCategoryVolume:&volume andName:nil];
				_swipingInitialValue = volume;
				
				// hide HUD, if needed
				if (hideHUD) {
					if (isSpringBoard) {
						setShowVolumeHUD(NO);
					} else {
						CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kVolumeHUDHideNotification, NULL, NULL, true);
					}
				}
			}
		}
		_swipingCoordinates = location; // update the latest dragging location
		_swiping = YES;
	} else {
		// reset values
		_swiping = NO;
		_swipingInitialCoordinates = CGPointZero;
		_swipingInitialValue = 0.0;
		_swipingCoordinates = CGPointZero;
		
		if (swipeAction == 2) {
			// restore the enabled state of volume HUD
			if (isSpringBoard) {
				setShowVolumeHUD(YES);
			} else {
				CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kVolumeHUDShowNotification, NULL, NULL, true);
			}
		}
	}
	
	// ZOTEvent : SCRCGestureEvent
	//NSLog(@"*** Handle event with type: %d, fingers: %d, location: %.2f, %.2f", type, fingers, [event location].x, [event location].y);
	
	%orig;
}

%end

%hook ZOTZoomManager

// prevent original zooming behaviour
- (void)_setZoomLevel:(float)level location:(CGPoint)location zoomed:(BOOL)zoomed duration:(double)duration {
	
	if (zoomed) { // just double-tap
		
		if (isSpringBoard) {
			toggleOrientationLock();
		} else {
			// post notification and let SpringBoard take action
			CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kOrientationLockNotification, NULL, NULL, true);
		}
		
		//NSLog(@"*** Double tap with three fingers without swiping");
		
	} else if (_swiping && swipeAction != 0) { // double-tap then swiping
		
		// swipe distance
		CGFloat initialCoordinate = isLandscape ? _swipingInitialCoordinates.x : _swipingInitialCoordinates.y;
		CGFloat swipingCoordinate = isLandscape ? _swipingCoordinates.x : _swipingCoordinates.y;
		CGFloat swipeDelta = initialCoordinate - swipingCoordinate;
		
		if (shouldFlipCoordinate) swipeDelta *= -1;
		
		// calculate the target value with initial value and swipe distance
		// value may refer to brightness or volume depending on the setting
		CGFloat value = _swipingInitialValue + swipeDelta / SWIPE_RANGE;
		value = value > 1.0 ? 1.0 : (value < 0.0 ? 0.0 : value);
		
		if (swipeAction == 1) {
			if ([UIScreen mainScreen].brightness != value)
				[UIScreen mainScreen].brightness = value;
		} else if (swipeAction == 2) {
			[[objc_getClass("AVSystemController") sharedAVSystemController] setActiveCategoryVolumeTo:value];
		}
		
		//NSLog(@"*** Swiping with three fingers (%.2f)", swipeDelta);
		//NSLog(@"*** Set Brightness: %f", targetBrightness);
	}
}

%end

%end

// ZoomTouch group only for iOS 5
%group ZoomTouchIOS5

%hook ZOTWorkSpace

// disabling ZoomTouch is prohibited
+ (void)disableZoom {}
- (void)_setZoomEnabled:(BOOL)enabled { %orig(YES); }

%end

%end

// ZoomTouch group only for iOS 6
%group ZoomTouchIOS6

%hook ZOTWorkspace

// disabling ZoomTouch is prohibited
+ (void)disableZoom {}
- (void)_setZoomEnabled:(BOOL)enabled { %orig(YES); }

%end

%end

// SpringBoard group
%group SpringBoard

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)arg1 {
	
	%orig;
	
	// force enable ZoomTouch
	if (IS_IOS6) {
		// post notification and let SpringBoard take action
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kEnableZoomNotification, NULL, NULL, true);
		
	} else if ([objc_getClass("SpringBoard") instancesRespondToSelector:@selector(setZoomTouchEnabled:)]) {
		[objc_getClass("SpringBoard") setZoomTouchEnabled:YES];
	}
}

- (void)noteInterfaceOrientationChanged:(int)orientation duration:(float)duration updateMirroredDisplays:(BOOL)update force:(BOOL)force {
	
	%orig;
	
	if (IS_IOS6) {
		CFStringRef notificationName;
		switch (orientation) {
			case UIInterfaceOrientationPortrait:
				notificationName = kOrientationPortraitNotification;
				break;
			case UIInterfaceOrientationPortraitUpsideDown:
				notificationName = kOrientationPortraitUpsideDownNotification;
				break;
			case UIInterfaceOrientationLandscapeLeft:
				notificationName = kOrientationLandscapeLeftNotification;
				break;
			case UIInterfaceOrientationLandscapeRight:
				notificationName = kOrientationLandscapeRightNotification;
				break;
		}
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), notificationName, NULL, NULL, true);
	} else {
		isLandscape = UIInterfaceOrientationIsLandscape(orientation);
	}
}

%end

%end

static inline void AddObserver(CFStringRef name, CFNotificationCallback callback) {
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, callback, name, NULL, 0);
}

// Note:
// In iOS 5: ZOTWorkSpace loaded in SpringBoard
// In iOS 6: ZOTWorkspace loaded in backboardd

static inline void loadZoomTouch() {
	// load the zoom touch bundle before hooking its classes
	NSBundle *zoomTouchBundle = [NSBundle bundleWithPath:@"/System/Library/SpringBoardPlugins/ZoomTouch.bundle/"];
	if ([zoomTouchBundle load]) {
		%init(ZoomTouch);
	}
}

static inline void toggleOrientationLock() {
	
	if (!toggleOrientationLockEnabled) return;
	
	SBOrientationLockManager *manager = [objc_getClass("SBOrientationLockManager") sharedInstance];
	if ([manager isLocked]) {
		[manager unlock];
	} else {
		[manager lock];
	}
}

static inline void setShowVolumeHUD(BOOL enabled) {
	NSString *activeCategory;
	[[objc_getClass("AVSystemController") sharedAVSystemController] getActiveCategoryVolume:nil andName:&activeCategory];
	if (activeCategory != nil)
		[[UIApplication sharedApplication] setSystemVolumeHUDEnabled:enabled forAudioCategory:activeCategory];
}

/* preference notification handler */
static inline void reloadPref(ObserverParameters) {
	
	NSDictionary *dict = [[NSDictionary alloc] initWithContentsOfFile:PREF_PATH];
	
	// load options
	NSNumber *_toggleOrientationLockEnabled = [dict objectForKey:@"toggleOrientationLockEnabled"];
	NSNumber *_swipeAction = [dict objectForKey:@"swipeAction"];
	NSNumber *_hideHUD = [dict objectForKey:@"hideHUD"];
	
	toggleOrientationLockEnabled = _toggleOrientationLockEnabled != nil ? [_toggleOrientationLockEnabled boolValue] : YES;
	swipeAction = _swipeAction != nil ? [_swipeAction intValue] : 1;
	hideHUD = _hideHUD != nil ? [_hideHUD boolValue] : NO;
	
	if (swipeAction < 0 || swipeAction > 2) swipeAction = 0;
	
	[dict release];
}

/* backboardd notification handlers */

static inline void _toggleOrientationLockHandler(ObserverParameters) {
	toggleOrientationLock();
}

static inline void _enableZoomHandler(ObserverParameters) {
	[objc_getClass("ZOTWorkspace") enableZoom];
}

static inline void _showVolumeHUDHandler(ObserverParameters) {
	setShowVolumeHUD(YES);
}

static inline void _hideVolumeHUDHandler(ObserverParameters) {
	setShowVolumeHUD(NO);
}

static inline void _orientationPortraitHandler(ObserverParameters) {
	isLandscape = NO;
	shouldFlipCoordinate = NO;
}

static inline void _orientationPortraitUpsideDownHandler(ObserverParameters) {
	isLandscape = NO;
	shouldFlipCoordinate = YES;
}

static inline void _orientationLandscapeLeftHandler(ObserverParameters) {
	isLandscape = YES;
	shouldFlipCoordinate = NO;
}

static inline void _orientationLandscapeRightHandler(ObserverParameters) {
	isLandscape = YES;
	shouldFlipCoordinate = YES;
}

static __attribute__((constructor)) void init() {
	
	@autoreleasepool {
		
		NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
		
		if ([bundleId isEqualToString:@"com.apple.springboard"]) {
			
			// SpringBoard
			isSpringBoard = YES;
			%init(SpringBoard);
			
			if (IS_IOS5) {
				%init(ZoomTouchIOS5);
				loadZoomTouch();
			} else {
				AddObserver(kOrientationLockNotification, &_toggleOrientationLockHandler);
				AddObserver(kVolumeHUDShowNotification, &_showVolumeHUDHandler);
				AddObserver(kVolumeHUDHideNotification, &_hideVolumeHUDHandler);
			}
			
		} else if (IS_IOS6) { // backboardd is only available in iOS 6
			
			// backboardd
			%init(ZoomTouchIOS6);
			loadZoomTouch();
			
			// triggered when SpringBoard finished launching
			AddObserver(kEnableZoomNotification,					&_enableZoomHandler);
			
			// triggered when the interface orientation changes in SpringBoard or the frontmost app
			AddObserver(kOrientationPortraitNotification,			&_orientationPortraitHandler);
			AddObserver(kOrientationPortraitUpsideDownNotification, &_orientationPortraitUpsideDownHandler);
			AddObserver(kOrientationLandscapeLeftNotification,		&_orientationLandscapeLeftHandler);
			AddObserver(kOrientationLandscapeRightNotification,		&_orientationLandscapeRightHandler);
		}
		
		AddObserver(kPreferenceChangedNotification, &reloadPref);
		reloadPref(NULL, NULL, NULL, NULL, NULL);
	}
}