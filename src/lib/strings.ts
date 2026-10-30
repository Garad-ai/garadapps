import { getLocales } from 'expo-localization';

const so = {
  offlineTitle: 'Lama gaari karo Garad AI',
  offlineBody: 'Hubi internetkaaga oo isku day mar kale.',
  retry: 'Isku day mar kale',
  downloadFailed: 'Faylka lama soo dejin karo. Isku day mar kale.',
  maintenanceTitle: 'Garad AI waa la cusbooneysiinayaa',
  maintenanceBody: 'Fadlan dib ugu soo laabo wax yar kadib.',
  updateRequiredTitle: 'Cusbooneysii Garad AI',
  updateRequiredBody: 'Nooca cusub ayaa loo baahan yahay si aad u sii isticmaasho app-ka.',
  updateAvailable: 'Nooc cusub oo Garad AI ah ayaa diyaar ah.',
  update: 'Cusbooneysii',
  later: 'Hadhow',
  close: 'Xir',
  menuTitle: 'Garad AI',
  talkToGarad: 'La hadal Garad',
  checkForUpdates: 'Hubi cusbooneysiin',
  upToDate: 'Waxaad haysataa nooca ugu dambeeyay.',
  version: 'Nooca',
};

type Strings = typeof so;

const en: Strings = {
  offlineTitle: "Can't reach Garad AI",
  offlineBody: 'Check your internet connection and try again.',
  retry: 'Try again',
  downloadFailed: "The file couldn't be downloaded. Please try again.",
  maintenanceTitle: 'Garad AI is being updated',
  maintenanceBody: 'Please come back in a little while.',
  updateRequiredTitle: 'Update Garad AI',
  updateRequiredBody: 'A newer version is needed to keep using the app.',
  updateAvailable: 'A new version of Garad AI is available.',
  update: 'Update',
  later: 'Later',
  close: 'Close',
  menuTitle: 'Garad AI',
  talkToGarad: 'Talk to Garad',
  checkForUpdates: 'Check for updates',
  upToDate: 'You have the latest version.',
  version: 'Version',
};

/** Somali unless the phone is set to English. */
export const STRINGS: Strings = getLocales()[0]?.languageCode === 'en' ? en : so;
