import 'chat_strings.dart';

/// Text for the Sign in / Sign up card (email and password, like garad.ai), in Somali and English —
/// the same language choice as the rest of the app.
class AuthStrings {
  const AuthStrings._({
    required this.signIn,
    required this.signUp,
    required this.subtitle,
    required this.fullName,
    required this.email,
    required this.password,
    required this.or,
    required this.google,
    required this.apple,
    required this.noAccount,
    required this.haveAccount,
    required this.forgotPassword,
    required this.forgotTitle,
    required this.forgotSubtitle,
    required this.sendLink,
    required this.sendAgain,
    required this.linkSent,
    required this.backToSignIn,
    required this.back,
    required this.invalidEmail,
    required this.required,
    required this.passwordShort,
    required this.showPassword,
    required this.hidePassword,
    required this.comingSoon,
  });

  final String signIn;
  final String signUp;
  final String subtitle;
  final String fullName;
  final String email;
  final String password;
  final String or;
  final String google;
  final String apple;
  final String noAccount;
  final String haveAccount;
  final String forgotPassword;
  final String forgotTitle;
  final String forgotSubtitle;
  final String sendLink;
  final String sendAgain;
  final String linkSent;
  final String backToSignIn;
  final String back;
  final String invalidEmail;
  final String required;
  final String passwordShort;
  final String showPassword;
  final String hidePassword;
  final String comingSoon;
}

const _so = AuthStrings._(
  signIn: 'Gal',
  signUp: 'Is diiwaangeli',
  subtitle: 'Waxaad heli doontaa jawaabo caqli badan, waxaadna soo diri kartaa faylal, sawirro iyo wax kale.',
  fullName: 'Magaca oo buuxa',
  email: 'Iimaylka',
  password: 'Furaha sirta ah',
  or: 'AMA',
  google: 'Ku sii wad Google',
  apple: 'Ku sii wad Apple',
  noAccount: 'Akoon ma lihid?',
  haveAccount: 'Akoon ma leedahay?',
  forgotPassword: 'Furaha ma ilowday?',
  forgotTitle: 'Furaha ma ilowday',
  forgotSubtitle: 'Geli iimaylkaaga. Waxaan kuu soo diraynaa link aad ku dooranayso furaha cusub.',
  sendLink: 'Dir link-ga',
  sendAgain: 'Mar kale dir',
  linkSent: 'Link-ga waa la diray. Eeg iimaylkaaga, iyo Spam-ka sidoo kale.',
  backToSignIn: 'Ku noqo Gal',
  back: 'Dib u noqo',
  invalidEmail: 'Iimayl sax ah geli',
  required: 'Waa loo baahan yahay',
  passwordShort: 'Ugu yaraan 8 xaraf',
  showPassword: 'Tus furaha',
  hidePassword: 'Qari furaha',
  comingSoon: 'Dhawaan ayuu imanayaa.',
);

const _en = AuthStrings._(
  signIn: 'Sign in',
  signUp: 'Sign up',
  subtitle: "You'll get smarter responses and can upload files, images and more.",
  fullName: 'Full name',
  email: 'Email',
  password: 'Password',
  or: 'OR',
  google: 'Continue with Google',
  apple: 'Continue with Apple',
  noAccount: "Don't have an account?",
  haveAccount: 'Already have an account?',
  forgotPassword: 'Forgot password?',
  forgotTitle: 'Forgot password',
  forgotSubtitle: "Enter your email and we'll send you a link to choose a new password.",
  sendLink: 'Send link',
  sendAgain: 'Send again',
  linkSent: 'The link is on its way. Check your inbox, and your spam folder too.',
  backToSignIn: 'Back to Sign in',
  back: 'Back',
  invalidEmail: 'Enter a valid email',
  required: 'Required',
  passwordShort: 'At least 8 characters',
  showPassword: 'Show password',
  hidePassword: 'Hide password',
  comingSoon: 'Coming soon.',
);

AuthStrings get authStrings => chatStrings.isSomali ? _so : _en;
