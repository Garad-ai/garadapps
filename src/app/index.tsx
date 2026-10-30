import { useLocalSearchParams } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import { StatusBar } from 'expo-status-bar';
import * as WebBrowser from 'expo-web-browser';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, AppState, BackHandler, Linking, Platform, StyleSheet, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { WebView as RNWebView, WebViewMessageEvent, WebViewNavigation } from 'react-native-webview';
import type { FileDownloadEvent, ShouldStartLoadRequest } from 'react-native-webview/lib/WebViewTypes';

import { AppMenu } from '@/components/AppMenu';
import { Banner } from '@/components/Banner';
import { BlockingScreen } from '@/components/BlockingScreen';
import { BRIDGE_SCRIPT, copyText, saveDownload, speak, stopSpeaking } from '@/lib/bridge';
import { APP_USER_AGENT, isSiteUrl, START_URL } from '@/lib/config';
import { APP_VERSION, AppConfig, fetchAppConfig, updateStatus, updateUrl } from '@/lib/remoteConfig';
import { STRINGS } from '@/lib/strings';
import { useIsDark, usePalette } from '@/lib/theme';

// react-native-webview 14 types default the extra-props parameter to `undefined`, which
// intersects every prop to `never` under current TypeScript; `object` keeps the real props.
const WebView = RNWebView as unknown as typeof RNWebView<object>;
type WebViewHandle = RNWebView<object>;

function withVoice(url: string): string {
  return `${url}${url.includes('?') ? '&' : '?'}voice=1`;
}

/** Opens a link from the app menu: site pages in the app, the rest outside it. */
function openExternally(url: string): void {
  if (/^https?:/i.test(url) && !/^https:\/\/wa\.me\//i.test(url)) void WebBrowser.openBrowserAsync(url);
  else void Linking.openURL(url).catch(() => undefined);
}

/**
 * The Garad AI app: the garad.ai web app in a native shell, so the app has exactly
 * the same design, account, data and AI features as the website. The admin controls
 * updates, maintenance, an announcement and the menu links (Settings › Mobile App).
 */
export default function GaradApp() {
  const c = usePalette();
  const deviceDark = useIsDark();
  const { voice } = useLocalSearchParams<{ voice?: string }>();
  // The website reports its own theme (it can differ from the device setting); see
  // Garad_ai/frontend/src/core/appShell.ts.
  const [pageTheme, setPageTheme] = useState<{ background: string; dark: boolean } | null>(null);
  const background = pageTheme?.background ?? c.background;
  const isDark = pageTheme?.dark ?? deviceDark;
  const webView = useRef<WebViewHandle>(null);
  const [uri] = useState(voice ? withVoice(START_URL) : START_URL);
  const firstVoiceRequest = useRef(voice);
  const [canGoBack, setCanGoBack] = useState(false);
  const [progress, setProgress] = useState(0);
  const [failed, setFailed] = useState(false);
  const [config, setConfig] = useState<AppConfig | null>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const [updateNote, setUpdateNote] = useState<string | null>(null);
  const [dismissed, setDismissed] = useState<{ update?: boolean; announcement?: string }>({});

  const loadConfig = useCallback(async () => {
    const next = await fetchAppConfig();
    if (next) setConfig(next);
    return next;
  }, []);

  // Read the admin's app settings on start and whenever the app comes back to the front.
  useEffect(() => {
    void loadConfig();
    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') void loadConfig();
    });
    return () => subscription.remove();
  }, [loadConfig]);

  // The "Talk to Garad" shortcut while the app is already open (the first one is in `uri`).
  useEffect(() => {
    if (!voice || voice === firstVoiceRequest.current) return;
    webView.current?.injectJavaScript(`window.location.href = ${JSON.stringify(withVoice(START_URL))}; true;`);
  }, [voice]);

  // Hide the splash screen after the first page load, or after a few seconds at most.
  useEffect(() => {
    const timer = setTimeout(() => SplashScreen.hideAsync(), 8000);
    return () => clearTimeout(timer);
  }, []);

  // Android back button: close the menu, then go back inside the website, then leave.
  useEffect(() => {
    if (Platform.OS !== 'android') return;
    const subscription = BackHandler.addEventListener('hardwareBackPress', () => {
      if (menuOpen) {
        setMenuOpen(false);
        return true;
      }
      if (!canGoBack) return false;
      webView.current?.goBack();
      return true;
    });
    return () => subscription.remove();
  }, [canGoBack, menuOpen]);

  const onNavigationStateChange = (state: WebViewNavigation) => setCanGoBack(state.canGoBack);

  const onShouldStartLoadWithRequest = useCallback((request: ShouldStartLoadRequest) => {
    const { url } = request;
    if (url.startsWith('about:') || url.startsWith('blob:') || url.startsWith('data:')) return true;
    // Embedded frames (videos, maps, payment widgets) load inside the page.
    if (Platform.OS === 'ios' && request.isTopFrame === false) return true;
    if (isSiteUrl(url)) return true;

    openExternally(url);
    return false;
  }, []);

  const onMessage = useCallback((event: WebViewMessageEvent) => {
    let message: Record<string, unknown>;
    try {
      message = JSON.parse(event.nativeEvent.data);
    } catch {
      return; // Not a message from the Chat Pro app shell or the download bridge.
    }
    if (message.type === 'theme' && typeof message.background === 'string') {
      setPageTheme({ background: message.background, dark: message.dark === true });
    } else if (message.type === 'openAppMenu') {
      setUpdateNote(null);
      setMenuOpen(true);
    } else if (message.type === 'copy' && typeof message.text === 'string') {
      void copyText(message.text);
    } else if (message.type === 'download' && typeof message.base64 === 'string') {
      saveDownload(
        typeof message.name === 'string' ? message.name : 'download',
        typeof message.mime === 'string' ? message.mime : 'application/octet-stream',
        message.base64
      ).catch(() => Alert.alert(STRINGS.downloadFailed));
    } else if (message.type === 'speak' && typeof message.text === 'string') {
      speak(
        message.text,
        {
          language: typeof message.lang === 'string' ? message.lang : undefined,
          rate: typeof message.rate === 'number' ? message.rate : undefined,
        },
        (speechEvent) =>
          webView.current?.injectJavaScript(`window.__garadSpeech && window.__garadSpeech('${speechEvent}'); true;`)
      );
    } else if (message.type === 'speakStop') {
      stopSpeaking();
    } else if (message.type === 'downloadError') {
      if (typeof message.url === 'string' && /^https:/i.test(message.url)) {
        void WebBrowser.openBrowserAsync(message.url);
      } else {
        Alert.alert(STRINGS.downloadFailed);
      }
    }
  }, []);

  // iOS reports file responses instead of saving them; fetch them in the page (with the
  // user's cookies) so they go through the same save/share bridge.
  const onFileDownload = useCallback(({ nativeEvent }: FileDownloadEvent) => {
    webView.current?.injectJavaScript(`window.__garadDownload(${JSON.stringify(nativeEvent.downloadUrl)}); true;`);
  }, []);

  const openInPage = (url: string) => {
    webView.current?.injectJavaScript(`window.location.href = ${JSON.stringify(url)}; true;`);
  };

  const openUpdate = () => {
    const url = updateUrl(config);
    if (url) void Linking.openURL(url).catch(() => openExternally(url));
  };

  const retry = () => {
    setFailed(false);
    webView.current?.reload();
  };

  const status = updateStatus(config);
  const announcement = config?.announcement;

  if (config?.maintenance.enabled) {
    return (
      <SafeAreaView style={[styles.flex, { backgroundColor: background }]}>
        <StatusBar style={isDark ? 'light' : 'dark'} />
        <BlockingScreen
          title={STRINGS.maintenanceTitle}
          body={config.maintenance.message || STRINGS.maintenanceBody}
          actionLabel={STRINGS.retry}
          onAction={() => void loadConfig()}
          background={background}
          colors={c}
        />
      </SafeAreaView>
    );
  }

  if (status === 'required') {
    return (
      <SafeAreaView style={[styles.flex, { backgroundColor: background }]}>
        <StatusBar style={isDark ? 'light' : 'dark'} />
        <BlockingScreen
          title={STRINGS.updateRequiredTitle}
          body={config?.update.message || STRINGS.updateRequiredBody}
          actionLabel={updateUrl(config) ? STRINGS.update : undefined}
          onAction={openUpdate}
          background={background}
          colors={c}
        />
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={[styles.flex, { backgroundColor: background }]} edges={['top', 'bottom']}>
      <StatusBar style={isDark ? 'light' : 'dark'} />
      {status === 'available' && !dismissed.update && (
        <Banner
          message={config?.update.message || STRINGS.updateAvailable}
          actionLabel={updateUrl(config) ? STRINGS.update : undefined}
          onAction={openUpdate}
          onDismiss={() => setDismissed((d) => ({ ...d, update: true }))}
          dismissLabel={STRINGS.later}
          colors={c}
        />
      )}
      {announcement && dismissed.announcement !== announcement.message && (
        <Banner
          message={announcement.message}
          actionLabel={announcement.url ? '›' : undefined}
          onAction={() => announcement.url && (isSiteUrl(announcement.url) ? openInPage(announcement.url) : openExternally(announcement.url))}
          onDismiss={() => setDismissed((d) => ({ ...d, announcement: announcement.message }))}
          dismissLabel={STRINGS.close}
          colors={c}
        />
      )}
      {progress > 0 && progress < 1 && (
        <View style={[styles.progress, { width: `${progress * 100}%`, backgroundColor: c.brand }]} />
      )}

      <WebView
        ref={webView}
        source={{ uri }}
        style={[styles.flex, { backgroundColor: background }]}
        applicationNameForUserAgent={APP_USER_AGENT}
        originWhitelist={['*']}
        javaScriptEnabled
        domStorageEnabled
        sharedCookiesEnabled
        thirdPartyCookiesEnabled
        allowsBackForwardNavigationGestures
        allowsInlineMediaPlayback
        mediaPlaybackRequiresUserAction={false}
        mediaCapturePermissionGrantType="grantIfSameHostElsePrompt"
        allowFileAccess={false}
        setSupportMultipleWindows={false}
        pullToRefreshEnabled
        keyboardDisplayRequiresUserAction={false}
        contentInsetAdjustmentBehavior="never"
        automaticallyAdjustContentInsets={false}
        overScrollMode="never"
        textZoom={100}
        onShouldStartLoadWithRequest={onShouldStartLoadWithRequest}
        onNavigationStateChange={onNavigationStateChange}
        onMessage={onMessage}
        onFileDownload={onFileDownload}
        injectedJavaScriptBeforeContentLoaded={BRIDGE_SCRIPT}
        onLoadProgress={({ nativeEvent }) => setProgress(nativeEvent.progress)}
        onLoadEnd={() => {
          setProgress(1);
          void SplashScreen.hideAsync();
        }}
        onError={() => setFailed(true)}
        onContentProcessDidTerminate={() => webView.current?.reload()}
        onRenderProcessGone={() => {
          webView.current?.reload();
          return true;
        }}
      />

      {failed && (
        <BlockingScreen
          title={STRINGS.offlineTitle}
          body={STRINGS.offlineBody}
          actionLabel={STRINGS.retry}
          onAction={retry}
          background={background}
          colors={c}
        />
      )}

      <AppMenu
        visible={menuOpen}
        onClose={() => setMenuOpen(false)}
        config={config}
        version={APP_VERSION}
        updateNote={updateNote}
        onTalk={() => {
          setMenuOpen(false);
          openInPage(withVoice(START_URL));
        }}
        onOpenLink={(url) => {
          setMenuOpen(false);
          if (isSiteUrl(url)) openInPage(url);
          else openExternally(url);
        }}
        onCheckUpdates={async () => {
          const next = await loadConfig();
          const nextStatus = updateStatus(next);
          if (nextStatus === 'none') setUpdateNote(STRINGS.upToDate);
          else {
            setMenuOpen(false);
            setDismissed((d) => ({ ...d, update: false }));
          }
        }}
        colors={c}
        background={background}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  progress: { height: 2 },
});
