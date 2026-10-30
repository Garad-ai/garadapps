import { getLocales } from 'expo-localization';
import * as SplashScreen from 'expo-splash-screen';
import { StatusBar } from 'expo-status-bar';
import * as WebBrowser from 'expo-web-browser';
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  Alert,
  BackHandler,
  Image,
  Linking,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { WebView as RNWebView, WebViewMessageEvent, WebViewNavigation } from 'react-native-webview';
import type { FileDownloadEvent, ShouldStartLoadRequest } from 'react-native-webview/lib/WebViewTypes';

import { BRIDGE_SCRIPT, copyText, saveDownload, speak, stopSpeaking } from '@/lib/bridge';
import { APP_USER_AGENT, isSiteUrl, START_URL } from '@/lib/config';
import { useIsDark, usePalette } from '@/lib/theme';

// react-native-webview 14 types default the extra-props parameter to `undefined`, which
// intersects every prop to `never` under current TypeScript; `object` keeps the real props.
const WebView = RNWebView as unknown as typeof RNWebView<object>;
type WebViewHandle = RNWebView<object>;

const somali = getLocales()[0]?.languageCode !== 'en';
const STRINGS = somali
  ? {
      title: 'Lama gaari karo Garad AI',
      body: 'Hubi internetkaaga oo isku day mar kale.',
      retry: 'Isku day mar kale',
      downloadFailed: 'Faylka lama soo dejin karo. Isku day mar kale.',
    }
  : {
      title: "Can't reach Garad AI",
      body: 'Check your internet connection and try again.',
      retry: 'Try again',
      downloadFailed: "The file couldn't be downloaded. Please try again.",
    };

/**
 * The Garad AI app: the garad.ai web app in a native shell, so the app has exactly
 * the same design, account, data and AI features as the website. Links to other
 * sites open outside the app.
 */
export default function GaradApp() {
  const c = usePalette();
  const deviceDark = useIsDark();
  // The website reports its own theme (it can differ from the device setting); see
  // Garad_ai/frontend/src/core/appShell.ts.
  const [pageTheme, setPageTheme] = useState<{ background: string; dark: boolean } | null>(null);
  const background = pageTheme?.background ?? c.background;
  const isDark = pageTheme?.dark ?? deviceDark;
  const webView = useRef<WebViewHandle>(null);
  const [canGoBack, setCanGoBack] = useState(false);
  const [progress, setProgress] = useState(0);
  const [failed, setFailed] = useState(false);

  // Hide the splash screen after the first page load, or after a few seconds at most.
  useEffect(() => {
    const timer = setTimeout(() => SplashScreen.hideAsync(), 8000);
    return () => clearTimeout(timer);
  }, []);

  // Android back button goes back inside the website before leaving the app.
  useEffect(() => {
    if (Platform.OS !== 'android') return;
    const subscription = BackHandler.addEventListener('hardwareBackPress', () => {
      if (!canGoBack) return false;
      webView.current?.goBack();
      return true;
    });
    return () => subscription.remove();
  }, [canGoBack]);

  const onNavigationStateChange = (state: WebViewNavigation) => setCanGoBack(state.canGoBack);

  const onShouldStartLoadWithRequest = useCallback((request: ShouldStartLoadRequest) => {
    const { url } = request;
    if (url.startsWith('about:') || url.startsWith('blob:') || url.startsWith('data:')) return true;
    // Embedded frames (videos, maps, payment widgets) load inside the page.
    if (Platform.OS === 'ios' && request.isTopFrame === false) return true;
    if (isSiteUrl(url)) return true;

    if (/^https?:/i.test(url)) void WebBrowser.openBrowserAsync(url);
    else void Linking.openURL(url).catch(() => undefined);
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

  const retry = () => {
    setFailed(false);
    webView.current?.reload();
  };

  return (
    <SafeAreaView style={[styles.flex, { backgroundColor: background }]} edges={['top', 'bottom']}>
      <StatusBar style={isDark ? 'light' : 'dark'} />
      {progress > 0 && progress < 1 && (
        <View style={[styles.progress, { width: `${progress * 100}%`, backgroundColor: c.brand }]} />
      )}

      <WebView
        ref={webView}
        source={{ uri: START_URL }}
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
        <View style={[StyleSheet.absoluteFill, styles.offline, { backgroundColor: background }]}>
          <Image source={require('../../assets/images/splash-icon.png')} style={styles.mark} />
          <Text style={[styles.title, { color: c.text }]}>{STRINGS.title}</Text>
          <Text style={[styles.body, { color: c.muted }]}>{STRINGS.body}</Text>
          <Pressable
            accessibilityRole="button"
            onPress={retry}
            style={({ pressed }) => [styles.button, { backgroundColor: c.brand, opacity: pressed ? 0.85 : 1 }]}>
            <Text style={styles.buttonText}>{STRINGS.retry}</Text>
          </Pressable>
        </View>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  progress: { height: 2 },
  offline: { alignItems: 'center', justifyContent: 'center', padding: 32, gap: 12 },
  mark: { width: 64, height: 64, marginBottom: 8 },
  title: { fontSize: 20, fontWeight: '700', textAlign: 'center' },
  body: { fontSize: 15, lineHeight: 21, textAlign: 'center' },
  button: { marginTop: 12, borderRadius: 12, paddingHorizontal: 24, paddingVertical: 13 },
  buttonText: { color: '#fff', fontSize: 16, fontWeight: '600' },
});
