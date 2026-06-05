package com.astrbot.astrbot_android;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.Toast;

import java.util.HashMap;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.fragment.app.FragmentActivity;
import androidx.fragment.app.FragmentManager;

import io.flutter.embedding.android.FlutterFragment;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngineCache;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugins.GeneratedPluginRegistrant;

public class MainActivity extends FragmentActivity {
    FlutterFragment flutterFragment;
    private static final String TAG_FLUTTER_FRAGMENT = "flutter_fragment";
    Context mContext;
    FragmentManager fragmentManager = getSupportFragmentManager();

    /* ── 文件选择器 ── */
    private static final int FILE_CHOOSER_REQUEST_CODE = 1;
    private ValueCallback<Uri[]> filePathCallback;

    /* ── 双击返回退出 ── */
    private boolean doubleBackToExitPressedOnce = false;
    private static final int DOUBLE_BACK_INTERVAL = 2000;

    /* ── 覆盖层 WebView ── */
    private HashMap<String, WebView> tabWebViews = new HashMap<>();
    private String activeTabTitle = null;
    private int navBarHeightPx = 0;         // 由 Flutter 传入的底部导航栏高度
    private int statusBarHeightPx = 0;        // 由 Flutter 传入的状态栏高度
    private String lastNapCatToken = null;    // 由 Flutter 传入的 NapCat WebUI Token
    private ValueCallback<Uri[]> overlayFilePathCallback;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        mContext = this;
        setContentView(com.astrbot.astrbot_android.R.layout.my_activity_layout);

        flutterFragment = (FlutterFragment) fragmentManager.findFragmentByTag(TAG_FLUTTER_FRAGMENT);
        FlutterEngine flutterEngine = new FlutterEngine(this, null, false);
        flutterEngine.getDartExecutor().executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault());

        /* AstrBot 通道 */
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), "astrbot_channel")
            .setMethodCallHandler((call, result) -> {
                if ("lib_path".equals(call.method)) {
                    result.success(mContext.getApplicationContext().getApplicationInfo().nativeLibraryDir);
                } else {
                    result.notImplemented();
                }
            });

        /* 原生 WebView 通道 */
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), "astrbot_native_webview")
            .setMethodCallHandler((call, result) -> {
                switch (call.method) {
                    case "openMainView": {
                        // 主面板 → 叠加式 WebView
                        String url = call.argument("url");
                        String title = call.argument("title");
                        Integer navH = call.argument("navBarHeight");
                        Integer statusH = call.argument("statusBarHeight");
                        if (navH != null) navBarHeightPx = navH;
                        if (statusH != null) statusBarHeightPx = statusH;
                        showOverlayWebView(url, title);
                        result.success(true);
                        break;
                    }
                    case "clearCache": {
                        for (WebView twv : tabWebViews.values()) {
                            if (twv != null) {
                                twv.clearCache(true);
                            }
                        }
                        result.success(true);
                        break;
                    }
                    case "closeWebView": {
                        String title = (String) call.arguments();
                        WebView twv = tabWebViews.remove(title);
                        if (twv != null) {
                            ViewGroup parent = (ViewGroup) twv.getParent();
                            if (parent != null) parent.removeView(twv);
                            twv.destroy();
                        }
                        result.success(true);
                        break;
                    }
                    case "setNapCatToken": {
                        String token = (String) call.arguments();
                        if (token != null) lastNapCatToken = token;
                        result.success(true);
                        break;
                    }
                    case "hideWebView": {
                        hideOverlayWebView();
                        result.success(true);
                        break;
                    }
                    case "navigateWebView": {
                        String url = call.argument("url");
                        WebView wv = tabWebViews.get(activeTabTitle);
                        if (wv != null && url != null)
                            wv.loadUrl(url);
                        result.success(true);
                        break;
                    }
                    default:
                        result.notImplemented();
                }
            });

        GeneratedPluginRegistrant.registerWith(flutterEngine);
        FlutterEngineCache.getInstance().put("my_engine_id", flutterEngine);
        if (flutterFragment == null) {
            flutterFragment = FlutterFragment.withCachedEngine("my_engine_id").build();
        }
        fragmentManager
                .beginTransaction()
                .add(com.astrbot.astrbot_android.R.id.fl_container, flutterFragment, TAG_FLUTTER_FRAGMENT)
                .commit();
    }


    /* =====================================================
     * 覆盖层 WebView 管理
     * ===================================================== */

    @SuppressLint("SetJavaScriptEnabled")
    private void hideOverlayWebView() {
        if (activeTabTitle != null) {
            WebView wv = tabWebViews.get(activeTabTitle);
            if (wv != null) wv.setVisibility(View.GONE);
        }
    }

    private void showOverlayWebView(String url, String title) {
        FrameLayout container = findViewById(com.astrbot.astrbot_android.R.id.fl_container);
        if (container == null) return;

        // 先隐藏所有 WebView
        for (WebView wv : tabWebViews.values()) {
            if (wv != null) wv.setVisibility(View.GONE);
        }

        // 获取或创建当前 tab 的 WebView
        WebView wv = tabWebViews.get(title);
        if (wv == null) {
            wv = new WebView(this);

            // 给 WebView 独立硬件层
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                wv.setLayerType(View.LAYER_TYPE_HARDWARE, null);
            }

            // 隐藏原生滚动条
            wv.setVerticalScrollBarEnabled(false);
            wv.setHorizontalScrollBarEnabled(false);
            wv.setScrollBarStyle(View.SCROLLBARS_OUTSIDE_OVERLAY);
            wv.setOverScrollMode(View.OVER_SCROLL_NEVER);

            // 基础设置
            WebSettings s = wv.getSettings();
            s.setJavaScriptEnabled(true);
            s.setDomStorageEnabled(true);
            s.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
            s.setAllowFileAccess(true);
            s.setAllowContentAccess(true);
            s.setBuiltInZoomControls(false);
            s.setDisplayZoomControls(false);
            s.setLoadWithOverviewMode(true);
            s.setUseWideViewPort(true);
            s.setCacheMode(WebSettings.LOAD_DEFAULT);

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT)
                WebView.setWebContentsDebuggingEnabled(true);

            // WebViewClient
            wv.setWebViewClient(new WebViewClient() {
                @Override
                public void onPageFinished(WebView view, String url) {
                    disableZoom(view);
                    // NapCat 登录页自动填充 token
                    if (url.contains("6099/webui") && lastNapCatToken != null && !lastNapCatToken.isEmpty()) {
                        final String safeToken = lastNapCatToken.replace("'", "\\'");
                        view.evaluateJavascript(
                            "(function(){" +
                            "var inp=document.querySelector('input[placeholder*=\\\"请输入token\\\"]');" +
                            "if(inp&&!inp.value){" +
                            "inp.value='" + safeToken + "';" +
                            "inp.dispatchEvent(new Event('input',{bubbles:true}));" +
                            "var btn=document.querySelector('button')||document.querySelector('[type=submit]');" +
                            "if(btn)setTimeout(function(){btn.click()},300)}})()", null);
                    }
                }
                @Override
                public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                    String url = request.getUrl().toString();
                    if (url == null) return false;
                    try {
                        java.net.URI uri = java.net.URI.create(url);
                        String host = uri.getHost();
                        if (host != null) {
                            String hl = host.toLowerCase();
                            // 本地链接在 WebView 内打开
                            if (hl.equals("localhost") || hl.equals("127.0.0.1")
                                || hl.equals("0.0.0.0") || hl.startsWith("192.168.")
                                || hl.startsWith("10.") || hl.startsWith("172.")) {
                                return false;
                            }
                        }
                        // 外部链接在系统浏览器打开
                        Intent browserIntent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
                        startActivity(browserIntent);
                        return true;
                    } catch (Exception e) {
                        return false;
                    }
                }
            });

            // WebChromeClient — 文件选择
            wv.setWebChromeClient(new WebChromeClient() {
                @Override
                public boolean onShowFileChooser(WebView view,
                        ValueCallback<Uri[]> filePathCallback,
                        FileChooserParams fileChooserParams) {
                    overlayFilePathCallback = filePathCallback;
                    Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
                    intent.addCategory(Intent.CATEGORY_OPENABLE);
                    intent.setType("*/*");
                    intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
                    startActivityForResult(Intent.createChooser(intent, "选择文件"),
                            FILE_CHOOSER_REQUEST_CODE);
                    return true;
                }
            });

            // 添加 WebView 到容器，保留状态栏和底部导航栏区域
            FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT);
            lp.topMargin = statusBarHeightPx > 0 ? statusBarHeightPx : 0;
            lp.bottomMargin = navBarHeightPx > 0 ? navBarHeightPx : 0;
            container.addView(wv, lp);

            // 首次创建，加载 URL
            wv.loadUrl(url);
            tabWebViews.put(title, wv);
        } else {
            // 已有 WebView，更新 margin
            ViewGroup.MarginLayoutParams mlp =
                    (ViewGroup.MarginLayoutParams) wv.getLayoutParams();
            int newTop = statusBarHeightPx > 0 ? statusBarHeightPx : 0;
            int newBottom = navBarHeightPx > 0 ? navBarHeightPx : 0;
            if (mlp.topMargin != newTop || mlp.bottomMargin != newBottom) {
                mlp.topMargin = newTop;
                mlp.bottomMargin = newBottom;
                wv.requestLayout();
            }
        }

        wv.setVisibility(View.VISIBLE);
        activeTabTitle = title;
    }

    private void disableZoom(WebView view) {
        view.evaluateJavascript(
            "(function(){" +
            "var m=document.querySelector('meta[name=viewport]');" +
            "if(m)m.content='width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no';" +
            "else{" +
            "m=document.createElement('meta');m.name='viewport';" +
            "m.content='width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no';" +
            "document.head.appendChild(m)}})()", null);
    }

    /* =====================================================
     * 返回键 / Activity 结果
     * ===================================================== */

    @Override
    public void onBackPressed() {
        // 先给覆盖层 WebView 返回机会
        WebView wv = tabWebViews.get(activeTabTitle);
        if (wv != null && wv.canGoBack()) {
            wv.goBack();
            return;
        }

        // 双击返回退出
        if (doubleBackToExitPressedOnce) {
            moveTaskToBack(true);
            return;
        }
        this.doubleBackToExitPressedOnce = true;
        Toast.makeText(this, "再按一次返回桌面", Toast.LENGTH_SHORT).show();
        new Handler().postDelayed(() -> doubleBackToExitPressedOnce = false, DOUBLE_BACK_INTERVAL);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, @Nullable Intent data) {
        super.onActivityResult(requestCode, resultCode, data);

        // 覆盖层 WebView 文件选择
        if (requestCode == FILE_CHOOSER_REQUEST_CODE && overlayFilePathCallback != null) {
            Uri[] results = null;
            if (resultCode == Activity.RESULT_OK && data != null) {
                String dataStr = data.getDataString();
                if (dataStr != null) {
                    results = new Uri[]{Uri.parse(dataStr)};
                } else if (data.getClipData() != null) {
                    int cnt = data.getClipData().getItemCount();
                    results = new Uri[cnt];
                    for (int i = 0; i < cnt; i++)
                        results[i] = data.getClipData().getItemAt(i).getUri();
                }
            }
            overlayFilePathCallback.onReceiveValue(results);
            overlayFilePathCallback = null;
        }

        flutterFragment.onActivityResult(requestCode, resultCode, data);
    }

    /* =====================================================
     * 生命周期转发
     * ===================================================== */

    @Override
    public void onPostResume() {
        super.onPostResume();
        flutterFragment.onPostResume();
    }

    @Override
    protected void onNewIntent(@NonNull Intent intent) {
        super.onNewIntent(intent);
        flutterFragment.onNewIntent(intent);
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions,
                                           @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        flutterFragment.onRequestPermissionsResult(requestCode, permissions, grantResults);
    }

    @Override
    public void onUserLeaveHint() {
        flutterFragment.onUserLeaveHint();
    }

    @Override
    public void onTrimMemory(int level) {
        super.onTrimMemory(level);
        flutterFragment.onTrimMemory(level);
    }

    @Override
    protected void onDestroy() {
        for (WebView twv : tabWebViews.values()) {
            if (twv != null) twv.destroy();
        }
        tabWebViews.clear();
        super.onDestroy();
    }
}
