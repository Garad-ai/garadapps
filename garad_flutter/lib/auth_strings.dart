import 'dart:ui' show PlatformDispatcher;

/// Text for the Sign in / Sign up page, in Somali and English (Somali unless the phone is English).
class AuthStrings {
  const AuthStrings._({
    required this.signIn,
    required this.signUp,
    required this.fullName,
    required this.fullNameHint,
    required this.phone,
    required this.phoneHint,
    required this.email,
    required this.emailHint,
    required this.password,
    required this.passwordHint,
    required this.rememberMe,
    required this.forgotPassword,
    required this.noAccount,
    required this.haveAccount,
    required this.dataSafe,
    required this.agreePrefix,
    required this.terms,
    required this.readOur,
    required this.privacy,
    required this.required,
    required this.invalidEmail,
    required this.invalidPhone,
    required this.passwordShort,
  });

  final String signIn;
  final String signUp;
  final String fullName;
  final String fullNameHint;
  final String phone;
  final String phoneHint;
  final String email;
  final String emailHint;
  final String password;
  final String passwordHint;
  final String rememberMe;
  final String forgotPassword;
  final String noAccount;
  final String haveAccount;
  final String dataSafe;
  final String agreePrefix;
  final String terms;
  final String readOur;
  final String privacy;
  final String required;
  final String invalidEmail;
  final String invalidPhone;
  final String passwordShort;
}

const _so = AuthStrings._(
  signIn: 'Gal',
  signUp: 'Is diiwaangeli',
  fullName: 'Magaca oo buuxa',
  fullNameHint: 'Magacaaga oo buuxa',
  phone: 'Taleefanka',
  phoneHint: 'Lambarka taleefankaaga',
  email: 'Iimaylka',
  emailHint: 'iimaylkaaga@email.com',
  password: 'Furaha sirta ah',
  passwordHint: 'Furahaaga sirta ah',
  rememberMe: 'I xasuuso',
  forgotPassword: 'Furaha ma ilowday?',
  noAccount: 'Akoon ma lihid?',
  haveAccount: 'Akoon ma leedahay?',
  dataSafe: 'Xogtaadu waa ammaan, waana qarsoodi',
  agreePrefix: 'Markaad sii wadato, waxaad oggolaatay',
  terms: 'Shuruudaha isticmaalka',
  readOur: 'Akhri',
  privacy: 'Siyaasadda asturnaanta',
  required: 'Waa loo baahan yahay',
  invalidEmail: 'Iimayl sax ah geli',
  invalidPhone: 'Lambar taleefan oo sax ah geli',
  passwordShort: 'Ugu yaraan 8 xaraf',
);

const _en = AuthStrings._(
  signIn: 'Sign in',
  signUp: 'Sign up',
  fullName: 'Full name',
  fullNameHint: 'Your full name',
  phone: 'Phone',
  phoneHint: 'Your Phone Number',
  email: 'Email Address',
  emailHint: 'your@email.com',
  password: 'Password',
  passwordHint: 'Your password',
  rememberMe: 'Remember me',
  forgotPassword: 'Forgot password?',
  noAccount: "Don't have account yet?",
  haveAccount: 'Already have an account?',
  dataSafe: 'Your data is safe, secure, and fully private',
  agreePrefix: 'By proceeding, you agree to our',
  terms: 'Terms of use',
  readOur: 'Read our',
  privacy: 'Privacy Policy',
  required: 'Required',
  invalidEmail: 'Enter a valid email',
  invalidPhone: 'Enter a valid phone number',
  passwordShort: 'At least 8 characters',
);

final AuthStrings authStrings = PlatformDispatcher.instance.locale.languageCode == 'en' ? _en : _so;
