import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/auth_store.dart';
import 'core/blocker.dart';
import 'core/prefs.dart';
import 'features/admin/admin_home.dart';
import 'features/admin/media_page.dart';
import 'features/admin/student_detail_page.dart';
import 'features/auth/login_page.dart';
import 'features/blocker/blocker_page.dart';
import 'features/blocker/permissions_page.dart';
import 'features/blocker/schedule_editor_page.dart';
import 'features/focus_room/focus_room_page.dart';
import 'features/intro/intro_page.dart';
import 'features/music/music_page.dart';
import 'features/plan/plan_week_page.dart';
import 'features/report/nightly_report_flow.dart';
import 'features/settings/settings_page.dart';
import 'features/shell.dart';
import 'features/stats/stats_page.dart';
import 'features/today/today_page.dart';
import 'theme/motion.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final role = ref.watch(authProvider.select((s) => s?.role));
  final rootKey = GlobalKey<NavigatorState>();
  return GoRouter(
    navigatorKey: rootKey,
    initialLocation:
        role == null ? (Prefs.introSeen ? '/login' : '/intro') : (role == 'admin' ? '/admin' : '/today'),
    redirect: (ctx, st) {
      final loc = st.matchedLocation;
      if (role == null) {
        if (loc == '/intro' && !Prefs.introSeen) return null;
        return loc == '/login' ? null : '/login';
      }
      if (loc == '/login' || loc == '/intro') return role == 'admin' ? '/admin' : '/today';
      if (role == 'admin' && !loc.startsWith('/admin')) return '/admin';
      if (role == 'student' && loc.startsWith('/admin')) return '/today';
      return null;
    },
    routes: [
      GoRoute(path: '/intro', pageBuilder: (_, s) => fadePage(s, const IntroPage())),
      GoRoute(path: '/login', pageBuilder: (_, s) => fadePage(s, const LoginPage())),
      ShellRoute(
        builder: (_, __, child) => StudentShell(child: child),
        routes: [
          // تعویض تب: محو شدن نرم داخل Navigator خودِ شل (بدون ریسک GlobalKey تکراری)
          GoRoute(path: '/today', pageBuilder: (_, s) => fadePage(s, const TodayPage())),
          GoRoute(path: '/stats', pageBuilder: (_, s) => fadePage(s, const StatsPage())),
          GoRoute(path: '/plan', pageBuilder: (_, s) => fadePage(s, const PlanWeekPage())),
          GoRoute(path: '/music', pageBuilder: (_, s) => fadePage(s, const MusicPage())),
          GoRoute(
              path: '/settings', pageBuilder: (_, s) => fadePage(s, const SettingsPage())),
        ],
      ),
      GoRoute(
        path: '/focus',
        parentNavigatorKey: rootKey,
        pageBuilder: (_, s) => fadePage(
            s,
            FocusRoomPage(
              part: s.uri.queryParameters['part'] ?? '',
              subject: s.uri.queryParameters['subject'] ?? '',
            )),
      ),
      GoRoute(
          path: '/report',
          parentNavigatorKey: rootKey,
          pageBuilder: (_, s) => fadePage(s, const NightlyReportFlow())),
      GoRoute(
          path: '/blocker', parentNavigatorKey: rootKey, pageBuilder: (_, s) => fadePage(s, const BlockerPage())),
      GoRoute(
          path: '/blocker/edit',
          parentNavigatorKey: rootKey,
          pageBuilder: (_, s) => fadePage(
              s, ScheduleEditorPage(initial: s.extra is BlockSchedule ? s.extra as BlockSchedule : null))),
      GoRoute(
          path: '/blocker/permissions',
          parentNavigatorKey: rootKey,
          pageBuilder: (_, s) => fadePage(s, const BlockerPermissionsPage())),
      GoRoute(path: '/admin', pageBuilder: (_, s) => fadePage(s, const AdminHome())),
      GoRoute(
          path: '/admin/student/:id',
          pageBuilder: (_, s) => fadePage(s, StudentDetailPage(id: s.pathParameters['id']!))),
      GoRoute(path: '/admin/media', pageBuilder: (_, s) => fadePage(s, const MediaPage())),
    ],
  );
});
