import { Redirect } from 'expo-router';

/** `garadai://voice` (the "Talk to Garad" shortcut): open Chat Pro straight into Voice. */
export default function VoiceShortcut() {
  // A fresh value each time, so tapping the shortcut again while the app is open still works.
  return <Redirect href={{ pathname: '/', params: { voice: String(Date.now()) } }} />;
}
