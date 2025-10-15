import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:grademate/firebase_options.dart';
import 'package:grademate/providers/auth_provider.dart' as AppAuthProvider;
import 'package:grademate/pages/Authentication/login_page.dart';
import 'package:grademate/pages/Authentication/forgot_password_page.dart';
import 'package:grademate/pages/Authentication/register_page.dart';
import 'package:grademate/pages/Student/student_shell.dart';
import 'package:grademate/pages/Faculty/faculty_shell.dart';
import 'package:grademate/pages/Student/student_home_page.dart';
import 'package:grademate/pages/Student/student_courses_page.dart';
import 'package:grademate/pages/Student/student_profile_page.dart';
import 'package:grademate/pages/Student/student_my_files_page.dart';
import 'package:grademate/pages/Faculty/faculty_home_page.dart';
import 'package:grademate/pages/Faculty/faculty_courses_page.dart';
import 'package:grademate/pages/Faculty/faculty_profile_page.dart';
import 'package:grademate/pages/Faculty/faculty_my_files_page.dart';
import 'package:grademate/widgets/file_details_page.dart';
import 'package:grademate/widgets/file_viewer_page.dart';
import 'package:grademate/models/file_models.dart';
import 'package:grademate/widgets/downloads_page.dart';
import 'package:grademate/widgets/all_activities_page.dart';
import 'package:grademate/widgets/my_notes_page.dart';
import 'package:grademate/widgets/reminders_page.dart';
import 'package:grademate/pages/Faculty/faculty_assignments_page.dart';
import 'package:grademate/pages/Faculty/send_notification_page.dart';
import 'package:grademate/pages/Faculty/manage_students_page.dart';
import 'package:grademate/widgets/notifications_page.dart';
import 'package:grademate/widgets/favorites_page.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// ✅ Add for FlutterQuill localization support
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final _router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/login',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterPage(),
    ),
    GoRoute(
      path: '/forgot_password',
      builder: (context, state) => const ForgotPasswordPage(),
    ),
    GoRoute(
      path: '/notifications',
      builder: (context, state) => const NotificationsPage(),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return StudentShell(navigationShell: navigationShell);
      },
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/student_home',
              builder: (context, state) => const StudentHomePage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/student_courses',
              builder: (context, state) => const StudentCoursesPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/student_my_files',
              builder: (context, state) => const StudentMyFilesPage(),
              routes: [
                GoRoute(
                  path: ':folderId',
                  builder: (context, state) {
                    final folderId = state.pathParameters['folderId'];
                    final folderName = state.extra as String?;
                    return StudentMyFilesPage(
                        folderId: folderId, folderName: folderName);
                  },
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/student_profile',
              builder: (context, state) => const StudentProfilePage(),
            ),
          ],
        ),
      ],
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return FacultyShell(navigationShell: navigationShell);
      },
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/faculty_home',
              builder: (context, state) => const FacultyHomePage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/faculty_courses',
              builder: (context, state) => const FacultyCoursesPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/faculty_my_files',
              builder: (context, state) => const FacultyMyFilesPage(),
              routes: [
                GoRoute(
                  path: ':folderId',
                  builder: (context, state) {
                    final folderId = state.pathParameters['folderId'];
                    final folderName = state.extra as String?;
                    return FacultyMyFilesPage(
                        folderId: folderId, folderName: folderName);
                  },
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/faculty_profile',
              builder: (context, state) => const FacultyProfilePage(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/file_details',
      builder: (context, state) =>
          FileDetailsPage(file: state.extra as FileData),
    ),
    GoRoute(
      path: '/file_viewer',
      builder: (context, state) =>
          FileViewerPage(file: state.extra as FileData),
    ),
    GoRoute(
      path: '/downloads',
      builder: (context, state) => const DownloadsPage(),
    ),
    GoRoute(
      path: '/all_activities',
      builder: (context, state) => const AllActivitiesPage(),
    ),
    GoRoute(
      path: '/my_notes',
      builder: (context, state) => const MyNotesPage(),
    ),
    GoRoute(
      path: '/reminders',
      builder: (context, state) => const RemindersPage(),
    ),
    GoRoute(
      path: '/favorites',
      builder: (context, state) => const FavoritesPage(),
    ),
    GoRoute(
      path: '/faculty_assignments',
      builder: (context, state) => const FacultyAssignmentsPage(),
    ),
    GoRoute(
      path: '/send_notification',
      builder: (context, state) => const SendNotificationPage(),
    ),
    GoRoute(
      path: '/manage_students',
      builder: (context, state) => const ManageStudentsPage(),
    ),
  ],
  redirect: (context, state) {
    final user = FirebaseAuth.instance.currentUser;
    final isAuthenticated = user != null;
    final isVerified = isAuthenticated ? user.emailVerified : false;

    final userBox =
        Hive.isBoxOpen('userBox') ? Hive.box<String>('userBox') : null;
    final role = userBox?.get('role');

    final isAuthPage = [
      '/login',
      '/register',
      '/forgot_password',
      '/',
    ].contains(state.uri.toString());

    if (!isAuthenticated || !isVerified) {
      if (userBox != null) userBox.clear();
      return isAuthPage ? null : '/login';
    }

    if (isAuthPage) {
      if (role == 'Student') {
        return '/student_home';
      } else if (role == 'Faculty') {
        return '/faculty_home';
      }

      if (role == null) {
        FirebaseAuth.instance.signOut();
        if (userBox != null) userBox.clear();
        return '/login';
      }
    }

    return null;
  },
);

void main() async {
  await dotenv.load(fileName: ".env");

  WidgetsFlutterBinding.ensureInitialized();
  await _requestPermissions();

  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

  final appDocumentDir = await getApplicationDocumentsDirectory();
  await Hive.initFlutter(appDocumentDir.path);
  await Hive.openBox<String>('userBox');

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);

  runApp(const MyApp());
}

Future<void> _requestPermissions() async {
  Map<Permission, PermissionStatus> statuses = await [
    Permission.storage,
    Permission.notification,
  ].request();

  print("Storage Permission: ${statuses[Permission.storage]}");
  print("Notification Permission: ${statuses[Permission.notification]}");
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppAuthProvider.AuthProvider()),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        routerConfig: _router,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          fontFamily: 'Roboto',
        ),

        // ✅ Added localization support for FlutterQuill
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          quill.FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en'),
          Locale('hi'),
        ],
      ),
    );
  }
}
