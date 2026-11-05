import 'dart:ui' show PlatformDispatcher;

/// Text for scheduled tasks (the card in chat and the Scheduled screen), Somali and English.
class ScheduleStrings {
  const ScheduleStrings._({
    required this.title,
    required this.subtitle,
    required this.taskReady,
    required this.open,
    required this.today,
    required this.tomorrow,
    required this.inMinutes,
    required this.inHours,
    required this.inDays,
    required this.now,
    required this.months,
    required this.weekdays,
    required this.filters,
    required this.statuses,
    required this.scheduleHint,
    required this.searchHint,
    required this.empty,
    required this.nextRun,
    required this.lastRun,
    required this.lastResult,
    required this.pause,
    required this.resume,
    required this.delete,
    required this.deleteConfirm,
    required this.cancel,
    required this.created,
    required this.openChat,
    required this.eastAfricaTime,
    required this.recommended,
    required this.newTask,
    required this.newTaskHint,
    required this.create,
    required this.suggestions,
  });

  final String recommended;
  final String newTask;
  final String newTaskHint;
  final String create;

  /// Recommended tasks: (emoji, label shown, request sent to Garad).
  final List<(String, String, String)> suggestions;

  final String title;
  final String subtitle;
  final String taskReady;
  final String open;
  final String today;
  final String tomorrow;
  final String Function(int) inMinutes;
  final String Function(int) inHours;
  final String Function(int) inDays;
  final String now;
  final List<String> months;
  final List<String> weekdays;

  /// Tab labels by filter id.
  final Map<String, String> filters;

  /// Status labels by status id.
  final Map<String, String> statuses;
  final String scheduleHint;
  final String searchHint;
  final String empty;
  final String nextRun;
  final String lastRun;
  final String lastResult;
  final String pause;
  final String resume;
  final String delete;
  final String deleteConfirm;
  final String cancel;
  final String created;
  final String openChat;
  final String eastAfricaTime;
}

const _so = ScheduleStrings._(
  title: 'La qorsheeyay',
  subtitle: 'Garad ka codso inuu qorsheeyo hawlo, xasuusin, ama la socdo wararka cusub',
  taskReady: 'Hawsha la qorsheeyay waa diyaar',
  open: 'Fur',
  today: 'Maanta',
  tomorrow: 'Berri',
  inMinutes: _soMinutes,
  inHours: _soHours,
  inDays: _soDays,
  now: 'hadda',
  months: ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'],
  weekdays: ['Isn', 'Tal', 'Arb', 'Kha', 'Jim', 'Sab', 'Axd'],
  filters: {
    'all': 'Dhammaan',
    'upcoming': 'Soo socda',
    'active': 'Firfircoon',
    'paused': 'Hakad',
    'completed': 'Dhammaaday',
    'failed': 'Fashilmay',
  },
  statuses: {
    'active': 'La qorsheeyay',
    'paused': 'Hakad',
    'running': 'Socda',
    'completed': 'Dhammaaday',
    'failed': 'Fashilmay',
  },
  scheduleHint: 'Qorshee hawl…',
  searchHint: 'Raadi hawlahaaga',
  empty: 'Hawl halkan ma jirto.',
  nextRun: 'Marka xigta',
  lastRun: 'Markii u dambeysay',
  lastResult: 'Natiijadii u dambeysay',
  pause: 'Hakad geli',
  resume: 'Sii wad',
  delete: 'Tirtir',
  deleteConfirm: 'Hawshan ma tirtirtaa?',
  cancel: 'Jooji',
  created: 'Hawsha waa la qorsheeyay.',
  openChat: 'Fur sheekada',
  eastAfricaTime: 'Waqtiga Bariga Afrika',
  recommended: 'La soo jeediyay',
  newTask: 'Hawl cusub',
  newTaskHint: 'Maxaad rabtaa in Garad sameeyo, goormase? Tusaale: "Subax kasta 7da ii soo koob wararka"',
  create: 'Qorshee',
  suggestions: [
    (
      '💧',
      'I xasuusi inaan biyo cabbo',
      'I xasuusi inaan biyo cabbo 2-dii saacadoodba mar, 8da subaxnimo ilaa 8da habeennimo',
    ),
    (
      '📰',
      'Ii soo koob wararka subax kasta',
      'Subax kasta 7da ii soo koob wararka ugu muhiimsan Soomaaliya iyo Bariga Afrika',
    ),
    (
      '💱',
      'Qiimaha doollarka subax kasta',
      'Subax kasta 8da ii sheeg qiimaha doollarka Maraykanka ee shilinka Soomaaliga',
    ),
    ('🌦️', 'Cimilada Muqdisho subax kasta', 'Subax kasta 6:30 ii sheeg cimilada maanta ee Muqdisho'),
    ('🏃', 'I xasuusi jimicsiga', 'Fiid kasta 6da i xasuusi inaan jimicsi sameeyo'),
    (
      '📚',
      'Buug fiican oo toddobaadka dhammaadka',
      'Jimce kasta 5ta galabnimo ii soo jeedi buug fiican oo aan akhriyo dhammaadka toddobaadka',
    ),
  ],
);

String _soMinutes(int n) => n == 1 ? '1 daqiiqo kadib' : '$n daqiiqo kadib';
String _soHours(int n) => n == 1 ? '1 saac kadib' : '$n saacadood kadib';
String _soDays(int n) => n == 1 ? '1 maalin kadib' : '$n maalmood kadib';

const _en = ScheduleStrings._(
  title: 'Scheduled',
  subtitle: 'Ask Garad to schedule tasks, set reminders, or monitor for updates',
  taskReady: 'Scheduled task ready',
  open: 'Open',
  today: 'Today',
  tomorrow: 'Tomorrow',
  inMinutes: _enMinutes,
  inHours: _enHours,
  inDays: _enDays,
  now: 'now',
  months: ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'],
  weekdays: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
  filters: {
    'all': 'All',
    'upcoming': 'Upcoming',
    'active': 'Active',
    'paused': 'Paused',
    'completed': 'Completed',
    'failed': 'Failed',
  },
  statuses: {
    'active': 'Scheduled',
    'paused': 'Paused',
    'running': 'Running',
    'completed': 'Completed',
    'failed': 'Failed',
  },
  scheduleHint: 'Schedule a task',
  searchHint: 'Search your tasks',
  empty: 'No tasks here.',
  nextRun: 'Next run',
  lastRun: 'Last run',
  lastResult: 'Last result',
  pause: 'Pause',
  resume: 'Resume',
  delete: 'Delete',
  deleteConfirm: 'Delete this task?',
  cancel: 'Cancel',
  created: 'Task scheduled.',
  openChat: 'Open chat',
  eastAfricaTime: 'East Africa Time',
  recommended: 'Recommended',
  newTask: 'New task',
  newTaskHint: 'What should Garad do, and when? E.g. "Every morning at 7, summarise the news for me"',
  create: 'Schedule',
  suggestions: [
    ('💧', 'Remind me to drink water', 'Remind me to drink water every 2 hours from 8am to 8pm'),
    (
      '📰',
      'Update me on the news every morning',
      'Every morning at 7am, give me a short summary of the top news in Somalia and East Africa',
    ),
    (
      '💱',
      'Dollar exchange rate every morning',
      'Every morning at 8am, tell me the US dollar exchange rate in Somali shillings',
    ),
    ('🌦️', 'Mogadishu weather every morning', 'Every morning at 6:30am, tell me today\'s weather in Mogadishu'),
    ('🏃', 'Remind me to exercise', 'Every evening at 6pm remind me to exercise'),
    ('📚', 'Find me a great weekend read', 'Every Friday at 5pm, suggest a great book to read this weekend'),
  ],
);

String _enMinutes(int n) => n == 1 ? 'in 1 minute' : 'in $n minutes';
String _enHours(int n) => n == 1 ? 'in 1 hour' : 'in $n hours';
String _enDays(int n) => n == 1 ? 'in 1 day' : 'in $n days';

final ScheduleStrings scheduleStrings = PlatformDispatcher.instance.locale.languageCode == 'en' ? _en : _so;

/// "in 1 minute", "in 3 hours" — how long until [when].
String timeUntil(DateTime when, DateTime now) {
  final s = scheduleStrings;
  final diff = when.difference(now);
  if (diff.inSeconds < 30) return s.now;
  final minutes = (diff.inSeconds / 60).ceil();
  if (minutes < 60) return s.inMinutes(minutes);
  final hours = (minutes / 60).round();
  if (hours < 24) return s.inHours(hours);
  return s.inDays((hours / 24).round());
}

/// "2:10 PM"
String clockTime(DateTime t) {
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$hour:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// Friendly name for common East African timezones, otherwise the IANA id ("Europe/London").
String timezoneLabel(String timezone) {
  const eastAfrica = {
    'Africa/Mogadishu',
    'Africa/Nairobi',
    'Africa/Addis_Ababa',
    'Africa/Djibouti',
    'Africa/Dar_es_Salaam',
    'Africa/Kampala',
    'Africa/Asmara',
  };
  return eastAfrica.contains(timezone) ? scheduleStrings.eastAfricaTime : timezone.replaceAll('_', ' ');
}
