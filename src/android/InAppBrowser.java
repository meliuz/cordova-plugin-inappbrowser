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
package org.apache.cordova.inappbrowser;

import android.annotation.SuppressLint;
import org.apache.cordova.inappbrowser.InAppBrowserDialog;
import android.content.Context;
import android.content.Intent;
import android.content.DialogInterface;
import android.provider.Browser;
import android.content.res.Resources;
import android.content.res.AssetManager;
import android.graphics.Bitmap;
import android.graphics.Typeface;
import android.graphics.Paint;
import android.graphics.drawable.Drawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.text.InputType;
import android.util.Log;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.view.WindowManager.LayoutParams;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.webkit.CookieManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.TextView;
import android.widget.LinearLayout;
import android.widget.RelativeLayout;
import android.widget.ProgressBar;
import android.app.AlertDialog;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.Config;
import org.apache.cordova.CordovaArgs;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CordovaWebView;
import org.apache.cordova.LOG;
import org.apache.cordova.PluginManager;
import org.apache.cordova.PluginResult;
import org.json.JSONException;
import org.json.JSONObject;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.HashMap;
import java.util.StringTokenizer;
import java.io.InputStream;
import java.io.IOException;

@SuppressLint("SetJavaScriptEnabled")
public class InAppBrowser extends CordovaPlugin {

    private static final int TOUCH_SIZE = 48;
    private static final int TOOLBAR_HEIGHT = 56;
    private static final int TOOLBAR_PADDING = 6;

    private static final String NULL = "null";
    protected static final String LOG_TAG = "InAppBrowser";
    private static final String SELF = "_self";
    private static final String SYSTEM = "_system";
    private static final String BLANK = "_blank";
    private static final String EXIT_EVENT = "exit";
    private static final String ZOOM = "zoom";
    private static final String HIDDEN = "hidden";
    private static final String LOAD_START_EVENT = "loadstart";
    private static final String LOAD_STOP_EVENT = "loadstop";
    private static final String LOAD_ERROR_EVENT = "loaderror";
    private static final String CLEAR_ALL_CACHE = "clearcache";
    private static final String CLEAR_SESSION_CACHE = "clearsessioncache";
    private static final String HARDWARE_BACK_BUTTON = "hardwareback";
    private static final String REDIRECT_INTERFACE = "meliuzredirectinterface";

    private InAppBrowserDialog dialog;
    private WebView inAppWebView;
    private TextView titleView;
    private TextView cashbackView;
    private ProgressBar loadingProgressBar;
    private Button closeButton;
    private Button couponCodeButton;
    private Button backButton;
    private Button forwardButton;
    private CallbackContext callbackContext;
    private boolean meliuzRedirectInterface = false;
    private boolean showZoomControls = true;
    private boolean openWindowHidden = false;
    private boolean clearAllCache= false;
    private boolean clearSessionCache=false;
    private boolean hadwareBackButton=true;

    /**
     * Executes the request and returns PluginResult.
     *
     * @param action        The action to execute.
     * @param args          JSONArry of arguments for the plugin.
     * @param callbackId    The callback id used when calling back into JavaScript.
     * @return              A PluginResult object with a status and message.
     */
    public boolean execute(String action, CordovaArgs args, final CallbackContext callbackContext) throws JSONException {
        if (action.equals("open")) {
            this.callbackContext = callbackContext;
            final String url = args.getString(0);
            String t = args.optString(1);
            if (t == null || t.equals("") || t.equals(NULL)) {
                t = SELF;
            }
            final String target = t;
            final HashMap<String, Boolean> features = parseFeature(args.optString(2));

            Log.d(LOG_TAG, "target = " + target);

            this.cordova.getActivity().runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    String result = "";
                    // SELF
                    if (SELF.equals(target)) {
                        Log.d(LOG_TAG, "in self");
                        /* This code exists for compatibility between 3.x and 4.x versions of Cordova.
                         * Previously the Config class had a static method, isUrlWhitelisted(). That
                         * responsibility has been moved to the plugins, with an aggregating method in
                         * PluginManager.
                         */
                        Boolean shouldAllowNavigation = null;
                        if (url.startsWith("javascript:")) {
                            shouldAllowNavigation = true;
                        }
                        if (shouldAllowNavigation == null) {
                            try {
                                Method iuw = Config.class.getMethod("isUrlWhiteListed", String.class);
                                shouldAllowNavigation = (Boolean)iuw.invoke(null, url);
                            } catch (NoSuchMethodException e) {
                            } catch (IllegalAccessException e) {
                            } catch (InvocationTargetException e) {
                            }
                        }
                        if (shouldAllowNavigation == null) {
                            try {
                                Method gpm = webView.getClass().getMethod("getPluginManager");
                                PluginManager pm = (PluginManager)gpm.invoke(webView);
                                Method san = pm.getClass().getMethod("shouldAllowNavigation", String.class);
                                shouldAllowNavigation = (Boolean)san.invoke(pm, url);
                            } catch (NoSuchMethodException e) {
                            } catch (IllegalAccessException e) {
                            } catch (InvocationTargetException e) {
                            }
                        }
                        // load in webview
                        if (Boolean.TRUE.equals(shouldAllowNavigation)) {
                            Log.d(LOG_TAG, "loading in webview");
                            webView.loadUrl(url);
                        } else if (url.startsWith(WebView.SCHEME_TEL)) {
                            // Load the dialer
                            try {
                                Log.d(LOG_TAG, "loading in dialer");
                                Intent intent = new Intent(Intent.ACTION_DIAL);
                                intent.setData(Uri.parse(url));
                                cordova.getActivity().startActivity(intent);
                            } catch (android.content.ActivityNotFoundException e) {
                                LOG.e(LOG_TAG, "Error dialing " + url + ": " + e.toString());
                            }
                        } else {
                            // load in InAppBrowser
                            Log.d(LOG_TAG, "loading in InAppBrowser");
                            result = showWebPage(url, features);
                        }
                    } else if (SYSTEM.equals(target)) {
                        // SYSTEM
                        Log.d(LOG_TAG, "in system");
                        result = openExternal(url);
                    } else {
                        // BLANK - or anything else
                        Log.d(LOG_TAG, "in blank");
                        result = showWebPage(url, features);
                    }

                    PluginResult pluginResult = new PluginResult(PluginResult.Status.OK, result);
                    pluginResult.setKeepCallback(true);
                    callbackContext.sendPluginResult(pluginResult);
                }
            });
        } else if (action.equals("close")) {
            closeDialog();
        } else if (action.equals("injectScriptCode")) {
            String jsWrapper = null;
            if (args.getBoolean(1)) {
                jsWrapper = String.format("prompt(JSON.stringify([eval(%%s)]), 'gap-iab://%s')", callbackContext.getCallbackId());
            }
            injectDeferredObject(args.getString(0), jsWrapper);
        } else if (action.equals("injectScriptFile")) {
            String jsWrapper;
            if (args.getBoolean(1)) {
                jsWrapper = String.format("(function(d) { var c = d.createElement('script'); c.src = %%s; c.onload = function() { prompt('', 'gap-iab://%s'); }; d.body.appendChild(c); })(document)", callbackContext.getCallbackId());
            } else {
                jsWrapper = "(function(d) { var c = d.createElement('script'); c.src = %s; d.body.appendChild(c); })(document)";
            }
            injectDeferredObject(args.getString(0), jsWrapper);
        } else if (action.equals("injectStyleCode")) {
            String jsWrapper;
            if (args.getBoolean(1)) {
                jsWrapper = String.format("(function(d) { var c = d.createElement('style'); c.innerHTML = %%s; d.body.appendChild(c); prompt('', 'gap-iab://%s');})(document)", callbackContext.getCallbackId());
            } else {
                jsWrapper = "(function(d) { var c = d.createElement('style'); c.innerHTML = %s; d.body.appendChild(c); })(document)";
            }
            injectDeferredObject(args.getString(0), jsWrapper);
        } else if (action.equals("injectStyleFile")) {
            String jsWrapper;
            if (args.getBoolean(1)) {
                jsWrapper = String.format("(function(d) { var c = d.createElement('link'); c.rel='stylesheet'; c.type='text/css'; c.href = %%s; d.head.appendChild(c); prompt('', 'gap-iab://%s');})(document)", callbackContext.getCallbackId());
            } else {
                jsWrapper = "(function(d) { var c = d.createElement('link'); c.rel='stylesheet'; c.type='text/css'; c.href = %s; d.head.appendChild(c); })(document)";
            }
            injectDeferredObject(args.getString(0), jsWrapper);
        } else if (action.equals("show")) {
            this.cordova.getActivity().runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    dialog.show();
                }
            });
            PluginResult pluginResult = new PluginResult(PluginResult.Status.OK);
            pluginResult.setKeepCallback(true);
            this.callbackContext.sendPluginResult(pluginResult);
        } else {
            return false;
        }
        return true;
    }

    /**
     * Called when the view navigates.
     */
    @Override
    public void onReset() {
        closeDialog();
    }

    /**
     * Called by AccelBroker when listener is to be shut down.
     * Stop listener.
     */
    public void onDestroy() {
        closeDialog();
    }

    /**
     * Inject an object (script or style) into the InAppBrowser WebView.
     *
     * This is a helper method for the inject{Script|Style}{Code|File} API calls, which
     * provides a consistent method for injecting JavaScript code into the document.
     *
     * If a wrapper string is supplied, then the source string will be JSON-encoded (adding
     * quotes) and wrapped using string formatting. (The wrapper string should have a single
     * '%s' marker)
     *
     * @param source      The source object (filename or script/style text) to inject into
     *                    the document.
     * @param jsWrapper   A JavaScript string to wrap the source string in, so that the object
     *                    is properly injected, or null if the source string is JavaScript text
     *                    which should be executed directly.
     */
    private void injectDeferredObject(String source, String jsWrapper) {
        String scriptToInject;
        if (jsWrapper != null) {
            org.json.JSONArray jsonEsc = new org.json.JSONArray();
            jsonEsc.put(source);
            String jsonRepr = jsonEsc.toString();
            String jsonSourceString = jsonRepr.substring(1, jsonRepr.length()-1);
            scriptToInject = String.format(jsWrapper, jsonSourceString);
        } else {
            scriptToInject = source;
        }
        final String finalScriptToInject = scriptToInject;
        this.cordova.getActivity().runOnUiThread(new Runnable() {
            @SuppressLint("NewApi")
            @Override
            public void run() {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.KITKAT) {
                    // This action will have the side-effect of blurring the currently focused element
                    inAppWebView.loadUrl("javascript:" + finalScriptToInject);
                } else {
                    inAppWebView.evaluateJavascript(finalScriptToInject, null);
                }
            }
        });
    }

    /**
     * Put the list of features into a hash map
     *
     * @param optString
     * @return
     */
    private HashMap<String, Boolean> parseFeature(String optString) {
        if (optString.equals(NULL)) {
            return null;
        } else {
            HashMap<String, Boolean> map = new HashMap<String, Boolean>();
            StringTokenizer features = new StringTokenizer(optString, ",");
            StringTokenizer option;
            while(features.hasMoreElements()) {
                option = new StringTokenizer(features.nextToken(), "=");
                if (option.hasMoreElements()) {
                    String key = option.nextToken();
                    Boolean value = option.nextToken().equals("no") ? Boolean.FALSE : Boolean.TRUE;
                    map.put(key, value);
                }
            }
            return map;
        }
    }

    /**
     * Display a new browser with the specified URL.
     *
     * @param url           The url to load.
     * @param usePhoneGap   Load url in PhoneGap webview
     * @return              "" if ok, or error message.
     */
    public String openExternal(String url) {
        try {
            Intent intent = null;
            intent = new Intent(Intent.ACTION_VIEW);
            // Omitting the MIME type for file: URLs causes "No Activity found to handle Intent".
            // Adding the MIME type to http: URLs causes them to not be handled by the downloader.
            Uri uri = Uri.parse(url);
            if ("file".equals(uri.getScheme())) {
                intent.setDataAndType(uri, webView.getResourceApi().getMimeType(uri));
            } else {
                intent.setData(uri);
            }
            intent.putExtra(Browser.EXTRA_APPLICATION_ID, cordova.getActivity().getPackageName());
            this.cordova.getActivity().startActivity(intent);
            return "";
        } catch (android.content.ActivityNotFoundException e) {
            Log.d(LOG_TAG, "InAppBrowser: Error loading url "+url+":"+ e.toString());
            return e.toString();
        }
    }

    /**
     * Shows up the coupon code
     */
    public void couponCodeDialog() {
        new AlertDialog.Builder(cordova.getActivity())
            .setTitle("CÓDIGO DE DESCONTO")
            .setMessage(this.couponCodeButton.getContentDescription())
            // .setCancelable(true)
            .setPositiveButton(android.R.string.ok, new DialogInterface.OnClickListener() {
                public void onClick(DialogInterface dialog, int which) {
                    // continue with delete
                }
            })
            // .setNegativeButton(android.R.string.no, new DialogInterface.OnClickListener() {
            //     public void onClick(DialogInterface dialog, int which) {
            //         // do nothing
            //     }
            //  })
            // .setIcon(android.R.drawable.ic_dialog_alert)
            .show();
    }

    /**
     * Closes the dialog
     */
    public void closeDialog() {
        final WebView childView = this.inAppWebView;
        // The JS protects against multiple calls, so this should happen only when
        // closeDialog() is called by other native code.
        if (childView == null) {
            return;
        }
        this.cordova.getActivity().runOnUiThread(new Runnable() {
            @Override
            public void run() {
                childView.setWebViewClient(new WebViewClient() {
                    // NB: wait for about:blank before dismissing
                    public void onPageFinished(WebView view, String url) {
                        if (dialog != null) {
                            dialog.dismiss();
                        }
                    }
                });
                // NB: From SDK 19: "If you call methods on WebView from any thread
                // other than your app's UI thread, it can cause unexpected results."
                // http://developer.android.com/guide/webapps/migrating.html#Threads
                childView.loadUrl("about:blank");
            }
        });

        try {
            JSONObject obj = new JSONObject();
            obj.put("type", EXIT_EVENT);
            sendUpdate(obj, false);
        } catch (JSONException ex) {
            Log.d(LOG_TAG, "Should never happen");
        }
    }

    /**
     * Checks to see if it is possible to go back one page in history, then does so.
     */
    public void goBack() {
        this.inAppWebView.goBack();
    }

    /**
     * Can the web browser go back?
     * @return boolean
     */
    public boolean canGoBack() {
        return this.inAppWebView.canGoBack();
    }

    /**
     * Has the user set the hardware back button to go back
     * @return boolean
     */
    public boolean hardwareBack() {
        return hadwareBackButton;
    }

    /**
     * Checks to see if it is possible to go forward one page in history, then does so.
     */
    private void goForward() {
        this.inAppWebView.goForward();
    }

    /**
     * Navigate to the new page
     *
     * @param url to load
     */
    private void navigate(String url) {
        InputMethodManager imm = (InputMethodManager)this.cordova.getActivity().getSystemService(Context.INPUT_METHOD_SERVICE);

        if (!url.startsWith("http") && !url.startsWith("file:")) {
            this.inAppWebView.loadUrl("http://" + url);
        } else {
            this.inAppWebView.loadUrl(url);
        }
        this.inAppWebView.requestFocus();
    }


    /**
     * Should we show the zoom controls?
     *
     * @return boolean
     */
    private boolean getShowZoomControls() {
        return this.showZoomControls;
    }

    private InAppBrowser getInAppBrowser(){
        return this;
    }

    /**
     * Display a new browser with the specified URL.
     *
     * @param url           The url to load.
     * @param jsonObject
     */
    public String showWebPage(final String url, HashMap<String, Boolean> features) {
        showZoomControls = true;
        openWindowHidden = false;
        meliuzRedirectInterface = false;
        if (features != null) {
            Boolean zoom = features.get(ZOOM);
            if (zoom != null) {
                showZoomControls = zoom.booleanValue();
            }
            Boolean hidden = features.get(HIDDEN);
            if (hidden != null) {
                openWindowHidden = hidden.booleanValue();
            }
            Boolean hardwareBack = features.get(HARDWARE_BACK_BUTTON);
            if (hardwareBack != null) {
                hadwareBackButton = hardwareBack.booleanValue();
            }
            Boolean cache = features.get(CLEAR_ALL_CACHE);
            if (cache != null) {
                clearAllCache = cache.booleanValue();
            } else {
                cache = features.get(CLEAR_SESSION_CACHE);
                if (cache != null) {
                    clearSessionCache = cache.booleanValue();
                }
            }
            Boolean redirectInterface = features.get(REDIRECT_INTERFACE);
            if (redirectInterface != null) {
                meliuzRedirectInterface = redirectInterface.booleanValue();
            }
        }

        final CordovaWebView thatWebView = this.webView;
        final boolean meliuzRedirectInterface = this.meliuzRedirectInterface;

        // Create dialog in new thread
        Runnable runnable = new Runnable() {
            /**
             * Convert our DIP units to Pixels
             *
             * @return int
             */
            private int dpToPixels(int dipValue) {
                int value = (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP,
                                                            (float) dipValue,
                                                            cordova.getActivity().getResources().getDisplayMetrics()
                );

                return value;
            }

            @SuppressLint("NewApi")
            public void run() {
                // Let's create the main dialog
                dialog = new InAppBrowserDialog(cordova.getActivity(), android.R.style.Theme_NoTitleBar);
                dialog.getWindow().getAttributes().windowAnimations = android.R.style.Animation_Dialog;
                dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
                dialog.setCancelable(true);
                dialog.setInAppBroswer(getInAppBrowser());

                // Main container layout
                LinearLayout main = new LinearLayout(cordova.getActivity());
                main.setOrientation(LinearLayout.VERTICAL);

                // Main activity resources
                Resources activityRes = cordova.getActivity().getResources();

                /**
                 *
                 * ================= TOP TOOLBAR =================
                 *
                 **/
                LinearLayout topToolbar = new LinearLayout(cordova.getActivity());
                topToolbar.setOrientation(LinearLayout.HORIZONTAL);
                topToolbar.setBackgroundColor(android.graphics.Color.WHITE);
                topToolbar.setLayoutParams(new LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, this.dpToPixels(TOOLBAR_HEIGHT)));
                topToolbar.setPadding(this.dpToPixels(TOOLBAR_PADDING), this.dpToPixels(TOOLBAR_PADDING), this.dpToPixels(TOOLBAR_PADDING), this.dpToPixels(TOOLBAR_PADDING));
                topToolbar.setHorizontalGravity(Gravity.LEFT);
                topToolbar.setVerticalGravity(Gravity.CENTER);

                // Close/Done button
                closeButton = new Button(cordova.getActivity());
                LinearLayout.LayoutParams closeButtonLayoutParams = new LinearLayout.LayoutParams(this.dpToPixels(TOUCH_SIZE), this.dpToPixels(TOUCH_SIZE));
                closeButton.setLayoutParams(closeButtonLayoutParams);
                closeButton.setGravity(Gravity.LEFT);
                closeButton.setContentDescription("Fechar");
                closeButton.setId(50);
                int closeButtonResId = activityRes.getIdentifier("ic_action_remove", "drawable", cordova.getActivity().getPackageName());
                Drawable closeButtonIcon = activityRes.getDrawable(closeButtonResId);
                try {
                    // get input stream
                    InputStream ims = cordova.getActivity().getAssets().open("www/assets/images/icon-close@3x.png");
                    // load image as Drawable
                    closeButtonIcon = Drawable.createFromStream(ims, null);
                } catch (IOException e) {
                    // ...
                }
                if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.JELLY_BEAN) {
                    closeButton.setBackgroundDrawable(closeButtonIcon);
                } else {
                    closeButton.setBackground(closeButtonIcon);
                }
                closeButton.setOnClickListener(new View.OnClickListener() {
                    public void onClick(View v) {
                        closeDialog();
                    }
                });

                // Title
                titleView = new TextView(cordova.getActivity());
                LinearLayout.LayoutParams titleViewLayoutParams = new LinearLayout.LayoutParams(this.dpToPixels(0), LayoutParams.MATCH_PARENT, 1);
                titleView.setLayoutParams(titleViewLayoutParams);
                titleView.setGravity(Gravity.CENTER);
                titleView.setPadding(this.dpToPixels(TOOLBAR_PADDING), this.dpToPixels(0), this.dpToPixels(TOOLBAR_PADDING), this.dpToPixels(0));
                if (meliuzRedirectInterface) {
                    titleView.setText("CARREGANDO...");
                } else {
                    titleView.setText("");
                }
                titleView.setGravity(Gravity.CENTER);
                titleView.setTextSize(19);
                titleView.setTypeface(Typeface.createFromAsset(cordova.getActivity().getApplicationContext().getAssets(), "www/assets/fonts/source-sans/SourceSansPro-Regular.ttf"));
                titleView.setTextColor(android.graphics.Color.parseColor("#F13900"));
                titleView.setContentDescription("");
                titleView.setId(51);

                // Coupon code button
                couponCodeButton = new Button(cordova.getActivity());
                LinearLayout.LayoutParams couponCodeButtonLayoutParams = new LinearLayout.LayoutParams(this.dpToPixels(TOUCH_SIZE), this.dpToPixels(TOUCH_SIZE));
                couponCodeButton.setLayoutParams(couponCodeButtonLayoutParams);
                couponCodeButton.setGravity(Gravity.RIGHT);
                couponCodeButton.setContentDescription("");
                couponCodeButton.setId(52);
                int couponCodeButtonResId = activityRes.getIdentifier("ic_action_remove", "drawable", cordova.getActivity().getPackageName());
                Drawable couponCodeButtonIcon = activityRes.getDrawable(couponCodeButtonResId);
                try {
                    // get input stream
                    InputStream ims = cordova.getActivity().getAssets().open("www/assets/images/icon-code@3x.png");
                    // load image as Drawable
                    couponCodeButtonIcon = Drawable.createFromStream(ims, null);
                } catch (IOException e) {
                    // ...
                }
                if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.JELLY_BEAN) {
                    couponCodeButton.setBackgroundDrawable(couponCodeButtonIcon);
                } else {
                    couponCodeButton.setBackground(couponCodeButtonIcon);
                }
                couponCodeButton.setOnClickListener(new View.OnClickListener() {
                    public void onClick(View v) {
                        couponCodeDialog();
                    }
                });
                couponCodeButton.setEnabled(false);
                couponCodeButton.setAlpha(0.0f);

                // Add the views to our topToolbar
                topToolbar.addView(closeButton);
                topToolbar.addView(titleView);
                topToolbar.addView(couponCodeButton);

                /**
                 *
                 * ================= BOTTOM TOOLBAR =================
                 *
                 **/
                LinearLayout bottomToolbar = new LinearLayout(cordova.getActivity());
                bottomToolbar.setOrientation(LinearLayout.HORIZONTAL);
                bottomToolbar.setBackgroundColor(android.graphics.Color.WHITE);
                bottomToolbar.setLayoutParams(new LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, this.dpToPixels(TOOLBAR_HEIGHT)));
                bottomToolbar.setPadding(this.dpToPixels(TOOLBAR_PADDING), this.dpToPixels(TOOLBAR_PADDING), this.dpToPixels(TOOLBAR_PADDING), this.dpToPixels(TOOLBAR_PADDING));
                bottomToolbar.setHorizontalGravity(Gravity.LEFT);
                bottomToolbar.setVerticalGravity(Gravity.CENTER);

                // Action Button Container layout
                RelativeLayout actionButtonContainer = new RelativeLayout(cordova.getActivity());
                RelativeLayout.LayoutParams actionButtonContainerLayoutParams = new RelativeLayout.LayoutParams(this.dpToPixels(2 * TOUCH_SIZE), LayoutParams.MATCH_PARENT);
                actionButtonContainerLayoutParams.addRule(RelativeLayout.ALIGN_PARENT_RIGHT);
                actionButtonContainer.setLayoutParams(actionButtonContainerLayoutParams);
                actionButtonContainer.setGravity(Gravity.RIGHT);
                actionButtonContainer.setId(1);

                // Back button
                backButton = new Button(cordova.getActivity());
                RelativeLayout.LayoutParams backButtonLayoutParams = new RelativeLayout.LayoutParams(this.dpToPixels(TOUCH_SIZE), LayoutParams.MATCH_PARENT);
                backButtonLayoutParams.addRule(RelativeLayout.ALIGN_RIGHT);
                backButton.setLayoutParams(backButtonLayoutParams);
                backButton.setContentDescription("Voltar");
                backButton.setId(2);
                int backButtonResId = activityRes.getIdentifier("ic_action_previous_item", "drawable", cordova.getActivity().getPackageName());
                Drawable backButtonIcon = activityRes.getDrawable(backButtonResId);
                try {
                    // get input stream
                    InputStream ims = cordova.getActivity().getAssets().open("www/assets/images/icon-back@3x.png");
                    // load image as Drawable
                    backButtonIcon = Drawable.createFromStream(ims, null);
                } catch (IOException e) {
                    // ...
                }
                if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.JELLY_BEAN) {
                    backButton.setBackgroundDrawable(backButtonIcon);
                } else {
                    backButton.setBackground(backButtonIcon);
                }
                backButton.setOnClickListener(new View.OnClickListener() {
                    public void onClick(View v) {
                        goBack();
                    }
                });
                backButton.setEnabled(false);
                backButton.setAlpha(0.3f);

                // Forward button
                forwardButton = new Button(cordova.getActivity());
                RelativeLayout.LayoutParams forwardButtonLayoutParams = new RelativeLayout.LayoutParams(this.dpToPixels(TOUCH_SIZE), LayoutParams.MATCH_PARENT);
                forwardButtonLayoutParams.addRule(RelativeLayout.RIGHT_OF, backButton.getId());
                forwardButton.setLayoutParams(forwardButtonLayoutParams);
                forwardButton.setContentDescription("Avançar");
                forwardButton.setId(3);
                int forwardButtonResId = activityRes.getIdentifier("ic_action_next_item", "drawable", cordova.getActivity().getPackageName());
                Drawable forwardButtonIcon = activityRes.getDrawable(forwardButtonResId);
                try {
                    // get input stream
                    InputStream ims = cordova.getActivity().getAssets().open("www/assets/images/icon-forward@3x.png");
                    // load image as Drawable
                    forwardButtonIcon = Drawable.createFromStream(ims, null);
                } catch (IOException e) {
                    // ...
                }
                if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.JELLY_BEAN) {
                    forwardButton.setBackgroundDrawable(forwardButtonIcon);
                } else {
                    forwardButton.setBackground(forwardButtonIcon);
                }
                forwardButton.setOnClickListener(new View.OnClickListener() {
                    public void onClick(View v) {
                        goForward();
                    }
                });
                forwardButton.setEnabled(false);
                forwardButton.setAlpha(0.3f);

                // CashbackView
                cashbackView = new TextView(cordova.getActivity());
                LinearLayout.LayoutParams cashbackViewLayoutParams = new LinearLayout.LayoutParams(this.dpToPixels(0), LayoutParams.MATCH_PARENT, 1);
                cashbackView.setLayoutParams(cashbackViewLayoutParams);
                cashbackView.setPadding(this.dpToPixels(TOOLBAR_PADDING), this.dpToPixels(0), this.dpToPixels(TOOLBAR_PADDING), this.dpToPixels(0));
                cashbackView.setText("");
                cashbackView.setGravity(Gravity.LEFT | Gravity.CENTER);
                cashbackView.setTextSize(19);
                cashbackView.setTypeface(Typeface.createFromAsset(cordova.getActivity().getApplicationContext().getAssets(), "www/assets/fonts/source-sans/SourceSansPro-Regular.ttf"));
                cashbackView.setTextColor(android.graphics.Color.parseColor("#FF4D4D"));
                cashbackView.setContentDescription("");
                cashbackView.setId(99);

                // LoadingProgressBar
                loadingProgressBar = new ProgressBar(cordova.getActivity(), null, android.R.attr.progressBarStyleSmall);
                RelativeLayout.LayoutParams loadingProgressBarLayoutParams = new RelativeLayout.LayoutParams(this.dpToPixels(TOUCH_SIZE) / 2, this.dpToPixels(TOUCH_SIZE) / 2);
                loadingProgressBarLayoutParams.addRule(RelativeLayout.ALIGN_PARENT_RIGHT);
                loadingProgressBar.setLayoutParams(loadingProgressBarLayoutParams);
                loadingProgressBar.setIndeterminate(true);
                loadingProgressBar.setId(999);

                // Add the back and forward buttons to our action button container layout
                actionButtonContainer.addView(forwardButton);
                actionButtonContainer.addView(backButton);

                // Add the views to our bottomToolbar
                bottomToolbar.addView(cashbackView);
                bottomToolbar.addView(loadingProgressBar);
                bottomToolbar.addView(actionButtonContainer);

                /**
                 *
                 * ================= WEBVIEW =================
                 *
                 **/
                inAppWebView = new WebView(cordova.getActivity());
                inAppWebView.addJavascriptInterface(new AndroidJavaScriptInterface(titleView, cashbackView, couponCodeButton), "androidJSInterface");
                inAppWebView.setLayoutParams(new LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, this.dpToPixels(0), 1));
                inAppWebView.setWebChromeClient(new InAppChromeClient(thatWebView));
                WebViewClient client = new InAppBrowserClient(thatWebView, meliuzRedirectInterface, loadingProgressBar);
                inAppWebView.setWebViewClient(client);
                WebSettings settings = inAppWebView.getSettings();
                settings.setJavaScriptEnabled(true);
                settings.setJavaScriptCanOpenWindowsAutomatically(true);
                settings.setBuiltInZoomControls(getShowZoomControls());
                settings.setPluginState(android.webkit.WebSettings.PluginState.ON);

                // Toggle whether this is enabled or not!
                Bundle appSettings = cordova.getActivity().getIntent().getExtras();
                boolean enableDatabase = appSettings == null ? true : appSettings.getBoolean("InAppBrowserStorageEnabled", true);
                if (enableDatabase) {
                    String databasePath = cordova.getActivity().getApplicationContext().getDir("inAppBrowserDB", Context.MODE_PRIVATE).getPath();
                    settings.setDatabasePath(databasePath);
                    settings.setDatabaseEnabled(true);
                }
                settings.setDomStorageEnabled(true);

                if (clearAllCache) {
                    CookieManager.getInstance().removeAllCookie();
                } else if (clearSessionCache) {
                    CookieManager.getInstance().removeSessionCookie();
                }

                inAppWebView.loadUrl(url);
                inAppWebView.setId(6);
                inAppWebView.getSettings().setLoadWithOverviewMode(true);
                inAppWebView.getSettings().setUseWideViewPort(true);
                inAppWebView.requestFocus();
                inAppWebView.requestFocusFromTouch();

                // Add our topToolbar to our main view/layout
                main.addView(topToolbar);
                // Add our webview to our main view/layout
                main.addView(inAppWebView);
                // Add our bottomToolbar to our main view/layout
                main.addView(bottomToolbar);

                WindowManager.LayoutParams lp = new WindowManager.LayoutParams();
                lp.copyFrom(dialog.getWindow().getAttributes());
                lp.width = WindowManager.LayoutParams.MATCH_PARENT;
                lp.height = WindowManager.LayoutParams.MATCH_PARENT;

                dialog.setContentView(main);
                dialog.show();
                dialog.getWindow().setAttributes(lp);
                // the goal of openhidden is to load the url and not display it
                // Show() needs to be called to cause the URL to be loaded
                if (openWindowHidden) {
                    dialog.hide();
                }
            }
        };
        this.cordova.getActivity().runOnUiThread(runnable);
        return "";
    }

    /**
     * Create a new plugin success result and send it back to JavaScript
     *
     * @param obj a JSONObject contain event payload information
     */
    private void sendUpdate(JSONObject obj, boolean keepCallback) {
        sendUpdate(obj, keepCallback, PluginResult.Status.OK);
    }

    /**
     * Create a new plugin result and send it back to JavaScript
     *
     * @param obj a JSONObject contain event payload information
     * @param status the status code to return to the JavaScript environment
     */
    private void sendUpdate(JSONObject obj, boolean keepCallback, PluginResult.Status status) {
        if (callbackContext != null) {
            PluginResult result = new PluginResult(status, obj);
            result.setKeepCallback(keepCallback);
            callbackContext.sendPluginResult(result);
            if (!keepCallback) {
                callbackContext = null;
            }
        }
    }

    /* An instance of this class will be registered as a JavaScript interface */
    public class AndroidJavaScriptInterface {
        private TextView titleView;
        private TextView cashbackView;
        private Button couponCodeButton;

        /**
         * Constructor.
         *
         * @param TextView title
         */
        public AndroidJavaScriptInterface(TextView titleView, TextView cashbackView, Button couponCodeButton) {
            this.titleView = titleView;
            this.cashbackView = cashbackView;
            this.couponCodeButton = couponCodeButton;
        }

        @JavascriptInterface
        public void updateInterface(final String titleString, final String cashbackString, final String couponCodeString, final String mobileFriendlyString) {
            final TextView titleView = this.titleView;
            final TextView cashbackView = this.cashbackView;
            final Button couponCodeButton = this.couponCodeButton;

            // when updating UI, needs to run on UI Thread
            // http://stackoverflow.com/a/17230947/165233
            cordova.getActivity().runOnUiThread(new Runnable() {
                public void run() {
                    titleView.setText(titleString.toUpperCase());
                    titleView.setContentDescription(titleString);

                    cashbackView.setText(cashbackString);
                    cashbackView.setContentDescription(cashbackString);
                    if (mobileFriendlyString.equals("false")) {
                        cashbackView.setTextColor(android.graphics.Color.parseColor("#999999"));
                        cashbackView.setPaintFlags(cashbackView.getPaintFlags() | Paint.STRIKE_THRU_TEXT_FLAG);
                    }

                    if (!couponCodeString.equals("")) {
                        couponCodeButton.setEnabled(true);
                        couponCodeButton.setAlpha(1.0f);
                        couponCodeButton.setContentDescription(couponCodeString);
                    }
                }
            });
        }

        @JavascriptInterface
        public void updateTitle(final String titleString) {
            final TextView titleView = this.titleView;

            // when updating UI, needs to run on UI Thread
            // http://stackoverflow.com/a/17230947/165233
            cordova.getActivity().runOnUiThread(new Runnable() {
                public void run() {
                    titleView.setText(titleString.toUpperCase());
                    titleView.setContentDescription(titleString);
                }
            });
        }
    }

    /**
     * The webview client receives notifications about appView
     */
    public class InAppBrowserClient extends WebViewClient {
        CordovaWebView webView;
        boolean checkedVars;
        boolean meliuzRedirectInterface;
        ProgressBar loadingProgressBar;

        /**
         * Constructor.
         *
         * @param mContext
         */
        public InAppBrowserClient(CordovaWebView webView, boolean meliuzRedirectInterface, ProgressBar loadingProgressBar) {
            this.webView = webView;
            this.checkedVars = false;
            this.meliuzRedirectInterface = meliuzRedirectInterface;
            this.loadingProgressBar = loadingProgressBar;
        }

        /**
         * Notify the host application that a page has started loading.
         *
         * @param view          The webview initiating the callback.
         * @param url           The url of the page.
         */
        @Override
        public void onPageStarted(WebView view, String url,  Bitmap favicon) {
            this.loadingProgressBar.setVisibility(ProgressBar.VISIBLE);

            super.onPageStarted(view, url, favicon);
            String newloc = "";
            if (url.startsWith("http:") || url.startsWith("https:") || url.startsWith("file:")) {
                newloc = url;
            } else if (url.startsWith(WebView.SCHEME_TEL)) {
                // If dialing phone (tel:5551212)
                try {
                    Intent intent = new Intent(Intent.ACTION_DIAL);
                    intent.setData(Uri.parse(url));
                    cordova.getActivity().startActivity(intent);
                } catch (android.content.ActivityNotFoundException e) {
                    LOG.e(LOG_TAG, "Error dialing " + url + ": " + e.toString());
                }
            } else if (url.startsWith("geo:") || url.startsWith(WebView.SCHEME_MAILTO) || url.startsWith("market:")) {
                try {
                    Intent intent = new Intent(Intent.ACTION_VIEW);
                    intent.setData(Uri.parse(url));
                    cordova.getActivity().startActivity(intent);
                } catch (android.content.ActivityNotFoundException e) {
                    LOG.e(LOG_TAG, "Error with " + url + ": " + e.toString());
                }
            } else if (url.startsWith("sms:")) {
                // If sms:5551212?body=This is the message
                try {
                    Intent intent = new Intent(Intent.ACTION_VIEW);

                    // Get address
                    String address = null;
                    int parmIndex = url.indexOf('?');
                    if (parmIndex == -1) {
                        address = url.substring(4);
                    } else {
                        address = url.substring(4, parmIndex);

                        // If body, then set sms body
                        Uri uri = Uri.parse(url);
                        String query = uri.getQuery();
                        if (query != null) {
                            if (query.startsWith("body=")) {
                                intent.putExtra("sms_body", query.substring(5));
                            }
                        }
                    }
                    intent.setData(Uri.parse("sms:" + address));
                    intent.putExtra("address", address);
                    intent.setType("vnd.android-dir/mms-sms");
                    cordova.getActivity().startActivity(intent);
                } catch (android.content.ActivityNotFoundException e) {
                    LOG.e(LOG_TAG, "Error sending sms " + url + ":" + e.toString());
                }
            } else {
                newloc = "http://" + url;
            }

            try {
                JSONObject obj = new JSONObject();
                obj.put("type", LOAD_START_EVENT);
                obj.put("url", newloc);

                sendUpdate(obj, true);
            } catch (JSONException ex) {
                Log.d(LOG_TAG, "Should never happen");
            }
        }

        public void onPageFinished(WebView view, String url) {
            this.loadingProgressBar.setVisibility(ProgressBar.GONE);

            if (inAppWebView.canGoBack()) {
                backButton.setEnabled(true);
                backButton.setAlpha(1.0f);
            } else {
                backButton.setEnabled(false);
                backButton.setAlpha(0.3f);
            }
            if (inAppWebView.canGoForward()) {
                forwardButton.setEnabled(true);
                forwardButton.setAlpha(1.0f);
            } else {
                forwardButton.setEnabled(false);
                forwardButton.setAlpha(0.3f);
            }

            super.onPageFinished(view, url);

            try {
                JSONObject obj = new JSONObject();
                obj.put("type", LOAD_STOP_EVENT);
                obj.put("url", url);

                sendUpdate(obj, true);
            } catch (JSONException ex) {
                Log.d(LOG_TAG, "Should never happen");
            }

            if (!this.checkedVars && this.meliuzRedirectInterface) {
                // set checkdVars, clear history, update interface and redirect user
                this.checkedVars = true;
                view.loadUrl("javascript: window.androidJSInterface.updateInterface(window.meliuz.storeTitle, window.meliuz.cashbackString, window.meliuz.couponCode, window.meliuz.mobileFriendly);");
                view.clearHistory();
            } else if (!this.meliuzRedirectInterface) {
                view.loadUrl("javascript: window.androidJSInterface.updateTitle(window.document.title);");
            }
        }

        public void onReceivedError(WebView view, int errorCode, String description, final String failingUrl) {
            this.loadingProgressBar.setVisibility(ProgressBar.GONE);

            super.onReceivedError(view, errorCode, description, failingUrl);

            new AlertDialog.Builder(cordova.getActivity())
                .setTitle("Deu ruim...")
                .setMessage("Houve algum problema ao carregar esta página. O que você quer fazer?")
                .setPositiveButton("Tentar denovo", new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface dialog, int which) {
                        inAppWebView.loadUrl(failingUrl);
                    }
                })
                .setNegativeButton("Fechar", new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface dialog, int which) {
                        closeDialog();
                    }
                })
                .show();

            try {
                JSONObject obj = new JSONObject();
                obj.put("type", LOAD_ERROR_EVENT);
                obj.put("url", failingUrl);
                obj.put("code", errorCode);
                obj.put("message", description);

                sendUpdate(obj, true, PluginResult.Status.ERROR);
            } catch (JSONException ex) {
                Log.d(LOG_TAG, "Should never happen");
            }
        }
    }
}
