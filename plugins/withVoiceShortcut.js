// Expo config plugin: adds a static Android launcher shortcut, "Talk to Garad", that
// opens garadai://voice and starts Garad Voice straight away (long-press the app icon,
// or pin it to the home screen). Helpful for blind and low-vision users with TalkBack.
const fs = require('fs');
const path = require('path');
const {
  AndroidConfig,
  withAndroidManifest,
  withDangerousMod,
  withStringsXml,
} = require('expo/config-plugins');

const SHORTCUTS_RESOURCE = '@xml/garad_shortcuts';

function shortcutsXml(packageName, scheme) {
  return `<?xml version="1.0" encoding="utf-8"?>
<shortcuts xmlns:android="http://schemas.android.com/apk/res/android">
  <shortcut
    android:shortcutId="talk_to_garad"
    android:enabled="true"
    android:icon="@mipmap/ic_launcher"
    android:shortcutShortLabel="@string/garad_shortcut_talk_short"
    android:shortcutLongLabel="@string/garad_shortcut_talk_long">
    <intent
      android:action="android.intent.action.VIEW"
      android:data="${scheme}://voice"
      android:targetPackage="${packageName}"
      android:targetClass="${packageName}.MainActivity" />
  </shortcut>
</shortcuts>
`;
}

module.exports = function withVoiceShortcut(config) {
  const packageName = config.android?.package;
  const scheme = Array.isArray(config.scheme) ? config.scheme[0] : config.scheme;
  if (!packageName || !scheme) {
    throw new Error('withVoiceShortcut: expo.android.package and expo.scheme are required');
  }

  config = withStringsXml(config, (mod) => {
    mod.modResults = AndroidConfig.Strings.setStringItem(
      [
        AndroidConfig.Resources.buildResourceItem({ name: 'garad_shortcut_talk_short', value: 'Talk to Garad' }),
        AndroidConfig.Resources.buildResourceItem({ name: 'garad_shortcut_talk_long', value: 'Talk to Garad (voice)' }),
      ],
      mod.modResults
    );
    return mod;
  });

  config = withAndroidManifest(config, (mod) => {
    const activity = AndroidConfig.Manifest.getMainActivityOrThrow(mod.modResults);
    activity['meta-data'] = (activity['meta-data'] ?? []).filter(
      (item) => item.$['android:name'] !== 'android.app.shortcuts'
    );
    activity['meta-data'].push({
      $: { 'android:name': 'android.app.shortcuts', 'android:resource': SHORTCUTS_RESOURCE },
    });
    return mod;
  });

  config = withDangerousMod(config, [
    'android',
    (mod) => {
      const dir = path.join(mod.modRequest.platformProjectRoot, 'app/src/main/res/xml');
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(path.join(dir, 'garad_shortcuts.xml'), shortcutsXml(packageName, scheme));
      return mod;
    },
  ]);

  return config;
};
