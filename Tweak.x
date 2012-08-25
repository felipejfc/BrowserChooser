#import <SpringBoard/SpringBoard.h>
#import <UIKit/UIKit2.h>
#import <AppList/ALApplicationList.h>

@interface NSURL (iOS5)
- (BOOL)isStoreServicesURL;
- (BOOL)gamecenterURL;
- (BOOL)appleStoreURL;
@end

@interface SpringBoard (iOS5)
- (void)applicationOpenURL:(NSURL *)url publicURLsOnly:(BOOL)only animating:(BOOL)animating sender:(id)sender additionalActivationFlag:(unsigned)additionalActivationFlag;
@end

static NSDictionary *schemeMapping;
static NSInteger suppressed;
static CGPoint lastTapCentroid;

static inline NSString *BCActiveDisplayIdentifier(void)
{
	return [[NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.rpetrich.browserchooser.plist"] objectForKey:@"BCActiveDisplayIdentifier"];
}

static inline NSString *BCReplaceSafariWordInText(NSString *text)
{
	if (text && [text rangeOfString:@"Safari"].location != NSNotFound) {
		// Because Flipboard inspects the button text, we ignore in this app
		if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.flipboard.flipboard-ipad"]) {
			NSString *displayIdentifier = BCActiveDisplayIdentifier();
			NSString *newAppName = displayIdentifier ? [[ALApplicationList sharedApplicationList].applications objectForKey:displayIdentifier] : @"Browser";
			if ([newAppName length]) {
				return [text stringByReplacingOccurrencesOfString:@"Safari" withString:newAppName];
			}
		}
	}
	return text;
}

static inline NSURL *BCApplySchemeReplacementForDisplayIdentifierOnURL(NSString *displayIdentifier, NSURL *url)
{
	NSDictionary *identifierMapping = [schemeMapping objectForKey:displayIdentifier];
	if (identifierMapping) {
		NSString *oldScheme = [url.scheme lowercaseString];
		NSString *absoluteString;
		if ([oldScheme isEqualToString:@"x-web-search"]) {
			oldScheme = @"http";
			if ([[url host] isEqualToString:@"wikipedia"]) {
				absoluteString = @"http://en.m.wikipedia.org/?search=";
			} else {
				absoluteString = @"http://www.google.com/search?q=";
			}
			absoluteString = [absoluteString stringByAppendingString:[url query]];
		} else {
			absoluteString = [url absoluteString];
		}
		NSString *newScheme = [identifierMapping objectForKey:oldScheme];
		BOOL encoded = [[identifierMapping objectForKey:@"encoded"] boolValue];
		if (newScheme){
			if (!encoded)
				url = [NSURL URLWithString:[newScheme stringByAppendingString:[absoluteString substringFromIndex:oldScheme.length]]];
			else {
				NSString *encodedString = [(NSString *)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,(CFStringRef)[absoluteString substringFromIndex:oldScheme.length], NULL,CFSTR(":/=,!$& '()*+;[]@#?"),kCFStringEncodingUTF8) autorelease];
				url = [NSURL URLWithString:[newScheme stringByAppendingString:encodedString]];
			}
		}
	}
	return url;
}

static inline BOOL BCURLPassesPrefilter(NSURL *url)
{
	return ![url isStoreServicesURL] && ![url isWebcalURL] && ![url mapsURL] && ![url youTubeURL] && ![url gamecenterURL] && ![url appleStoreURL];
}

__attribute__((visibility("hidden")))
@interface BCChooserViewController : UIViewController <UIActionSheetDelegate> {
@private
	NSURL *_url;
	id _sender;
	unsigned _additionalActivationFlag;
	NSDictionary *_displayIdentifierTitles;
	NSArray *_orderedDisplayIdentifiers;
	UIActionSheet *_actionSheet;
	UIWindow *_alertWindow;
}
@end

@implementation BCChooserViewController

- (id)initWithURL:(NSURL *)url originalSender:(id)sender additionalActivationFlag:(unsigned)additionalActivationFlag
{
	if ((self = [super init])) {
		_url = [url retain];
		_sender = [sender retain];
		_additionalActivationFlag = additionalActivationFlag;
		_displayIdentifierTitles = [[[ALApplicationList sharedApplicationList] applicationsFilteredUsingPredicate:[NSPredicate predicateWithFormat:@"isBrowserChooserBrowser = TRUE"]] copy];
		_orderedDisplayIdentifiers = [[_displayIdentifierTitles allKeys] retain];
		self.wantsFullScreenLayout = YES;
	}
	return self;
}

- (void)dealloc
{
	[_actionSheet release];
	[_alertWindow release];
	[_orderedDisplayIdentifiers release];
	[_displayIdentifierTitles release];
	[_sender release];
	[_url release];
	[super dealloc];
}

- (void)show
{
	if (!_actionSheet) {
		UIActionSheet *actionSheet = _actionSheet = [[UIActionSheet alloc] init];
		actionSheet.title = @"BrowserChooser";
		actionSheet.delegate = self;
		for (NSString *key in _orderedDisplayIdentifiers)
			[_actionSheet addButtonWithTitle:[_displayIdentifierTitles objectForKey:key]];
		NSInteger cancelButtonIndex = [actionSheet addButtonWithTitle:@"Cancel"];
		if (!_alertWindow) {
			_alertWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
			_alertWindow.windowLevel = 1050.1f /*UIWindowLevelStatusBar*/;
		}
		_alertWindow.hidden = NO;
		_alertWindow.rootViewController = self;
		if ([_alertWindow respondsToSelector:@selector(_updateToInterfaceOrientation:animated:)])
			[_alertWindow _updateToInterfaceOrientation:[(SpringBoard *)UIApp _frontMostAppOrientation] animated:NO];
		if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
			CGRect bounds;
			if ((lastTapCentroid.x == 0.0f) || (lastTapCentroid.y == 0.0f) || isnan(lastTapCentroid.x) || isnan(lastTapCentroid.y)) {
				bounds = self.view.bounds;
				bounds.origin.y += bounds.size.height;
				bounds.size.height = 0.0f;
			} else {
				bounds.origin.x = lastTapCentroid.x - 1.0f;
				bounds.origin.y = lastTapCentroid.y - 1.0f;
				bounds.size.width = 2.0f;
				bounds.size.height = 2.0f;
			}
			[actionSheet showFromRect:bounds inView:self.view animated:YES];
		} else {
			actionSheet.cancelButtonIndex = cancelButtonIndex;
			[actionSheet showInView:self.view];
		}
	}
}

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex
{
	[self retain];
	if (buttonIndex >= 0 && buttonIndex != actionSheet.cancelButtonIndex && buttonIndex < [_orderedDisplayIdentifiers count]) {
		NSURL *adjustedURL = BCApplySchemeReplacementForDisplayIdentifierOnURL([_orderedDisplayIdentifiers objectAtIndex:buttonIndex], _url);
		suppressed++;
		[(SpringBoard *)UIApp applicationOpenURL:adjustedURL publicURLsOnly:NO animating:YES sender:_sender additionalActivationFlag:_additionalActivationFlag];
		suppressed--;
	}
	_actionSheet.delegate = nil;
	[_actionSheet release];
	_actionSheet = nil;
	_alertWindow.hidden = YES;
	_alertWindow.rootViewController = nil;
	[_alertWindow release];
	_alertWindow = nil;
	[self autorelease];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
{
	return (toInterfaceOrientation == UIInterfaceOrientationPortrait) || ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad);
}

@end


%group SpringBoard

%hook SBApplication

%new(c@:)
- (BOOL)isBrowserChooserBrowser
{
	return [schemeMapping objectForKey:self.displayIdentifier] != nil;
}

%end

%hook SBBookmarkIcon

- (void)launch
{
	UIWebClip *webClip = [self webClip];
	NSURL *url = webClip.pageURL;
	if (BCURLPassesPrefilter(url))
		[(SpringBoard *)UIApp applicationOpenURL:url publicURLsOnly:NO animating:YES sender:nil additionalActivationFlag:0];
	else
		%orig;
}

%end

%hook SpringBoard

- (void)applicationOpenURL:(NSURL *)url publicURLsOnly:(BOOL)only animating:(BOOL)animating sender:(id)sender additionalActivationFlag:(unsigned)additionalActivationFlag
{
	if (!suppressed && BCURLPassesPrefilter(url)) {
		NSString *displayIdentifier = BCActiveDisplayIdentifier();
		if (displayIdentifier)
			url = BCApplySchemeReplacementForDisplayIdentifierOnURL(displayIdentifier, url);
		else {
			NSString *scheme = url.scheme;
			if ([scheme hasPrefix:@"http"] || [scheme isEqualToString:@"x-web-search"]) {
				BCChooserViewController *vc = [[BCChooserViewController alloc] initWithURL:url originalSender:sender additionalActivationFlag:additionalActivationFlag];
				[vc show];
				[vc release];
				return;
			}
		}
	}
	%orig;
}

%end

%hook SBHandMotionExtractor

- (void)extractHandMotionForActiveTouches:(void *)activeTouches count:(NSUInteger)count centroid:(CGPoint)centroid
{
	if (count && !isnan(centroid.x) && !isnan(centroid.y))
		lastTapCentroid = centroid;
	%orig;
}

%end

%end

%group App

%hook UIActionSheet

- (void)addButtonWithTitle:(NSString *)title
{
	%orig(BCReplaceSafariWordInText(title));
}

%end

%hook UIAlertView

- (void)addButtonWithTitle:(NSString *)title
{
	%orig(BCReplaceSafariWordInText(title));
}

- (void)setTitle:(NSString *)title
{
	%orig(BCReplaceSafariWordInText(title));
}

- (void)setMessage:(NSString *)message
{
	%orig(BCReplaceSafariWordInText(message));
}

%end

%hook UIButton

- (void)setTitle:(NSString *)title forState:(UIControlState)state
{
	%orig(BCReplaceSafariWordInText(title), state);
}

%end

%end

%ctor
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	schemeMapping = [[NSDictionary alloc] initWithContentsOfFile:@"/Library/Application Support/BrowserChooser/mapping.plist"];
	%init;
	if (%c(SpringBoard)) {
		%init(SpringBoard);
	} else {
		%init(App);
	}
	[pool drain];
}
