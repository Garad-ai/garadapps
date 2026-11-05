import 'dart:ui' show PlatformDispatcher;

/// Text for the login, chat and menu screens, in Somali and English (Somali unless the phone is English).
class ChatStrings {
  const ChatStrings._({
    required this.isSomali,
    required this.welcome,
    required this.welcomeBody,
    required this.login,
    required this.register,
    required this.noAccount,
    required this.haveAccount,
    required this.name,
    required this.email,
    required this.password,
    required this.passwordHint,
    required this.required,
    required this.invalidEmail,
    required this.newChat,
    required this.searchChats,
    required this.noResults,
    required this.library,
    required this.scheduled,
    required this.pinned,
    required this.recents,
    required this.seeAll,
    required this.settings,
    required this.talk,
    required this.menu,
    required this.noChats,
    required this.logout,
    required this.logoutConfirm,
    required this.cancel,
    required this.rename,
    required this.delete,
    required this.deleteConfirm,
    required this.pin,
    required this.unpin,
    required this.save,
    required this.tabChat,
    required this.tabToolkit,
    required this.goodMorning,
    required this.goodAfternoon,
    required this.goodEvening,
    required this.tagline,
    required this.messageHint,
    required this.listening,
    required this.disclaimer,
    required this.chipWrite,
    required this.chipLearn,
    required this.chipResearch,
    required this.chipPlan,
    required this.promptWrite,
    required this.promptLearn,
    required this.promptResearch,
    required this.promptPlan,
    required this.model,
    required this.chooseModel,
    required this.copy,
    required this.copied,
    required this.goodResponse,
    required this.badResponse,
    required this.feedbackThanks,
    required this.regenerate,
    required this.selectText,
    required this.answeredBy,
    required this.readAloud,
    required this.share,
    required this.notifications,
    required this.noNotifications,
    required this.attach,
    required this.more,
    required this.dictate,
    required this.voiceMode,
    required this.comingSoon,
    required this.stop,
    required this.retry,
    required this.micUnavailable,
    required this.cannotConnect,
    required this.timeout,
    required this.sessionExpired,
    required this.tooManyRequests,
    required this.somethingWrong,
  });

  final bool isSomali;
  final String welcome;
  final String welcomeBody;
  final String login;
  final String register;
  final String noAccount;
  final String haveAccount;
  final String name;
  final String email;
  final String password;
  final String passwordHint;
  final String required;
  final String invalidEmail;
  final String newChat;
  final String searchChats;
  final String noResults;
  final String library;
  final String scheduled;
  final String pinned;
  final String recents;
  final String seeAll;
  final String settings;
  final String talk;
  final String menu;
  final String noChats;
  final String logout;
  final String logoutConfirm;
  final String cancel;
  final String rename;
  final String delete;
  final String deleteConfirm;
  final String pin;
  final String unpin;
  final String save;
  final String tabChat;
  final String tabToolkit;
  final String goodMorning;
  final String goodAfternoon;
  final String goodEvening;
  final String tagline;
  final String messageHint;
  final String listening;
  final String disclaimer;
  final String chipWrite;
  final String chipLearn;
  final String chipResearch;
  final String chipPlan;
  final String promptWrite;
  final String promptLearn;
  final String promptResearch;
  final String promptPlan;
  final String model;
  final String chooseModel;
  final String copy;
  final String copied;
  final String goodResponse;
  final String badResponse;
  final String feedbackThanks;
  final String regenerate;
  final String selectText;
  final String answeredBy;
  final String readAloud;
  final String share;
  final String notifications;
  final String noNotifications;
  final String attach;
  final String more;
  final String dictate;
  final String voiceMode;
  final String comingSoon;
  final String stop;
  final String retry;
  final String micUnavailable;
  final String cannotConnect;
  final String timeout;
  final String sessionExpired;
  final String tooManyRequests;
  final String somethingWrong;

  /// "Good afternoon, Garad" — by the phone's time of day.
  String greeting(String name, DateTime now) {
    final hello = now.hour < 12 ? goodMorning : (now.hour < 17 ? goodAfternoon : goodEvening);
    final first = name.trim().split(RegExp(r'\s+')).first;
    return first.isEmpty ? hello : '$hello, $first';
  }
}

const _so = ChatStrings._(
  isSomali: true,
  welcome: 'Ku soo dhawoow Garad AI',
  welcomeBody: 'Gal akoonkaaga si aad ula sheekaysato Garad.',
  login: 'Gal',
  register: 'Is diiwaangeli',
  noAccount: 'Akoon ma lihid? Is diiwaangeli',
  haveAccount: 'Akoon ma leedahay? Gal',
  name: 'Magaca',
  email: 'Iimaylka',
  password: 'Furaha sirta ah',
  passwordHint: 'Ugu yaraan 8 xaraf',
  required: 'Waa loo baahan yahay',
  invalidEmail: 'Iimayl sax ah geli',
  newChat: 'Sheeko cusub',
  searchChats: 'Raadi sheekooyinka',
  noResults: 'Wax lama helin',
  library: 'Maktabadda',
  scheduled: 'Kuwa la qorsheeyay',
  pinned: 'La dhejiyay',
  recents: 'Kuwii u dambeeyay',
  seeAll: 'Dhammaan eeg…',
  settings: 'Dejinta',
  talk: 'Hadal',
  menu: 'Liiska',
  noChats: 'Weli sheeko ma jirto.',
  logout: 'Ka bax',
  logoutConfirm: 'Ma hubtaa inaad ka baxayso?',
  cancel: 'Jooji',
  rename: 'Magac beddel',
  delete: 'Tirtir',
  deleteConfirm: 'Sheekadan ma tirtirtaa? Lama soo celin karo.',
  pin: 'Dheji',
  unpin: 'Ka qaad dhejinta',
  save: 'Kaydi',
  tabChat: 'Sheeko',
  tabToolkit: 'Qalabka AI',
  goodMorning: 'Subax wanaagsan',
  goodAfternoon: 'Galab wanaagsan',
  goodEvening: 'Fiid wanaagsan',
  tagline: 'Mashruucaaga xiga wuxuu ku bilaabmi karaa hal weedh.',
  messageHint: 'Qor ama taabo 🎤 si aad u hadasho',
  listening: 'Waan ku dhageysanayaa…',
  disclaimer: 'Garad AI wuu qaldami karaa. Powered by Arkaan AI Center.',
  chipWrite: 'Qor',
  chipLearn: 'Baro',
  chipResearch: 'Baadhis',
  chipPlan: 'Qorshee',
  promptWrite: 'I caawi inaan qoro ',
  promptLearn: 'Ii sharax ',
  promptResearch: 'Baadh oo ii soo koob ',
  promptPlan: 'I caawi inaan qorsheeyo ',
  model: 'Moodeelka',
  chooseModel: 'Dooro moodeelka',
  copy: 'Koobiyee',
  copied: 'Waa la koobiyeeyay',
  goodResponse: 'Jawaab fiican',
  badResponse: 'Jawaab xun',
  feedbackThanks: 'Mahadsanid jawaab celintaada!',
  regenerate: 'Dib u samee jawaabta',
  selectText: 'Dooro qoraalka',
  answeredBy: 'Waxaa ka jawaabay',
  readAloud: 'Kor u akhri',
  share: 'Wadaag',
  notifications: 'Ogeysiisyada',
  noNotifications: 'Ogeysiis cusub ma jiro.',
  attach: 'Ku lifaaq fayl',
  more: 'Wax badan',
  dictate: 'Ku qor codkaaga',
  voiceMode: 'La hadal Garad',
  comingSoon: 'Dhawaan ayuu imanayaa.',
  stop: 'Jooji',
  retry: 'Isku day mar kale',
  micUnavailable: 'Makarafoonka lama heli karo. Hubi oggolaanshaha.',
  cannotConnect: 'Lama gaari karo Garad. Hubi internetkaaga.',
  timeout: 'Wakhti badan ayuu qaatay. Isku day mar kale.',
  sessionExpired: 'Fadlan mar kale gal.',
  tooManyRequests: 'Codsiyo badan. Sug daqiiqad kadibna isku day.',
  somethingWrong: 'Wax qalad ah ayaa dhacay. Isku day mar kale.',
);

const _en = ChatStrings._(
  isSomali: false,
  welcome: 'Welcome to Garad AI',
  welcomeBody: 'Sign in to chat with Garad.',
  login: 'Sign in',
  register: 'Create account',
  noAccount: "Don't have an account? Create one",
  haveAccount: 'Already have an account? Sign in',
  name: 'Name',
  email: 'Email',
  password: 'Password',
  passwordHint: 'At least 8 characters',
  required: 'Required',
  invalidEmail: 'Enter a valid email',
  newChat: 'New chat',
  searchChats: 'Search conversations',
  noResults: 'No matches',
  library: 'Library',
  scheduled: 'Scheduled',
  pinned: 'Pinned',
  recents: 'Recents',
  seeAll: 'See all…',
  settings: 'Settings',
  talk: 'Talk',
  menu: 'Menu',
  noChats: 'No chats yet.',
  logout: 'Sign out',
  logoutConfirm: 'Do you want to sign out?',
  cancel: 'Cancel',
  rename: 'Rename',
  delete: 'Delete',
  deleteConfirm: 'Delete this chat? This cannot be undone.',
  pin: 'Pin',
  unpin: 'Unpin',
  save: 'Save',
  tabChat: 'Chat',
  tabToolkit: 'AI Toolkit',
  goodMorning: 'Good morning',
  goodAfternoon: 'Good afternoon',
  goodEvening: 'Good evening',
  tagline: 'Your next project can start with one sentence.',
  messageHint: 'Type or tap 🎤 to talk',
  listening: 'Listening…',
  disclaimer: 'Garad AI can make mistakes. Powered by Arkaan AI Center.',
  chipWrite: 'Write',
  chipLearn: 'Learn',
  chipResearch: 'Research',
  chipPlan: 'Plan',
  promptWrite: 'Help me write ',
  promptLearn: 'Explain to me ',
  promptResearch: 'Research and summarize ',
  promptPlan: 'Help me plan ',
  model: 'Model',
  chooseModel: 'Choose a model',
  copy: 'Copy',
  copied: 'Copied',
  goodResponse: 'Good response',
  badResponse: 'Bad response',
  feedbackThanks: 'Thanks for your feedback!',
  regenerate: 'Regenerate',
  selectText: 'Select text',
  answeredBy: 'Answered by',
  readAloud: 'Read aloud',
  share: 'Share',
  notifications: 'Notifications',
  noNotifications: 'No new notifications.',
  attach: 'Attach a file',
  more: 'More',
  dictate: 'Dictate',
  voiceMode: 'Talk to Garad',
  comingSoon: 'Coming soon.',
  stop: 'Stop',
  retry: 'Try again',
  micUnavailable: 'The microphone is not available. Check the permission.',
  cannotConnect: "Can't reach Garad. Check your internet connection.",
  timeout: 'That took too long. Please try again.',
  sessionExpired: 'Please sign in again.',
  tooManyRequests: 'Too many requests. Wait a minute and try again.',
  somethingWrong: 'Something went wrong. Please try again.',
);

/// Somali unless the phone is set to English (same rule as the rest of the app).
final ChatStrings chatStrings = PlatformDispatcher.instance.locale.languageCode == 'en' ? _en : _so;
