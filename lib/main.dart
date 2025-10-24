// main.dart (CORRECTED)
import 'package:flutter/material.dart';
import 'package:grademate/pages/Faculty/faculty_chat_page.dart';
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
import 'package:grademate/pages/Student/student_ai_page.dart';
import 'package:grademate/pages/Faculty/faculty_home_page.dart';
import 'package:grademate/pages/Faculty/faculty_courses_page.dart';
import 'package:grademate/pages/Faculty/faculty_ai_page.dart';
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
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:grademate/pages/Student/job_updates_page.dart';
import 'package:grademate/pages/Student/student_chat_page.dart';
import 'package:grademate/pages/Student/student_assignment_page.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:async'; // CRITICAL IMPORT for runZonedGuarded

// [NEW FCM BACKGROUND HANDLER]
/// Must be a top-level function, cannot be a method of a class.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // CRITICAL: Initialize Firebase in the background handler
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  print("Handling a background message: ${message.messageId}");
  
  // Note: The system automatically displays the notification if the payload
  // contains 'notification' data and the channel ID is correctly referenced.
}

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
    GoRoute(
      path: '/job_updates', // The new route path
      builder: (context, state) => const JobUpdatesPage(),
    ),
    GoRoute(
      path: '/student_chat', // The new route path
      builder: (context, state) => const StudentChatPage(),
    ),
    GoRoute(
      path: '/faculty_chat', // The new route path
      builder: (context, state) => const FacultyChatPage(),
    ),
    GoRoute(
      path: '/student_assignments', // The new route path
      builder: (context, state) => const StudentAssignmentPage(),
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
        // **CRITICAL CHANGE HERE**
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/student_ai',
              builder: (context, state) {
                // This allows the AI page to receive the file object
                final file = state.extra as FileData?;
                return StudentAIPage(initialFile: file);
              },
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
              path: '/faculty_ai',
              builder: (context, state) {
                // This allows the AI page to receive the file object
                final file = state.extra as FileData?;
                return FacultyAIPage(initialFile: file);
              },
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

// Define the permanent notification channel details for Android
const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'new_file_channel', // ID: This must be the same ID used in flutterLocalNotificationsPlugin.show()
  'New Content Uploads', // Name
  description: 'Notifications for new course materials and file uploads.', // Description
  importance: Importance.high,
);

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _setupFCM() async {
  // 1. Initialize background handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // 2. Initialize the Notification Channel (Mandatory for Android 8.0+)
  // CRITICAL FIX: Ensure the channel is created for both foreground and background
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);


  // 3. Local notification setup for foreground messages (Android/iOS requires this)
  // CRITICAL: Use the resource name '@drawable/notification_icon'
  const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@drawable/notification_icon'); 
    
  // NOTE: Added the handler for notification tap
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse notificationResponse) {
      // Handle when the user taps on the notification banner
      print('Notification tapped with payload: ${notificationResponse.payload}');
      // Here you can navigate the user using the router based on payload data.
    },
  );

  // 4. Foreground message listener (Shows a local notification when app is open)
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('Got a message whilst in the foreground!');
    print('Message data: ${message.data}');

    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id, // CRITICAL FIX: Use the defined channel ID for the foreground notification
            channel.name,
            channelDescription: channel.description,
            // CRITICAL FIX: Explicitly reference the custom small icon from Android resources
            icon: '@drawable/notification_icon', 
          ),
        ),
      );
    }
  });

  // 5. Handle notification tap (if app is closed/in background and user taps banner)
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print('A new onMessageOpenedApp event was published!');
    final route = message.data[
        'route']; // Example: Get a custom route from the data payload
    if (route != null) {
      // Use the router to navigate here
      // _router.go(route);
    }
  });
}

// CRITICAL FIX: Wrapped the initialization in runZonedGuarded
void main() {
  runZonedGuarded<Future<void>>(() async {
    await dotenv.load(fileName: ".env");

    // --- START ADMOB INITIALIZATION ---
    WidgetsFlutterBinding.ensureInitialized();
    // 1. Initialize the Google Mobile Ads SDK (Required for banner/interstitial)
    MobileAds.instance.initialize();
    // --- END ADMOB INITIALIZATION ---

    await _requestPermissions();

    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

    final appDocumentDir = await getApplicationDocumentsDirectory();
    await Hive.initFlutter(appDocumentDir.path);
    await Hive.openBox<String>('userBox');

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // [NEW] Setup FCM handlers right after Firebase initialization
    await _setupFCM();

    FirebaseFirestore.instance.settings =
        const Settings(persistenceEnabled: true);

    runApp(const MyApp());
  }, (error, stack) {
    // This is the global crash handler. If an error occurs during startup,
    // it will be printed here, allowing the app to potentially continue or
    // display a simple error screen instead of a blank one.
    print('GLOBAL ERROR CAUGHT: $error');
  });
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
