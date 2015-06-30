/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */

#import "CDVInAppBrowser.h"
#import <Cordova/CDVPluginResult.h>
#import <Cordova/CDVUserAgentUtil.h>
#import <CoreText/CoreText.h>

#define    kInAppBrowserTargetSelf @"_self"
#define    kInAppBrowserTargetSystem @"_system"
#define    kInAppBrowserTargetBlank @"_blank"

#define    TOOLBAR_HEIGHT 55.f
#define    BUTTON_WIDTH 48.f
#define    GAP_WIDTH 10.f
#define    PADDING_WIDTH 15.f
#define    MELIUZ_RED [UIColor colorWithRed:241.f / 255.f green:57.f / 255.f blue:0.f / 255.f alpha:1];

#pragma mark CDVInAppBrowser

@interface CDVInAppBrowser () {
    NSInteger _previousStatusBarStyle;
}
@end

@implementation CDVInAppBrowser

- (void)pluginInitialize {
    _previousStatusBarStyle = -1;
    _callbackIdPattern = nil;
}

- (void)onReset {
    [self close:nil];
}

- (void)close:(CDVInvokedUrlCommand *)command {
    if (self.inAppBrowserViewController == nil) {
        NSLog(@"IAB.close() called but it was already closed.");
        return;
    }
    // Things are cleaned up in browserExit.
    [self.inAppBrowserViewController close];
}

- (BOOL)isSystemUrl:(NSURL *)url {
    if ([[url host] isEqualToString:@"itunes.apple.com"]) {
        return YES;
    }

    return NO;
}

- (void)open:(CDVInvokedUrlCommand *)command {
    CDVPluginResult* pluginResult;

    NSString* url = [command argumentAtIndex:0];
    NSString* target = [command argumentAtIndex:1 withDefault:kInAppBrowserTargetSelf];
    NSString* options = [command argumentAtIndex:2 withDefault:@"" andClass:[NSString class]];

    self.callbackId = command.callbackId;

    if (url != nil) {
#ifdef __CORDOVA_4_0_0
        NSURL* baseUrl = [self.webViewEngine URL];
#else
        NSURL* baseUrl = [self.webView.request URL];
#endif
        NSURL* absoluteUrl = [[NSURL URLWithString:url relativeToURL:baseUrl] absoluteURL];

        if ([self isSystemUrl:absoluteUrl]) {
            target = kInAppBrowserTargetSystem;
        }

        if ([target isEqualToString:kInAppBrowserTargetSelf]) {
            [self openInCordovaWebView:absoluteUrl withOptions:options];
        } else if ([target isEqualToString:kInAppBrowserTargetSystem]) {
            [self openInSystem:absoluteUrl];
        } else { // _blank or anything else
            [self openInInAppBrowser:absoluteUrl withOptions:options];
        }

        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"incorrect number of arguments"];
    }

    [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)openInInAppBrowser:(NSURL *)url withOptions:(NSString *)options {
    CDVInAppBrowserOptions* browserOptions = [CDVInAppBrowserOptions parseOptions:options];

    if (browserOptions.clearcache) {
        NSHTTPCookie *cookie;
        NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        for (cookie in [storage cookies]) {
            if (![cookie.domain isEqual: @".^filecookies^"]) {
                [storage deleteCookie:cookie];
            }
        }
    }

    if (browserOptions.clearsessioncache) {
        NSHTTPCookie *cookie;
        NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        for (cookie in [storage cookies]) {
            if (![cookie.domain isEqual: @".^filecookies^"] && cookie.isSessionOnly) {
                [storage deleteCookie:cookie];
            }
        }
    }

    if (self.inAppBrowserViewController == nil) {
        NSString* originalUA = [CDVUserAgentUtil originalUserAgent];
        self.inAppBrowserViewController = [[CDVInAppBrowserViewController alloc] initWithUserAgent:originalUA prevUserAgent:[self.commandDelegate userAgent] browserOptions: browserOptions];
        self.inAppBrowserViewController.navigationDelegate = self;

        if ([self.viewController conformsToProtocol:@protocol(CDVScreenOrientationDelegate)]) {
            self.inAppBrowserViewController.orientationDelegate = (UIViewController <CDVScreenOrientationDelegate>*)self.viewController;
        }
    }

    // Set Presentation Style
    UIModalPresentationStyle presentationStyle = UIModalPresentationFullScreen; // default
    if (browserOptions.presentationstyle != nil) {
        if ([[browserOptions.presentationstyle lowercaseString] isEqualToString:@"pagesheet"]) {
            presentationStyle = UIModalPresentationPageSheet;
        } else if ([[browserOptions.presentationstyle lowercaseString] isEqualToString:@"formsheet"]) {
            presentationStyle = UIModalPresentationFormSheet;
        }
    }
    self.inAppBrowserViewController.modalPresentationStyle = presentationStyle;

    // Set Transition Style
    UIModalTransitionStyle transitionStyle = UIModalTransitionStyleCoverVertical; // default
    if (browserOptions.transitionstyle != nil) {
        if ([[browserOptions.transitionstyle lowercaseString] isEqualToString:@"fliphorizontal"]) {
            transitionStyle = UIModalTransitionStyleFlipHorizontal;
        } else if ([[browserOptions.transitionstyle lowercaseString] isEqualToString:@"crossdissolve"]) {
            transitionStyle = UIModalTransitionStyleCrossDissolve;
        }
    }
    self.inAppBrowserViewController.modalTransitionStyle = transitionStyle;

    // prevent webView from bouncing
    if (browserOptions.disallowoverscroll) {
        if ([self.inAppBrowserViewController.webView respondsToSelector:@selector(scrollView)]) {
            ((UIScrollView *)[self.inAppBrowserViewController.webView scrollView]).bounces = NO;
        } else {
            for (id subview in self.inAppBrowserViewController.webView.subviews) {
                if ([[subview class] isSubclassOfClass:[UIScrollView class]]) {
                    ((UIScrollView *)subview).bounces = NO;
                }
            }
        }
    }

    // UIWebView options
    self.inAppBrowserViewController.webView.scalesPageToFit = browserOptions.enableviewportscale;
    self.inAppBrowserViewController.webView.mediaPlaybackRequiresUserAction = browserOptions.mediaplaybackrequiresuseraction;
    self.inAppBrowserViewController.webView.allowsInlineMediaPlayback = browserOptions.allowinlinemediaplayback;
    if (IsAtLeastiOSVersion(@"6.0")) {
        self.inAppBrowserViewController.webView.keyboardDisplayRequiresUserAction = browserOptions.keyboarddisplayrequiresuseraction;
        self.inAppBrowserViewController.webView.suppressesIncrementalRendering = browserOptions.suppressesincrementalrendering;
    }

    [self.inAppBrowserViewController navigateTo:url];
    if (!browserOptions.hidden) {
        [self show:nil];
    }
}

- (void)show:(CDVInvokedUrlCommand *)command {
    if (self.inAppBrowserViewController == nil) {
        NSLog(@"Tried to show IAB after it was closed.");
        return;
    }
    if (_previousStatusBarStyle != -1) {
        NSLog(@"Tried to show IAB while already shown");
        return;
    }

    _previousStatusBarStyle = [UIApplication sharedApplication].statusBarStyle;

    CDVInAppBrowserNavigationController* nav = [[CDVInAppBrowserNavigationController alloc]
                                   initWithRootViewController:self.inAppBrowserViewController];
    nav.orientationDelegate = self.inAppBrowserViewController;
    nav.navigationBarHidden = YES;
    // Run later to avoid the "took a long time" log message.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.inAppBrowserViewController != nil) {
            [self.viewController presentViewController:nav animated:YES completion:nil];
        }
    });
}

- (void)openInCordovaWebView:(NSURL *)url withOptions:(NSString *)options {
    if ([self.commandDelegate URLIsWhitelisted:url]) {
        NSURLRequest* request = [NSURLRequest requestWithURL:url];
#ifdef __CORDOVA_4_0_0
        [self.webViewEngine loadRequest:request];
#else
        [self.webView loadRequest:request];
#endif
    } else { // this assumes the InAppBrowser can be excepted from the white-list
        [self openInInAppBrowser:url withOptions:options];
    }
}

- (void)openInSystem:(NSURL *)url {
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url];
    } else { // handle any custom schemes to plugins
        [[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:CDVPluginHandleOpenURLNotification object:url]];
    }
}

// This is a helper method for the inject{Script|Style}{Code|File} API calls, which
// provides a consistent method for injecting JavaScript code into the document.
//
// If a wrapper string is supplied, then the source string will be JSON-encoded (adding
// quotes) and wrapped using string formatting. (The wrapper string should have a single
// '%@' marker).
//
// If no wrapper is supplied, then the source string is executed directly.

- (void)injectDeferredObject:(NSString *)source withWrapper:(NSString *)jsWrapper {
    if (!_injectedIframeBridge) {
        _injectedIframeBridge = YES;
        // Create an iframe bridge in the new document to communicate with the CDVInAppBrowserViewController
        [self.inAppBrowserViewController.webView stringByEvaluatingJavaScriptFromString:@"(function(d){var e = _cdvIframeBridge = d.createElement('iframe');e.style.display='none';d.body.appendChild(e);})(document)"];
    }

    if (jsWrapper != nil) {
        NSData* jsonData = [NSJSONSerialization dataWithJSONObject:@[source] options:0 error:nil];
        NSString* sourceArrayString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        if (sourceArrayString) {
            NSString* sourceString = [sourceArrayString substringWithRange:NSMakeRange(1, [sourceArrayString length] - 2)];
            NSString* jsToInject = [NSString stringWithFormat:jsWrapper, sourceString];
            [self.inAppBrowserViewController.webView stringByEvaluatingJavaScriptFromString:jsToInject];
        }
    } else {
        [self.inAppBrowserViewController.webView stringByEvaluatingJavaScriptFromString:source];
    }
}

- (void)injectScriptCode:(CDVInvokedUrlCommand *)command {
    NSString* jsWrapper = nil;

    if ((command.callbackId != nil) && ![command.callbackId isEqualToString:@"INVALID"]) {
        jsWrapper = [NSString stringWithFormat:@"_cdvIframeBridge.src='gap-iab://%@/'+encodeURIComponent(JSON.stringify([eval(%%@)]));", command.callbackId];
    }
    [self injectDeferredObject:[command argumentAtIndex:0] withWrapper:jsWrapper];
}

- (void)injectScriptFile:(CDVInvokedUrlCommand *)command {
    NSString* jsWrapper;

    if ((command.callbackId != nil) && ![command.callbackId isEqualToString:@"INVALID"]) {
        jsWrapper = [NSString stringWithFormat:@"(function(d) { var c = d.createElement('script'); c.src = %%@; c.onload = function() { _cdvIframeBridge.src='gap-iab://%@'; }; d.body.appendChild(c); })(document)", command.callbackId];
    } else {
        jsWrapper = @"(function(d) { var c = d.createElement('script'); c.src = %@; d.body.appendChild(c); })(document)";
    }
    [self injectDeferredObject:[command argumentAtIndex:0] withWrapper:jsWrapper];
}

- (void)injectStyleCode:(CDVInvokedUrlCommand *)command {
    NSString* jsWrapper;

    if ((command.callbackId != nil) && ![command.callbackId isEqualToString:@"INVALID"]) {
        jsWrapper = [NSString stringWithFormat:@"(function(d) { var c = d.createElement('style'); c.innerHTML = %%@; c.onload = function() { _cdvIframeBridge.src='gap-iab://%@'; }; d.body.appendChild(c); })(document)", command.callbackId];
    } else {
        jsWrapper = @"(function(d) { var c = d.createElement('style'); c.innerHTML = %@; d.body.appendChild(c); })(document)";
    }
    [self injectDeferredObject:[command argumentAtIndex:0] withWrapper:jsWrapper];
}

- (void)injectStyleFile:(CDVInvokedUrlCommand *)command {
    NSString* jsWrapper;

    if ((command.callbackId != nil) && ![command.callbackId isEqualToString:@"INVALID"]) {
        jsWrapper = [NSString stringWithFormat:@"(function(d) { var c = d.createElement('link'); c.rel='stylesheet'; c.type='text/css'; c.href = %%@; c.onload = function() { _cdvIframeBridge.src='gap-iab://%@'; }; d.body.appendChild(c); })(document)", command.callbackId];
    } else {
        jsWrapper = @"(function(d) { var c = d.createElement('link'); c.rel='stylesheet', c.type='text/css'; c.href = %@; d.body.appendChild(c); })(document)";
    }
    [self injectDeferredObject:[command argumentAtIndex:0] withWrapper:jsWrapper];
}

- (BOOL)isValidCallbackId:(NSString *)callbackId {
    NSError *err = nil;
    // Initialize on first use
    if (self.callbackIdPattern == nil) {
        self.callbackIdPattern = [NSRegularExpression regularExpressionWithPattern:@"^InAppBrowser[0-9]{1,10}$" options:0 error:&err];
        if (err != nil) {
            // Couldn't initialize Regex; No is safer than Yes.
            return NO;
        }
    }
    if ([self.callbackIdPattern firstMatchInString:callbackId options:0 range:NSMakeRange(0, [callbackId length])]) {
        return YES;
    }
    return NO;
}

/**
 * The iframe bridge provided for the InAppBrowser is capable of executing any oustanding callback belonging
 * to the InAppBrowser plugin. Care has been taken that other callbacks cannot be triggered, and that no
 * other code execution is possible.
 *
 * To trigger the bridge, the iframe (or any other resource) should attempt to load a url of the form:
 *
 * gap-iab://<callbackId>/<arguments>
 *
 * where <callbackId> is the string id of the callback to trigger (something like "InAppBrowser0123456789")
 *
 * If present, the path component of the special gap-iab:// url is expected to be a URL-escaped JSON-encoded
 * value to pass to the callback. [NSURL path] should take care of the URL-unescaping, and a JSON_EXCEPTION
 * is returned if the JSON is invalid.
 */
- (BOOL)webView:(UIWebView *)theWebView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
    NSURL* url = request.URL;
    BOOL isTopLevelNavigation = [request.URL isEqual:[request mainDocumentURL]];

    // See if the url uses the 'gap-iab' protocol. If so, the host should be the id of a callback to execute,
    // and the path, if present, should be a JSON-encoded value to pass to the callback.
    if ([[url scheme] isEqualToString:@"gap-iab"]) {
        NSString* scriptCallbackId = [url host];
        CDVPluginResult* pluginResult = nil;

        if ([self isValidCallbackId:scriptCallbackId]) {
            NSString* scriptResult = [url path];
            NSError* __autoreleasing error = nil;

            // The message should be a JSON-encoded array of the result of the script which executed.
            if ((scriptResult != nil) && ([scriptResult length] > 1)) {
                scriptResult = [scriptResult substringFromIndex:1];
                NSData* decodedResult = [NSJSONSerialization JSONObjectWithData:[scriptResult dataUsingEncoding:NSUTF8StringEncoding] options:kNilOptions error:&error];
                if ((error == nil) && [decodedResult isKindOfClass:[NSArray class]]) {
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:(NSArray *)decodedResult];
                } else {
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_JSON_EXCEPTION];
                }
            } else {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:@[]];
            }
            [self.commandDelegate sendPluginResult:pluginResult callbackId:scriptCallbackId];
            return NO;
        }
    } else if ((self.callbackId != nil) && isTopLevelNavigation) {
        // Send a loadstart event for each top-level navigation (includes redirects).
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsDictionary:@{@"type":@"loadstart", @"url":[url absoluteString]}];
        [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];

        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
    }

    return YES;
}

- (void)webViewDidStartLoad:(UIWebView *)theWebView {
    _injectedIframeBridge = NO;
}

- (void)webViewDidFinishLoad:(UIWebView *)theWebView {
    if (self.callbackId != nil) {
        // TODO: It would be more useful to return the URL the page is actually on (e.g. if it's been redirected).
        NSString* url = [self.inAppBrowserViewController.currentURL absoluteString];
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsDictionary:@{@"type":@"loadstop", @"url":url}];
        [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];

        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
    }
}

- (void)webView:(UIWebView *)theWebView didFailLoadWithError:(NSError *)error {
    if (self.callbackId != nil) {
        NSString* url = [self.inAppBrowserViewController.currentURL absoluteString];
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                      messageAsDictionary:@{@"type":@"loaderror", @"url":url, @"code": [NSNumber numberWithInteger:error.code], @"message": error.localizedDescription}];
        [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];

        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
    }
}

- (void)browserExit {
    if (self.callbackId != nil) {
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsDictionary:@{@"type":@"exit"}];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
        self.callbackId = nil;
    }
    // Set navigationDelegate to nil to ensure no callbacks are received from it.
    self.inAppBrowserViewController.navigationDelegate = nil;
    // Don't recycle the ViewController since it may be consuming a lot of memory.
    // Also - this is required for the PDF/User-Agent bug work-around.
    self.inAppBrowserViewController = nil;

    if (IsAtLeastiOSVersion(@"7.0")) {
        [[UIApplication sharedApplication] setStatusBarStyle:_previousStatusBarStyle];
    }

    _previousStatusBarStyle = -1; // this value was reset before reapplying it. caused statusbar to stay black on ios7
}

@end

#pragma mark CDVInAppBrowserViewController

@implementation CDVInAppBrowserViewController

@synthesize currentURL;

- (id)initWithUserAgent:(NSString *)userAgent prevUserAgent:(NSString *)prevUserAgent browserOptions: (CDVInAppBrowserOptions *) browserOptions {
    self = [super init];
    if (self != nil) {
        _userAgent = userAgent;
        _prevUserAgent = prevUserAgent;
        _browserOptions = browserOptions;
#ifdef __CORDOVA_4_0_0
        _webViewDelegate = [[CDVUIWebViewDelegate alloc] initWithDelegate:self];
#else
        _webViewDelegate = [[CDVWebViewDelegate alloc] initWithDelegate:self];
#endif
        
        [self createViews];
    }

    return self;
}

- (void)createViews {
    // We create the views in code for primarily for ease of upgrades and not requiring an external .xib to be included

    CGRect webViewBounds = self.view.bounds;
    webViewBounds.size.height -= 2 * TOOLBAR_HEIGHT;
    self.webView = [[UIWebView alloc] initWithFrame:webViewBounds];
    self.webView.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
    self.webView.delegate = _webViewDelegate;
    self.webView.clearsContextBeforeDrawing = YES;
    self.webView.clipsToBounds = YES;
    self.webView.contentMode = UIViewContentModeScaleToFill;
    self.webView.multipleTouchEnabled = YES;
    self.webView.opaque = YES;
    self.webView.scalesPageToFit = NO;
    self.webView.userInteractionEnabled = YES;
    
    [self.view addSubview:self.webView];
    [self.view sendSubviewToBack:self.webView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.alpha = 1.f;
    self.spinner.autoresizesSubviews = YES;
    self.spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
    self.spinner.clearsContextBeforeDrawing = NO;
    self.spinner.clipsToBounds = NO;
    self.spinner.contentMode = UIViewContentModeScaleToFill;
    self.spinner.frame = CGRectMake((self.webView.bounds.size.width - 20.f) / 2, (self.webView.bounds.size.height - 20.f) / 2, 20.f, 20.f);
    self.spinner.hidden = YES;
    self.spinner.hidesWhenStopped = YES;
    self.spinner.multipleTouchEnabled = NO;
    self.spinner.opaque = NO;
    self.spinner.userInteractionEnabled = NO;
    [self.spinner stopAnimating];

    self.topToolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0.f, 0.f, self.view.bounds.size.width, TOOLBAR_HEIGHT)];
    self.topToolbar.autoresizesSubviews = YES;
    self.topToolbar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.topToolbar.barTintColor = [UIColor whiteColor];
    self.topToolbar.clearsContextBeforeDrawing = NO;
    self.topToolbar.clipsToBounds = NO;
    self.topToolbar.contentMode = UIViewContentModeScaleToFill;
    self.topToolbar.hidden = NO;
    self.topToolbar.multipleTouchEnabled = NO;
    self.topToolbar.opaque = YES;
    self.bottomToolbar.translucent = NO;
    self.bottomToolbar.barStyle = UIBarStyleBlack;
    self.topToolbar.userInteractionEnabled = YES;

    NSString *closeIconPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"/www/assets/images/icon-close.png"];
    UIImage *closeIcon = [UIImage imageWithContentsOfFile:closeIconPath];
    UIButton *closeIconButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [closeIconButton addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    closeIconButton.bounds = CGRectMake(0, 0, closeIcon.size.width, closeIcon.size.height);
    [closeIconButton setImage:closeIcon forState:UIControlStateNormal];
    // [closeIconButton setBackgroundColor:[UIColor yellowColor]];
    self.closeButton = [[UIBarButtonItem alloc] initWithCustomView:closeIconButton];
    self.closeButton.enabled = YES;

    UIView *titleView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, [self getTitleButtonWidth], TOOLBAR_HEIGHT)];
    titleView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.titleButton = [[UIBarButtonItem alloc] initWithCustomView:titleView];
    [self.titleButton setTag:911];
    
    [self.topToolbar setItems:@[self.closeButton, self.titleButton]];

    [self setTitleButtonTitle:@"CARREGANDO..."];

    self.bottomToolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0.f, self.view.bounds.size.height - TOOLBAR_HEIGHT, self.view.bounds.size.width, TOOLBAR_HEIGHT)];
    self.bottomToolbar.autoresizesSubviews = YES;
    self.bottomToolbar.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin);
    self.bottomToolbar.barTintColor = [UIColor whiteColor];
    self.bottomToolbar.clearsContextBeforeDrawing = NO;
    self.bottomToolbar.clipsToBounds = NO;
    self.bottomToolbar.contentMode = UIViewContentModeScaleToFill;
    self.bottomToolbar.hidden = NO;
    self.bottomToolbar.multipleTouchEnabled = NO;
    self.bottomToolbar.opaque = YES;
    self.bottomToolbar.translucent = NO;
    self.bottomToolbar.barStyle = UIBarStyleBlack;
    self.bottomToolbar.userInteractionEnabled = YES;

    UIView *cashbackView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, [self getCashbackButtonWidth], TOOLBAR_HEIGHT)];
    cashbackView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.cashbackButton = [[UIBarButtonItem alloc] initWithCustomView:cashbackView];
    [self.cashbackButton setTag:912];
    
    NSString *forwardIconPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"/www/assets/images/icon-forward.png"];
    UIImage *forwardIcon = [UIImage imageWithContentsOfFile:forwardIconPath];
    UIButton *forwardIconButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [forwardIconButton addTarget:self action:@selector(goForward:) forControlEvents:UIControlEventTouchUpInside];
    forwardIconButton.bounds = CGRectMake(0, 0, forwardIcon.size.width, forwardIcon.size.height);
    [forwardIconButton setImage:forwardIcon forState:UIControlStateNormal];
    // [forwardIconButton setBackgroundColor:[UIColor yellowColor]];
    self.forwardButton = [[UIBarButtonItem alloc] initWithCustomView:forwardIconButton];
    
    NSString *backIconPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"/www/assets/images/icon-back.png"];
    UIImage *backIcon = [UIImage imageWithContentsOfFile:backIconPath];
    UIButton *backIconButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [backIconButton addTarget:self action:@selector(goBack:) forControlEvents:UIControlEventTouchUpInside];
    backIconButton.bounds = CGRectMake(0, 0, backIcon.size.width, backIcon.size.height);
    [backIconButton setImage:backIcon forState:UIControlStateNormal];
    // [backIconButton setBackgroundColor:[UIColor yellowColor]];
    self.backButton = [[UIBarButtonItem alloc] initWithCustomView:backIconButton];
    
    [self.bottomToolbar setItems:@[self.cashbackButton, self.backButton, self.forwardButton]];

    [self setCashbackButtonTitle:@"" mobileFriendly:NO];

    self.view.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:self.topToolbar];
    [self.view addSubview:self.bottomToolbar];
    [self.view addSubview:self.spinner];
}

- (CGFloat)getTitleButtonWidth {
    return self.topToolbar.frame.size.width - (2 * BUTTON_WIDTH) - (2 * PADDING_WIDTH) - (2 * GAP_WIDTH);
}

- (void)setTitleButtonTitle:(NSString *)title {
    self.titleButton = nil;
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, [self getTitleButtonWidth], TOOLBAR_HEIGHT)];
    titleLabel.text = [title uppercaseString];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.textColor = MELIUZ_RED;
    titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    // titleLabel.backgroundColor = [UIColor yellowColor];
    
    NSString *fpath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"/www/assets/fonts/source-sans/SourceSansPro-Regular.ttf"];
    CGDataProviderRef fontDataProvider = CGDataProviderCreateWithFilename([fpath UTF8String]);
    CGFontRef customFont = CGFontCreateWithDataProvider(fontDataProvider);
    CGDataProviderRelease(fontDataProvider);
    NSString *fontName = (__bridge NSString *)CGFontCopyFullName(customFont);
    CFErrorRef error;
    CTFontManagerRegisterGraphicsFont(customFont, &error);
    CGFontRelease(customFont);
    UIFont *uifont = [UIFont fontWithName:fontName size:19];
    
    titleLabel.font = uifont;
    self.titleButton = [[UIBarButtonItem alloc] initWithCustomView:titleLabel];
    [self.titleButton setTag:911];

    NSMutableArray* items = [self.topToolbar.items mutableCopy];
    [items replaceObjectAtIndex:1 withObject:self.titleButton];
    [self.topToolbar setItems:items];
}

- (CGFloat)getCashbackButtonWidth {
    return self.bottomToolbar.frame.size.width - (2 * BUTTON_WIDTH) - (2 * PADDING_WIDTH) - (2 * GAP_WIDTH);
}

- (void)setCashbackButtonTitle:(NSString *)title mobileFriendly:(BOOL)mobileFriendly {
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, [self getCashbackButtonWidth], TOOLBAR_HEIGHT)];

    // load font from file
    NSString *fpath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"/www/assets/fonts/source-sans/SourceSansPro-Regular.ttf"];
    CGDataProviderRef fontDataProvider = CGDataProviderCreateWithFilename([fpath UTF8String]);
    CGFontRef customFont = CGFontCreateWithDataProvider(fontDataProvider);
    CGDataProviderRelease(fontDataProvider);
    NSString *fontName = (__bridge NSString *)CGFontCopyFullName(customFont);
    CFErrorRef error;
    CTFontManagerRegisterGraphicsFont(customFont, &error);
    CGFontRelease(customFont);
    UIFont *uifont = [UIFont fontWithName:fontName size:19];

    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:title];
    [attributedString addAttribute:NSFontAttributeName value:uifont range:NSMakeRange(0, [attributedString length])];
    [attributedString addAttribute:NSForegroundColorAttributeName value:[UIColor colorWithRed:241.f / 255.f green:57.f / 255.f blue:0.f / 255.f alpha:1] range:NSMakeRange(0, [attributedString length])];
    if (!mobileFriendly) {
        // strike through text
        [attributedString addAttribute:NSStrikethroughStyleAttributeName value:@(NSUnderlineStyleSingle) range:NSMakeRange(0, [attributedString length])];
        [attributedString addAttribute:NSForegroundColorAttributeName value:[UIColor grayColor] range:NSMakeRange(0, [attributedString length])];
    }
    titleLabel.attributedText = attributedString;
    titleLabel.textAlignment = NSTextAlignmentLeft;
    titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    // titleLabel.backgroundColor = [UIColor yellowColor];
    
    self.cashbackButton = [[UIBarButtonItem alloc] initWithCustomView:titleLabel];
    [self.cashbackButton setTag:912];

    NSMutableArray* items = [self.bottomToolbar.items mutableCopy];
    [items replaceObjectAtIndex:0 withObject:self.cashbackButton];
    [self.bottomToolbar setItems:items];
}

- (void)showCodeButton {
    NSString *codeIconPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"/www/assets/images/icon-code.png"];
    UIImage *codeIcon = [UIImage imageWithContentsOfFile:codeIconPath];
    UIButton *codeIconButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [codeIconButton addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    codeIconButton.bounds = CGRectMake(0, 0, codeIcon.size.width, codeIcon.size.height);
    [codeIconButton setImage:codeIcon forState:UIControlStateNormal];
    // [codeIconButton setBackgroundColor:[UIColor yellowColor]];
    self.codeButton = [[UIBarButtonItem alloc] initWithCustomView:codeIconButton];
    self.codeButton.enabled = YES;

    [self.topToolbar setItems:@[self.closeButton, self.titleButton, self.codeButton]];
}

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (void)viewDidUnload {
    [self.webView loadHTMLString:nil baseURL:nil];
    [CDVUserAgentUtil releaseLock:&_userAgentLockToken];
    [super viewDidUnload];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleDefault;
}

- (void)close {
    [CDVUserAgentUtil releaseLock:&_userAgentLockToken];
    self.currentURL = nil;

    if ((self.navigationDelegate != nil) && [self.navigationDelegate respondsToSelector:@selector(browserExit)]) {
        [self.navigationDelegate browserExit];
    }

    // Run later to avoid the "took a long time" log message.
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self respondsToSelector:@selector(presentingViewController)]) {
            [[self presentingViewController] dismissViewControllerAnimated:YES completion:nil];
        } else {
            [[self parentViewController] dismissViewControllerAnimated:YES completion:nil];
        }
    });
}

- (void)navigateTo:(NSURL *)url {
    NSURLRequest* request = [NSURLRequest requestWithURL:url];

    if (_userAgentLockToken != 0) {
        [self.webView loadRequest:request];
    } else {
        [CDVUserAgentUtil acquireLock:^(NSInteger lockToken) {
            _userAgentLockToken = lockToken;
            [CDVUserAgentUtil setUserAgent:_userAgent lockToken:lockToken];
            [self.webView loadRequest:request];
        }];
    }
}

- (void)goBack:(id)sender {
    [self.webView goBack];
}

- (void)goForward:(id)sender {
    [self.webView goForward];
}

- (void)viewWillAppear:(BOOL)animated {
    if (IsAtLeastiOSVersion(@"7.0")) {
        [[UIApplication sharedApplication] setStatusBarStyle:[self preferredStatusBarStyle]];
    }
    [self rePositionViews];

    [super viewWillAppear:animated];
}

//
// On iOS 7 the status bar is part of the view's dimensions, therefore it's height has to be taken into account.
// The height of it could be hardcoded as 20 pixels, but that would assume that the upcoming releases of iOS won't
// change that value.
//
- (float)getStatusBarOffset {
    CGRect statusBarFrame = [[UIApplication sharedApplication] statusBarFrame];
    float statusBarOffset = IsAtLeastiOSVersion(@"7.0") ? MIN(statusBarFrame.size.width, statusBarFrame.size.height) : 0.f;
    return statusBarOffset;
}

- (void)rePositionViews {
    [self.webView setFrame:CGRectMake(self.webView.frame.origin.x, TOOLBAR_HEIGHT, self.webView.frame.size.width, self.webView.frame.size.height)];
    [self.topToolbar setFrame:CGRectMake(self.topToolbar.frame.origin.x, [self getStatusBarOffset], self.topToolbar.frame.size.width, self.topToolbar.frame.size.height)];
    [self.bottomToolbar setFrame:CGRectMake(self.bottomToolbar.frame.origin.x, self.view.bounds.size.height - TOOLBAR_HEIGHT, self.bottomToolbar.frame.size.width, self.bottomToolbar.frame.size.height)];
}

- (void)updateInterface {
    BOOL mobileFriendly = [[self.webView stringByEvaluatingJavaScriptFromString:@"window.meliuz.mobileFriendly"] isEqualToString:@"true"];
    NSString *storeTitle = [self.webView stringByEvaluatingJavaScriptFromString:@"window.meliuz.storeTitle"];
    NSString *cashbackString = [self.webView stringByEvaluatingJavaScriptFromString:@"window.meliuz.cashbackString"];
    NSString *couponCode = [self.webView stringByEvaluatingJavaScriptFromString:@"window.meliuz.couponCode"];
    [self setTitleButtonTitle:storeTitle];
    [self setCashbackButtonTitle:cashbackString mobileFriendly:mobileFriendly];
    if ([couponCode length] > 0) {
        [self showCodeButton];
    }
    self.checkedVars = YES;
}

- (void)checkVariables {
    if (!self.checkedVars) {
        [self updateInterface];
    }
}

#pragma mark UIWebViewDelegate

- (void)webViewDidStartLoad:(UIWebView *)theWebView {
    // loading url, start spinner, update back/forward

    self.addressLabel.text = NSLocalizedString(@"Loading...", nil);
    self.backButton.enabled = theWebView.canGoBack;
    self.forwardButton.enabled = theWebView.canGoForward;

    [self.spinner startAnimating];

    return [self.navigationDelegate webViewDidStartLoad:theWebView];
}

- (BOOL)webView:(UIWebView *)theWebView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
    BOOL isTopLevelNavigation = [request.URL isEqual:[request mainDocumentURL]];

    if (isTopLevelNavigation) {
        self.currentURL = request.URL;
    }
    return [self.navigationDelegate webView:theWebView shouldStartLoadWithRequest:request navigationType:navigationType];
}

- (void)webViewDidFinishLoad:(UIWebView *)theWebView {
    // update url, stop spinner, update back/forward

    self.addressLabel.text = [self.currentURL absoluteString];
    self.backButton.enabled = theWebView.canGoBack;
    self.forwardButton.enabled = theWebView.canGoForward;

    [self.spinner stopAnimating];

    // Work around a bug where the first time a PDF is opened, all UIWebViews
    // reload their User-Agent from NSUserDefaults.
    // This work-around makes the following assumptions:
    // 1. The app has only a single Cordova Webview. If not, then the app should
    //    take it upon themselves to load a PDF in the background as a part of
    //    their start-up flow.
    // 2. That the PDF does not require any additional network requests. We change
    //    the user-agent here back to that of the CDVViewController, so requests
    //    from it must pass through its white-list. This *does* break PDFs that
    //    contain links to other remote PDF/websites.
    // More info at https://issues.apache.org/jira/browse/CB-2225
    BOOL isPDF = [@"true" isEqualToString :[theWebView stringByEvaluatingJavaScriptFromString:@"document.body==null"]];
    if (isPDF) {
        [CDVUserAgentUtil setUserAgent:_prevUserAgent lockToken:_userAgentLockToken];
    }

    // Check for variables
    [self checkVariables];

    [self.navigationDelegate webViewDidFinishLoad:theWebView];
}

- (void)webView:(UIWebView *)theWebView didFailLoadWithError:(NSError *)error {
    // log fail message, stop spinner, update back/forward
    NSLog(@"webView:didFailLoadWithError - %ld: %@", (long)error.code, [error localizedDescription]);

    self.backButton.enabled = theWebView.canGoBack;
    self.forwardButton.enabled = theWebView.canGoForward;
    [self.spinner stopAnimating];

    self.addressLabel.text = NSLocalizedString(@"Load Error", nil);

    [self.navigationDelegate webView:theWebView didFailLoadWithError:error];
}

#pragma mark CDVScreenOrientationDelegate

- (BOOL)shouldAutorotate {
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(shouldAutorotate)]) {
        return [self.orientationDelegate shouldAutorotate];
    }
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations {
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(supportedInterfaceOrientations)]) {
        return [self.orientationDelegate supportedInterfaceOrientations];
    }

    return 1 << UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(shouldAutorotateToInterfaceOrientation:)]) {
        return [self.orientationDelegate shouldAutorotateToInterfaceOrientation:interfaceOrientation];
    }

    return YES;
}

@end

@implementation CDVInAppBrowserOptions

- (id)init {
    if (self = [super init]) {
        // default values
        self.closebuttoncaption = nil;
        self.clearcache = NO;
        self.clearsessioncache = NO;

        self.enableviewportscale = NO;
        self.mediaplaybackrequiresuseraction = NO;
        self.allowinlinemediaplayback = NO;
        self.keyboarddisplayrequiresuseraction = YES;
        self.suppressesincrementalrendering = NO;
        self.hidden = NO;
        self.disallowoverscroll = NO;
    }

    return self;
}

+ (CDVInAppBrowserOptions *)parseOptions:(NSString *)options {
    CDVInAppBrowserOptions* obj = [[CDVInAppBrowserOptions alloc] init];

    // NOTE: this parsing does not handle quotes within values
    NSArray* pairs = [options componentsSeparatedByString:@","];

    // parse keys and values, set the properties
    for (NSString* pair in pairs) {
        NSArray* keyvalue = [pair componentsSeparatedByString:@"="];

        if ([keyvalue count] == 2) {
            NSString* key = [[keyvalue objectAtIndex:0] lowercaseString];
            NSString* value = [keyvalue objectAtIndex:1];
            NSString* value_lc = [value lowercaseString];

            BOOL isBoolean = [value_lc isEqualToString:@"yes"] || [value_lc isEqualToString:@"no"];
            NSNumberFormatter* numberFormatter = [[NSNumberFormatter alloc] init];
            [numberFormatter setAllowsFloats:YES];
            BOOL isNumber = [numberFormatter numberFromString:value_lc] != nil;

            // set the property according to the key name
            if ([obj respondsToSelector:NSSelectorFromString(key)]) {
                if (isNumber) {
                    [obj setValue:[numberFormatter numberFromString:value_lc] forKey:key];
                } else if (isBoolean) {
                    [obj setValue:[NSNumber numberWithBool:[value_lc isEqualToString:@"yes"]] forKey:key];
                } else {
                    [obj setValue:value forKey:key];
                }
            }
        }
    }

    return obj;
}

@end

@implementation CDVInAppBrowserNavigationController : UINavigationController

- (void)viewDidLoad {

    CGRect frame = [UIApplication sharedApplication].statusBarFrame;

    // simplified from: http://stackoverflow.com/a/25669695/219684

    UIToolbar* bgToolbar = [[UIToolbar alloc] initWithFrame:frame];
    bgToolbar.barStyle = UIBarStyleDefault;
    [self.view addSubview:bgToolbar];

    [super viewDidLoad];
}


#pragma mark CDVScreenOrientationDelegate

- (BOOL)shouldAutorotate {
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(shouldAutorotate)]) {
        return [self.orientationDelegate shouldAutorotate];
    }
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations {
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(supportedInterfaceOrientations)]) {
        return [self.orientationDelegate supportedInterfaceOrientations];
    }

    return 1 << UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(shouldAutorotateToInterfaceOrientation:)]) {
        return [self.orientationDelegate shouldAutorotateToInterfaceOrientation:interfaceOrientation];
    }

    return YES;
}


@end

