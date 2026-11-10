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
    required this.libraryEmpty,
    required this.openChat,
    required this.thinking,
    required this.creatingImage,
    required this.creatingDocument,
    required this.searchingWeb,
    required this.question,
    required this.openFile,
    required this.images,
    required this.documents,
    required this.documentsEmpty,
    required this.all,
    required this.searchLibrary,
    required this.describeImage,
    required this.maxPhotos,
    required this.cameraUnavailable,
    required this.photosUnavailable,
    required this.removePhoto,
    required this.removeFile,
    required this.maxFiles,
    required this.fileTooBig,
    required this.filesUnavailable,
    required this.summarizeFile,
    required this.editImage,
    required this.editHint,
    required this.describeEdit,
    required this.reshapeAsk,
    required this.square,
    required this.portrait,
    required this.landscape,
    required this.undo,
    required this.clearSelection,
    required this.edit,
    required this.resize,
    required this.markup,
    required this.remove,
    required this.markupHint,
    required this.removeHint,
    required this.removeAsk,
    required this.removeOptional,
    required this.save,
    required this.saved,
    required this.saveFailed,
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
  final String libraryEmpty;
  final String openChat;
  final String thinking;
  final String creatingImage;
  final String creatingDocument;
  final String searchingWeb;
  final String question;
  final String openFile;
  final String images;
  final String documents;
  final String documentsEmpty;
  final String all;
  final String searchLibrary;
  final String describeImage;
  final String maxPhotos;
  final String cameraUnavailable;
  final String photosUnavailable;
  final String removePhoto;
  final String removeFile;
  final String maxFiles;
  final String fileTooBig;
  final String filesUnavailable;
  final String summarizeFile;
  final String editImage;
  final String editHint;
  final String describeEdit;

  /// 'Change it to a {shape} format.' — {shape} is square / portrait / landscape.
  final String reshapeAsk;
  final String square;
  final String portrait;
  final String landscape;
  final String undo;
  final String clearSelection;
  final String edit;
  final String resize;
  final String markup;
  final String remove;
  final String markupHint;
  final String removeHint;
  final String removeAsk;
  final String removeOptional;
  final String save;
  final String saved;
  final String saveFailed;
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

  // The ＋ sheet ("Add to chat").
  String get addToChat => isSomali ? 'Ku dar sheekada' : 'Add to chat';
  String get camera => isSomali ? 'Kamarad' : 'Camera';
  String get photos => isSomali ? 'Sawirro' : 'Photos';
  String get files => isSomali ? 'Faylal' : 'Files';
  String get webSearch => isSomali ? 'Ka raadi internetka' : 'Web search';
  String get close => isSomali ? 'Xir' : 'Close';

  // Apps and websites the AI builds (Claude-style preview).
  String get artifacts => isSomali ? 'Waxyaabaha la dhisay' : 'Artifacts';
  String get newArtifact => isSomali ? 'Cusub' : 'New';
  String get websites => isSomali ? 'Websaydhyo' : 'Websites';
  String get apps => isSomali ? 'Apps' : 'Apps';
  String get noArtifacts => isSomali
      ? 'Weli wax lama dhisin. Weydii Garad inuu kuu dhiso website ama app, halkan ayay ka soo muuqan doonaan.'
      : 'Nothing built yet. Ask Garad to build a website or app and it will show up here.';
  String get website => isSomali ? 'Website' : 'Website';
  String get websiteKind => isSomali ? 'Website · HTML' : 'Website · HTML';
  String get appKind => isSomali ? 'App · React' : 'App · React';
  String appVersion(int n) => isSomali ? 'Nooca $n' : 'Version $n';
  String get buildingApp => isSomali ? 'Waa la dhisayaa…' : 'Building…';
  String writingCode(int lines) => isSomali ? 'Koodh ayaa la qorayaa · $lines sadar' : 'Writing code · $lines lines';
  String get tapToOpen => isSomali ? 'Taabo si aad u furto' : 'Tap to open';
  String get preview => isSomali ? 'Muuqaal' : 'Preview';
  String get code => isSomali ? 'Koodh' : 'Code';
  String get reload => isSomali ? 'Dib u soo rar' : 'Reload';
  String get copyCode => isSomali ? 'Koobi koodhka' : 'Copy code';
  String get codeCopied => isSomali ? 'Koodhka waa la koobiyeeyay' : 'Code copied';
  String get shareFile => isSomali ? 'La wadaag faylka' : 'Share file';
  String get askForChanges => isSomali ? 'Weydii isbeddel…' : 'Ask for changes…';
  String get send => isSomali ? 'Dir' : 'Send';
  String get appError => isSomali ? 'App-ku khalad ayuu la kulmay' : 'This app hit an error';
  String get fixIt => isSomali ? 'Hagaaji' : 'Fix it';
  String get continueWithoutAccount => isSomali ? 'Ku sii wad akoon la’aan' : 'Continue without an account';
  String get logIn => isSomali ? 'Gal' : 'Log in';
  String get run => isSomali ? 'Kici' : 'Run';
  String get running => isSomali ? 'Waa socdaa' : 'Running';
  String get runningCode => isSomali ? 'Koodhka waa la kicinayaa…' : 'Running the code…';
  String get output => isSomali ? 'Natiijada' : 'Output';
  String get noOutput => isSomali ? 'Wax natiijo ah ma soo bixin.' : 'No output.';
  String get runTookTooLong =>
      isSomali ? 'Waa la joojiyay: wuxuu qaatay waqti aad u dheer.' : 'Stopped: it took too long.';
  String fixAppError(String error) => isSomali
      ? 'App-ku wuxuu muujinayaa khaladkan: "$error". Fadlan hagaaji oo dib u qor faylka oo dhan.'
      : 'The app shows this error: "$error". Please fix it and write the whole file again.';

  // Settings.
  String get account => isSomali ? 'Akoonka' : 'Account';
  String get app => isSomali ? 'App-ka' : 'App';
  String get appearance => isSomali ? 'Muuqaalka' : 'Appearance';
  String get profile => isSomali ? 'Astaanta' : 'Profile';
  String get billing => isSomali ? 'Lacag bixinta' : 'Billing';
  String get privacy => isSomali ? 'Asturnaanta' : 'Privacy';
  String get voice => isSomali ? 'Codka' : 'Voice';
  String get light => isSomali ? 'Iftiin' : 'Light';
  String get dark => isSomali ? 'Mugdi' : 'Dark';
  String get system => isSomali ? 'Taleefanka' : 'System';
  String get about => isSomali ? 'Ku saabsan' : 'About';
  String get version => isSomali ? 'Nooca' : 'Version';

  // "Select model".
  String get selectModel => isSomali ? 'Dooro moodeelka' : 'Select model';
  String get moreModels => isSomali ? 'Moodeelo kale' : 'More models';
  String get back => isSomali ? 'Dib' : 'Back';
  String get upgrade => isSomali ? 'Kor u qaad' : 'Upgrade';
  String get noCredits => isSomali ? 'Kiridit ma jiro' : 'No credits';
  String get tagFable => isSomali ? 'Hawlaha ugu adag' : 'For your toughest challenges';
  String get tagOpus => isSomali ? 'Shaqo adag iyo hawl maalmeed' : 'For complex work and everyday tasks';
  String get tagSonnet => isSomali ? 'Ugu waxtarka badan hawlaha fudud' : 'Most efficient for simpler tasks';
  String get tagHaiku => isSomali ? 'Ugu dhaqsaha badan jawaabaha gaagaaban' : 'Fastest for quick answers';

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
  libraryEmpty: 'Sawirrada aad ku sameyso sheekooyinka halkan ayay ka muuqan doonaan.',
  openChat: 'Fur sheekada',
  thinking: 'Waan ka fikirayaa…',
  creatingImage: 'Sawirka ayaan samaynayaa…',
  creatingDocument: 'Dukumentiga ayaan diyaarinayaa…',
  searchingWeb: 'Internetka ayaan ka raadinayaa…',
  question: "Su'aal",
  openFile: 'Fur faylka',
  images: 'Sawirro',
  documents: 'Dukumentiyo',
  documentsEmpty: 'Dukumentiyada aad ku sameyso sheekooyinka halkan ayay ka muuqan doonaan.',
  all: 'Dhammaan',
  searchLibrary: 'Raadi',
  describeImage: 'Maxaa sawirkan ku jira?',
  maxPhotos: 'Ugu badnaan 4 sawir fariintiiba.',
  cameraUnavailable: 'Kamaradda lama heli karo. Hubi oggolaanshaha.',
  photosUnavailable: 'Sawirrada lama furi karo. Hubi oggolaanshaha.',
  removePhoto: 'Ka saar sawirka',
  removeFile: 'Ka saar faylka',
  maxFiles: 'Ugu badnaan 5 fayl fariintiiba.',
  fileTooBig: 'Faylku wuu weyn yahay. Ugu badnaan 15 MB.',
  filesUnavailable: 'Faylasha lama furi karo.',
  summarizeFile: 'Ka soo koob faylkan.',
  editImage: 'Wax ka beddel sawirka',
  editHint: 'Sharax isbeddelka aad rabto ee sawirka oo dhan.',
  describeEdit: 'Sharax isbeddelka…',
  reshapeAsk: 'U beddel qaab {shape} ah.',
  square: 'Afar gees',
  portrait: 'Taagan',
  landscape: 'Jiifa',
  undo: 'Dib u celi',
  clearSelection: 'Tirtir xulashada',
  edit: 'Wax ka beddel',
  resize: 'Cabbir',
  markup: 'Calaamadee',
  remove: 'Ka saar',
  markupHint: 'Rinji qaybta aad beddelayso, kadib sharax waxa la sameeyo.',
  removeHint: 'Rinji waxa aad rabto inaad ka saarto.',
  removeAsk: 'Ka saar waxa aan rinjiyay, meesha si dabiici ah u buuxi.',
  removeOptional: 'Wax kale? (ikhtiyaari)',
  save: 'Kaydi',
  saved: 'Waa la kaydiyay',
  saveFailed: 'Sawirka lama kaydin karo. Hubi oggolaanshaha.',
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
  tabChat: 'Sheeko',
  tabToolkit: 'Qalabka AI',
  goodMorning: 'Subax wanaagsan',
  goodAfternoon: 'Galab wanaagsan',
  goodEvening: 'Fiid wanaagsan',
  tagline: 'Mashruucaaga xiga wuxuu ku bilaabmi karaa hal weedh.',
  messageHint: 'Wax weydii Garad',
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
  libraryEmpty: 'Images you create in chats will show up here.',
  openChat: 'Open chat',
  thinking: 'Thinking…',
  creatingImage: 'Creating image…',
  creatingDocument: 'Preparing your document…',
  searchingWeb: 'Searching the web…',
  question: 'Question',
  openFile: 'Open file',
  images: 'Images',
  documents: 'Documents',
  documentsEmpty: 'Documents you create in chats will show up here.',
  all: 'All',
  searchLibrary: 'Search',
  describeImage: "What's in this image?",
  maxPhotos: 'Up to 4 photos per message.',
  cameraUnavailable: 'The camera is not available. Check the permission.',
  photosUnavailable: 'Could not open your photos. Check the permission.',
  removePhoto: 'Remove photo',
  removeFile: 'Remove file',
  maxFiles: 'Up to 5 files per message.',
  fileTooBig: 'This file is too big. The limit is 15 MB.',
  filesUnavailable: 'Could not open your files.',
  summarizeFile: 'Summarize this file.',
  editImage: 'Edit image',
  editHint: 'Describe the change you want to the whole picture.',
  describeEdit: 'Describe your edit…',
  reshapeAsk: 'Change it to a {shape} format.',
  square: 'Square',
  portrait: 'Portrait',
  landscape: 'Landscape',
  undo: 'Undo',
  clearSelection: 'Clear selection',
  edit: 'Edit',
  resize: 'Resize',
  markup: 'Markup',
  remove: 'Remove',
  markupHint: 'Paint over the part to change, then describe what to do there.',
  removeHint: 'Paint over what you want to remove.',
  removeAsk: 'Remove what I painted over and fill the space so it blends in naturally.',
  removeOptional: 'Anything else? (optional)',
  save: 'Save',
  saved: 'Saved',
  saveFailed: 'Could not save the image. Check the permission.',
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
  tabChat: 'Chat',
  tabToolkit: 'AI Toolkit',
  goodMorning: 'Good morning',
  goodAfternoon: 'Good afternoon',
  goodEvening: 'Good evening',
  tagline: 'Your next project can start with one sentence.',
  messageHint: 'Ask Garad anything',
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
