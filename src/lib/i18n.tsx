import { getLocales } from 'expo-localization';
import { createContext, ReactNode, useCallback, useContext, useEffect, useMemo, useState } from 'react';

import { languageStore } from './storage';

const en = {
  greeting: 'How can I help you today?',
  suggestions: [
    'Write a professional email',
    'Explain a topic simply',
    'Translate text into Somali',
    'Plan a small business',
  ],
  search: 'Search chats',
  today: 'Today',
  yesterday: 'Yesterday',
  previous7: 'Previous 7 days',
  older: 'Older',
  menu: 'Open menu',
  disclaimer: 'Garad AI can make mistakes. Check important information.',
  appTagline: 'AI tools and intelligent agents for Somalia and East Africa',
  email: 'Email',
  password: 'Password',
  firstName: 'First name',
  lastName: 'Last name',
  signIn: 'Sign in',
  signUp: 'Create account',
  noAccount: "Don't have an account?",
  haveAccount: 'Already have an account?',
  forgotPassword: 'Forgot password?',
  sendResetLink: 'Send reset link',
  resetSent: 'If an account exists for this email, a reset link has been sent.',
  backToSignIn: 'Back to sign in',
  registered: 'Account created. Check your email if confirmation is required, then sign in.',
  otpCode: 'Email verification code',
  otpSent: 'We sent a verification code to your email.',
  twoFactorCode: 'Authenticator code',
  verify: 'Verify',
  images: 'Images',
  account: 'Account',
  newChat: 'New chat',
  noChats: 'No conversations yet. Start a new chat.',
  messagePlaceholder: 'Message Garad AI…',
  send: 'Send',
  stop: 'Stop',
  delete: 'Delete',
  cancel: 'Cancel',
  copy: 'Copy',
  copied: 'Copied',
  deleteChatConfirm: 'Delete this conversation?',
  imagePrompt: 'Describe the image you want…',
  generate: 'Generate',
  generating: 'Generating…',
  recentImages: 'Recent images',
  noImages: 'Your generated images will appear here.',
  share: 'Share',
  plan: 'Plan',
  freePlan: 'Free',
  wordCredits: 'Word credits',
  imageCredits: 'Image credits',
  unlimited: 'Unlimited',
  language: 'Language',
  privacy: 'Privacy policy',
  terms: 'Terms of service',
  signOut: 'Sign out',
  deleteAccount: 'Delete account',
  deleteAccountConfirm:
    'This permanently deletes your Garad AI account and all of its data. This cannot be undone.',
  networkError: 'Could not reach Garad AI. Check your internet connection and try again.',
  genericError: 'Something went wrong. Please try again.',
  retry: 'Try again',
  required: 'Please fill in all fields.',
};

type Strings = typeof en;

const so: Strings = {
  greeting: 'Maxaan kaa caawin karaa maanta?',
  suggestions: [
    'Qor iimayl xirfadeed',
    'Ii sharax mawduuc si fudud',
    'U turjun qoraal Af-Soomaali',
    'Qorshee ganacsi yar',
  ],
  search: 'Raadi wadahadallada',
  today: 'Maanta',
  yesterday: 'Shalay',
  previous7: '7-dii maalmood ee la soo dhaafay',
  older: 'Ka hor',
  menu: 'Fur menu-ga',
  disclaimer: 'Garad AI wuu qaldami karaa. Hubi macluumaadka muhiimka ah.',
  appTagline: 'Qalab AI iyo wakiillo caqli leh oo loogu talagalay Soomaaliya iyo Bariga Afrika',
  email: 'Iimayl',
  password: 'Furaha sirta ah',
  firstName: 'Magaca koowaad',
  lastName: 'Magaca dambe',
  signIn: 'Gal',
  signUp: 'Samee akoon',
  noAccount: 'Akoon ma lihid?',
  haveAccount: 'Akoon horay ayaad u leedahay?',
  forgotPassword: 'Ma ilowday furaha sirta ah?',
  sendResetLink: 'Soo dir linkiga dib-u-dejinta',
  resetSent: 'Haddii akoon iimayladan leh jiro, link dib-u-dejin ah ayaa loo diray.',
  backToSignIn: 'Ku noqo galitaanka',
  registered: 'Akoonka waa la sameeyay. Hubi iimaylkaaga haddii xaqiijin loo baahan yahay, kadib gal.',
  otpCode: 'Koodhka xaqiijinta iimaylka',
  otpSent: 'Koodh xaqiijin ah ayaan iimaylkaaga u dirnay.',
  twoFactorCode: 'Koodhka authenticator-ka',
  verify: 'Xaqiiji',
  images: 'Sawirro',
  account: 'Akoon',
  newChat: 'Wadahadal cusub',
  noChats: 'Weli wadahadal ma jiro. Bilow wadahadal cusub.',
  messagePlaceholder: 'U qor Garad AI…',
  send: 'Dir',
  stop: 'Jooji',
  delete: 'Tirtir',
  cancel: 'Ka noqo',
  copy: 'Koobiyee',
  copied: 'Waa la koobiyeeyay',
  deleteChatConfirm: 'Ma tirtirtaa wadahadalkan?',
  imagePrompt: 'Sharax sawirka aad rabto…',
  generate: 'Samee',
  generating: 'Waa la samaynayaa…',
  recentImages: 'Sawirradii dhowaa',
  noImages: 'Sawirrada aad samayso halkan ayay ka muuqan doonaan.',
  share: 'La wadaag',
  plan: 'Qorshe',
  freePlan: 'Bilaash',
  wordCredits: 'Kredit-ka erayada',
  imageCredits: 'Kredit-ka sawirrada',
  unlimited: 'Aan xad lahayn',
  language: 'Luqadda',
  privacy: 'Siyaasadda asturnaanta',
  terms: 'Shuruudaha adeegga',
  signOut: 'Ka bax',
  deleteAccount: 'Tirtir akoonka',
  deleteAccountConfirm:
    'Tani waxay si joogto ah u tirtiraysaa akoonkaaga Garad AI iyo xogtiisa oo dhan. Dib looma soo celin karo.',
  networkError: 'Lama gaari karo Garad AI. Hubi internetkaaga oo isku day mar kale.',
  genericError: 'Wax qalad ah ayaa dhacay. Fadlan isku day mar kale.',
  retry: 'Isku day mar kale',
  required: 'Fadlan buuxi dhammaan meelaha.',
};

export type Language = 'so' | 'en';
export const LANGUAGES: { code: Language; label: string }[] = [
  { code: 'so', label: 'Soomaali' },
  { code: 'en', label: 'English' },
];

const dictionaries: Record<Language, Strings> = { so, en };

function deviceLanguage(): Language {
  const code = getLocales()[0]?.languageCode;
  return code === 'en' ? 'en' : 'so';
}

type I18nValue = {
  language: Language;
  t: Strings;
  setLanguage: (language: Language) => void;
};

const I18nContext = createContext<I18nValue | null>(null);

export function I18nProvider({ children }: { children: ReactNode }) {
  const [language, setLanguageState] = useState<Language>(deviceLanguage);

  useEffect(() => {
    languageStore.get().then((stored) => {
      if (stored === 'so' || stored === 'en') setLanguageState(stored);
    });
  }, []);

  const setLanguage = useCallback((next: Language) => {
    setLanguageState(next);
    void languageStore.set(next);
  }, []);

  const value = useMemo(
    () => ({ language, t: dictionaries[language], setLanguage }),
    [language, setLanguage]
  );

  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}

export function useI18n(): I18nValue {
  const value = useContext(I18nContext);
  if (!value) throw new Error('useI18n must be used inside I18nProvider');
  return value;
}
