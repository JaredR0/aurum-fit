import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/storage/local_db.dart';
import '../plan/plan_models.dart';

/// Recordatorios 100 % locales (comidas, agua y entrenamiento). No se usa
/// ningún servicio de push en la nube.
///
/// Las horas se programan convirtiendo la hora local a UTC con repetición
/// diaria. En países sin horario de verano (Guatemala, México, Colombia…)
/// es exacto; donde hay cambio de horario puede correrse una hora hasta que
/// se vuelvan a programar (la app reprograma al abrirse).
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const int _mealBase = 100;
  static const int _waterBase = 200;
  static const int _workoutId = 300;
  static const int _checkinId = 400;

  static const String settingsKey = 'reminders';

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_aurum'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings);
    _ready = true;
  }

  /// Permiso de notificaciones en tiempo de ejecución (Android 13+ / iOS).
  static Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    return false;
  }

  static ReminderSettings loadSettings() {
    final j = LocalDb.readJson(LocalDb.settings, settingsKey);
    return j == null ? const ReminderSettings() : ReminderSettings.fromJson(j);
  }

  static Future<void> saveSettings(ReminderSettings s) =>
      LocalDb.writeJson(LocalDb.settings, settingsKey, s.toJson());

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'aurum_reminders',
      'Recordatorios',
      channelDescription: 'Comidas, agua y entrenamiento',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      visibility: NotificationVisibility.private,
    ),
    iOS: DarwinNotificationDetails(),
  );

  /// Reprograma todo según los ajustes y el plan actual.
  static Future<void> reschedule(ReminderSettings s, FitnessPlan? plan) async {
    await init();
    await _plugin.cancelAll();

    if (s.meals && plan != null) {
      final day = plan.nutrition.dayFor(DateTime.now());
      final meals = day?.meals ?? const <Meal>[];
      for (var i = 0; i < meals.length; i++) {
        final m = meals[i];
        await _daily(
          _mealBase + i,
          m.hour,
          m.minute,
          '${m.slot.label} · ${m.kcal} kcal',
          // Texto genérico en la pantalla de bloqueo; el detalle está en la app.
          'Hora de comer según tu plan.',
        );
      }
    }

    if (s.water) {
      var id = _waterBase;
      for (var h = s.waterStartHour; h <= s.waterEndHour; h += s.waterEveryHours) {
        await _daily(id++, h, 0, 'Hidratación', 'Toma un vaso de agua 💧');
      }
    }

    if (s.workout) {
      await _daily(_workoutId, s.workoutHour, s.workoutMinute,
          'Entrenamiento', 'Tu sesión de hoy te espera.');
    }

    if (s.checkin) {
      await _plugin.zonedSchedule(
        _checkinId,
        'Check-in semanal',
        'Cuéntale a Aurum Fit qué lograste esta semana.',
        _nextWeekday(DateTime.saturday, 10, 0),
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  static tz.TZDateTime _nextWeekday(int weekday, int hour, int minute) {
    final now = DateTime.now();
    var local = DateTime(now.year, now.month, now.day, hour, minute);
    while (local.weekday != weekday || !local.isAfter(now)) {
      local = local.add(const Duration(days: 1));
    }
    return tz.TZDateTime.from(local, tz.UTC);
  }

  static Future<void> _daily(
    int id,
    int hour,
    int minute,
    String title,
    String body,
  ) async {
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      _nextInstance(hour, minute),
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static tz.TZDateTime _nextInstance(int hour, int minute) {
    final now = DateTime.now();
    var local = DateTime(now.year, now.month, now.day, hour, minute);
    if (!local.isAfter(now)) local = local.add(const Duration(days: 1));
    return tz.TZDateTime.from(local, tz.UTC);
  }

  static Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }
}

class ReminderSettings {
  const ReminderSettings({
    this.meals = false,
    this.water = false,
    this.workout = false,
    this.checkin = false,
    this.waterStartHour = 8,
    this.waterEndHour = 20,
    this.waterEveryHours = 2,
    this.workoutHour = 18,
    this.workoutMinute = 0,
  });

  final bool meals;
  final bool water;
  final bool workout;
  final bool checkin;
  final int waterStartHour;
  final int waterEndHour;
  final int waterEveryHours;
  final int workoutHour;
  final int workoutMinute;

  bool get any => meals || water || workout || checkin;

  ReminderSettings copyWith({
    bool? meals,
    bool? water,
    bool? workout,
    bool? checkin,
    int? workoutHour,
    int? workoutMinute,
  }) =>
      ReminderSettings(
        meals: meals ?? this.meals,
        water: water ?? this.water,
        workout: workout ?? this.workout,
        checkin: checkin ?? this.checkin,
        waterStartHour: waterStartHour,
        waterEndHour: waterEndHour,
        waterEveryHours: waterEveryHours,
        workoutHour: workoutHour ?? this.workoutHour,
        workoutMinute: workoutMinute ?? this.workoutMinute,
      );

  Map<String, dynamic> toJson() => {
        'meals': meals,
        'water': water,
        'workout': workout,
        'checkin': checkin,
        'waterStartHour': waterStartHour,
        'waterEndHour': waterEndHour,
        'waterEveryHours': waterEveryHours,
        'workoutHour': workoutHour,
        'workoutMinute': workoutMinute,
      };

  factory ReminderSettings.fromJson(Map<String, dynamic> j) {
    int hour(Object? v, int d) => v is int && v >= 0 && v <= 23 ? v : d;
    return ReminderSettings(
      meals: j['meals'] == true,
      water: j['water'] == true,
      workout: j['workout'] == true,
      checkin: j['checkin'] == true,
      waterStartHour: hour(j['waterStartHour'], 8),
      waterEndHour: hour(j['waterEndHour'], 20),
      waterEveryHours: (j['waterEveryHours'] is int &&
              (j['waterEveryHours'] as int) >= 1 &&
              (j['waterEveryHours'] as int) <= 6)
          ? j['waterEveryHours'] as int
          : 2,
      workoutHour: hour(j['workoutHour'], 18),
      workoutMinute: j['workoutMinute'] is int &&
              (j['workoutMinute'] as int) >= 0 &&
              (j['workoutMinute'] as int) < 60
          ? j['workoutMinute'] as int
          : 0,
    );
  }
}
