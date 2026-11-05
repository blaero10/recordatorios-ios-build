import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );
  runApp(const RecordatoriosFlutterApp());
}

class BibleVerse {
  final String bookName;
  final int chapter;
  final int verseNumber;
  final String text;
  final int globalIndex;

  const BibleVerse({
    required this.bookName,
    required this.chapter,
    required this.verseNumber,
    required this.text,
    required this.globalIndex,
  });

  String get reference => '$bookName $chapter:$verseNumber';
}

class AlarmItem {
  final int id;
  final TimeOfDay time;
  final String label;
  final bool enabled;

  const AlarmItem({
    required this.id,
    required this.time,
    this.label = 'Promesa y versículo',
    this.enabled = true,
  });

  AlarmItem copyWith({TimeOfDay? time, bool? enabled}) {
    return AlarmItem(
      id: id,
      time: time ?? this.time,
      label: label,
      enabled: enabled ?? this.enabled,
    );
  }

  String get formatted12h {
    final h = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final m = time.minute.toString().padLeft(2, '0');
    return '${h.toString().padLeft(2, '0')}:$m';
  }

  String get periodLabel => time.period == DayPeriod.am ? 'a. m.' : 'p. m.';
}

class RecordatoriosFlutterApp extends StatelessWidget {
  const RecordatoriosFlutterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Recordatorios',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF080D16),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFD4AF37),
          secondary: Color(0xFFFDE68A),
          surface: Color(0xFF111826),
        ),
        useMaterial3: true,
      ),
      home: const RecordatoriosHomeScreen(),
    );
  }
}

class RecordatoriosHomeScreen extends StatefulWidget {
  const RecordatoriosHomeScreen({super.key});

  @override
  State<RecordatoriosHomeScreen> createState() =>
      _RecordatoriosHomeScreenState();
}

class _RecordatoriosHomeScreenState extends State<RecordatoriosHomeScreen> {
  static const MethodChannel _nativeChannel =
      MethodChannel('com.jose.recordatorios/native_alerts');

  final Random _random = Random();
  List<BibleVerse> _allVerses = const [
    BibleVerse(
      bookName: 'Jeremías',
      chapter: 29,
      verseNumber: 11,
      text:
          'Porque yo sé los pensamientos que tengo acerca de vosotros, dice Jehová, pensamientos de paz, y no de mal, para daros el fin que esperáis.',
      globalIndex: 19647,
    ),
    BibleVerse(
      bookName: 'Josué',
      chapter: 1,
      verseNumber: 9,
      text:
          'Mira que te mando que te esfuerces y seas valiente; no temas ni desmayes, porque Jehová tu Dios estará contigo en dondequiera que vayas.',
      globalIndex: 5861,
    ),
  ];

  late BibleVerse _currentVerse;
  String _promiseText =
      'Dios cumplirá Su propósito en mi vida; Su promesa permanece fiel y nunca me dejará.';
  String _promiseRef = 'Salmos 138:8 • Mi Promesa Personal';

  bool _autoReminderEnabled = true;
  bool _powerDetectorEnabled = true;
  bool _wakeScreenWhenOff = true;
  bool _showOverOtherApps = true;
  int _requiredPresses = 6;
  int _customHours = 0;
  int _customMinutes = 45;
  Timer? _periodicTimer;

  List<AlarmItem> _alarms = [
    const AlarmItem(
      id: 1,
      time: TimeOfDay(hour: 8, minute: 0),
      label: 'Promesa de la mañana',
      enabled: true,
    ),
    const AlarmItem(
      id: 2,
      time: TimeOfDay(hour: 21, minute: 30),
      label: 'Promesa de la noche',
      enabled: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _currentVerse = _allVerses.first;
    _loadOfflineBible();
    _restartPeriodicTimer();
  }

  @override
  void dispose() {
    _periodicTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadOfflineBible() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/biblia_rvr1960.json');
      final List<dynamic> books = json.decode(jsonStr) as List<dynamic>;
      final List<BibleVerse> parsed = [];
      int index = 1;
      for (final b in books) {
        final map = b as Map<String, dynamic>;
        final name = (map['name'] as String?) ?? 'Libro';
        final chapters = (map['chapters'] as List<dynamic>?) ?? const [];
        for (int c = 0; c < chapters.length; c++) {
          final verses = chapters[c] as List<dynamic>;
          for (int v = 0; v < verses.length; v++) {
            parsed.add(
              BibleVerse(
                bookName: name,
                chapter: c + 1,
                verseNumber: v + 1,
                text: verses[v].toString(),
                globalIndex: index++,
              ),
            );
          }
        }
      }
      if (parsed.isNotEmpty && mounted) {
        setState(() {
          _allVerses = parsed;
          _currentVerse = parsed[_random.nextInt(parsed.length)];
        });
      }
    } catch (_) {}
  }

  void _pickRandomVerse() {
    HapticFeedback.lightImpact();
    setState(() {
      _currentVerse = _allVerses[_random.nextInt(_allVerses.length)];
    });
  }

  void _restartPeriodicTimer() {
    _periodicTimer?.cancel();
    if (!_autoReminderEnabled) return;
    final totalMinutes = max(1, _customHours * 60 + _customMinutes);
    _periodicTimer = Timer.periodic(Duration(minutes: totalMinutes), (_) {
      if (_autoReminderEnabled && mounted) {
        _triggerFullScreenAlert('Recordatorio automático');
      }
    });
    _syncNativeService();
  }

  Future<void> _syncNativeService() async {
    try {
      await _nativeChannel.invokeMethod('updateConfig', {
        'promiseText': _promiseText,
        'promiseRef': _promiseRef,
        'autoReminderEnabled': _autoReminderEnabled,
        'intervalMinutes': max(1, _customHours * 60 + _customMinutes),
        'wakeScreenWhenOff': _wakeScreenWhenOff,
        'showOverOtherApps': _showOverOtherApps,
        'powerDetectorEnabled': _powerDetectorEnabled,
        'requiredPresses': _requiredPresses,
      });
    } catch (_) {}
  }

  void _triggerFullScreenAlert(String source) {
    HapticFeedback.heavyImpact();
    final alertVerse = _allVerses[_random.nextInt(_allVerses.length)];
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, __, ___) => FullScreenPromiseAlertDialog(
          promiseText: _promiseText,
          promiseRef: _promiseRef,
          initialVerse: alertVerse,
          sourceLabel: source,
          onPickAnotherVerse: () =>
              _allVerses[_random.nextInt(_allVerses.length)],
        ),
      ),
    );
  }

  Future<void> _pickAlarmTime({AlarmItem? existing}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: existing?.time ?? const TimeOfDay(hour: 7, minute: 30),
    );
    if (picked == null) return;
    setState(() {
      if (existing != null) {
        _alarms = _alarms
            .map((a) =>
                a.id == existing.id ? a.copyWith(time: picked, enabled: true) : a)
            .toList();
      } else {
        _alarms = [
          ..._alarms,
          AlarmItem(
            id: DateTime.now().millisecondsSinceEpoch,
            time: picked,
            enabled: true,
          ),
        ];
      }
    });
    _syncNativeService();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 360;
            final padX = isCompact ? 12.0 : 18.0;
            final cardPad = isCompact ? 14.0 : 18.0;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: ListView(
                  padding:
                      EdgeInsets.symmetric(horizontal: padX, vertical: 12.0),
                  children: [
                    // Encabezado limpio con la Cruz Latina y "Recordatorios"
                    Column(
                      children: [
                        Image.asset(
                          'assets/img_cross_emblem.png',
                          width: isCompact ? 42 : 48,
                          height: isCompact ? 42 : 48,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Recordatorios',
                          style: TextStyle(
                            fontFamily: 'Georgia',
                            fontSize: isCompact ? 21 : 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Reina-Valera 1960 • ${_allVerses.length} versículos',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // 1. Tarjeta de Versículo Aleatorio
                    Container(
                      padding: EdgeInsets.all(cardPad),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111927),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Versículo aleatorio',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFFDE68A),
                                ),
                              ),
                              Text(
                                '${_currentVerse.globalIndex} / ${_allVerses.length}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            '«${_currentVerse.text}»',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Georgia',
                              fontStyle: FontStyle.italic,
                              fontSize: isCompact ? 16 : 18,
                              height: 1.45,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _currentVerse.reference,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD4AF37),
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: ElevatedButton(
                              onPressed: _pickRandomVerse,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFD4AF37),
                                foregroundColor: const Color(0xFF140E00),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(11),
                                ),
                              ),
                              child: const Text(
                                'Cambiar versículo',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 2. Alarmas y Recordatorios (Android & iPhone)
                    Container(
                      padding: EdgeInsets.all(cardPad),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111826),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Alarmas y recordatorios',
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      'Elige cualquier hora o tiempo libre',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _StatusBadge(active: _autoReminderEnabled),
                              const SizedBox(width: 6),
                              CupertinoSwitch(
                                value: _autoReminderEnabled,
                                activeTrackColor: const Color(0xFFD4AF37),
                                onChanged: (v) {
                                  setState(() => _autoReminderEnabled = v);
                                  _restartPeriodicTimer();
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ..._alarms.map(
                            (alarm) => Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: InkWell(
                                onTap: () => _pickAlarmTime(existing: alarm),
                                borderRadius: BorderRadius.circular(13),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF172031),
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.baseline,
                                            textBaseline:
                                                TextBaseline.alphabetic,
                                            children: [
                                              Text(
                                                alarm.formatted12h,
                                                style: TextStyle(
                                                  fontSize: isCompact ? 22 : 26,
                                                  fontWeight: FontWeight.w600,
                                                  color: alarm.enabled &&
                                                          _autoReminderEnabled
                                                      ? Colors.white
                                                      : const Color(0xFF64748B),
                                                ),
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                alarm.periodLabel,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF94A3B8),
                                                ),
                                              ),
                                            ],
                                          ),
                                          Text(
                                            alarm.label,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF64748B),
                                            ),
                                          ),
                                        ],
                                      ),
                                      CupertinoSwitch(
                                        value: alarm.enabled &&
                                            _autoReminderEnabled,
                                        activeTrackColor:
                                            const Color(0xFFD4AF37),
                                        onChanged: (checked) {
                                          setState(() {
                                            _alarms = _alarms
                                                .map((a) => a.id == alarm.id
                                                    ? a.copyWith(
                                                        enabled: checked)
                                                    : a)
                                                .toList();
                                          });
                                          _syncNativeService();
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () => _pickAlarmTime(),
                              child: const Text(
                                '+ Agregar alarma a cualquier hora',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 3. Botón Físico (Android Botón Apagado / iPhone Botón de Acción o Toque Posterior)
                    Container(
                      padding: EdgeInsets.all(cardPad),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111826),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Botón físico de apagado',
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      'Android (6 toques) • iPhone (Toque posterior)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _StatusBadge(active: _powerDetectorEnabled),
                              const SizedBox(width: 6),
                              CupertinoSwitch(
                                value: _powerDetectorEnabled,
                                activeTrackColor: const Color(0xFFD4AF37),
                                onChanged: (v) {
                                  setState(() => _powerDetectorEnabled = v);
                                  _syncNativeService();
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => _triggerFullScreenAlert(
                                'Vista previa pantalla completa',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1E2D44),
                                foregroundColor: Colors.white,
                              ),
                              child: const Text(
                                'Probar alerta en pantalla completa',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool active;
  const _StatusBadge({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFF0F2922)
            : const Color(0xFF1E2430),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Text(
        active ? 'ACTIVO' : 'APAGADO',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: active
              ? const Color(0xFF6EE7B7)
              : const Color(0xFF94A3B8),
        ),
      ),
    );
  }
}

class FullScreenPromiseAlertDialog extends StatefulWidget {
  final String promiseText;
  final String promiseRef;
  final BibleVerse initialVerse;
  final String sourceLabel;
  final BibleVerse Function() onPickAnotherVerse;

  const FullScreenPromiseAlertDialog({
    super.key,
    required this.promiseText,
    required this.promiseRef,
    required this.initialVerse,
    required this.sourceLabel,
    required this.onPickAnotherVerse,
  });

  @override
  State<FullScreenPromiseAlertDialog> createState() =>
      _FullScreenPromiseAlertDialogState();
}

class _FullScreenPromiseAlertDialogState
    extends State<FullScreenPromiseAlertDialog> {
  late BibleVerse _verse;

  @override
  void initState() {
    super.initState();
    _verse = widget.initialVerse;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xF5060D18),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                children: [
                  Image.asset(
                    'assets/img_cross_emblem.png',
                    width: 52,
                    height: 52,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.sourceLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFDE68A),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Recuerda Tu Promesa',
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131E30),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Mi promesa recordada',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFD4AF37),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '“${widget.promiseText}”',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Georgia',
                            fontSize: 16,
                            height: 1.4,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.promiseRef,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFDE68A),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E1624),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Versículo aleatorio',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF93C5FD),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '«${_verse.text}»',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Georgia',
                            fontStyle: FontStyle.italic,
                            fontSize: 17,
                            height: 1.45,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _verse.reference,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFD4AF37),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() => _verse = widget.onPickAnotherVerse());
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD4AF37),
                        foregroundColor: const Color(0xFF140E00),
                      ),
                      child: const Text(
                        'Otro versículo aleatorio',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cerrar alerta'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
