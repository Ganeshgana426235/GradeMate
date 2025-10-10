import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart'; // [ADDED]
import 'package:hive_flutter/hive_flutter.dart';    // [ADDED]

import 'package:grademate/firebase_options.dart';
import 'package:grademate/providers/auth_provider.dart' as AppAuthProvider;
import 'package:grademate/pages/Authentication/login_page.dart';
import 'package:grademate/pages/Authentication/forgot_password_page.dart';
import 'package:grademate/pages/Authentication/register_page.dart';
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

final _router = GoRouter(
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
      path: '/student_home',
      builder: (context, state) => const StudentHomePage(),
    ),
    GoRoute(
      path: '/student_courses',
      builder: (context, state) => const StudentCoursesPage(),
    ),
    GoRoute(
      path: '/student_my_files',
      builder: (context, state) => const MyFilesPage(),
      routes: [
        GoRoute(
          path: ':folderId',
          builder: (context, state) {
            final folderId = state.pathParameters['folderId'];
            final folderName = state.extra as String?;
            return MyFilesPage(folderId: folderId, folderName: folderName);
          },
        ),
      ],
    ),
    GoRoute(
      path: '/student_profile',
      builder: (context, state) => const StudentProfilePage(),
    ),
    GoRoute(
      path: '/faculty_home',
      builder: (context, state) => const FacultyHomePage(),
    ),
    GoRoute(
      path: '/faculty_courses',
      builder: (context, state) => const FacultyCoursesPage(),
    ),
    GoRoute(
      path: '/faculty_my_files',
      builder: (context, state) => const FacultyMyFilesPage(),
      routes: [
        GoRoute(
          path: ':folderId',
          builder: (context, state) {
            final folderId = state.pathParameters['folderId'];
            final folderName = state.extra as String?;
            return FacultyMyFilesPage(folderId: folderId, folderName: folderName);
          },
        ),
      ],
    ),
    GoRoute(
      path: '/faculty_profile',
      builder: (context, state) => const FacultyProfilePage(),
    ),
    GoRoute(
      path: '/file_details',
      builder: (context, state) => FileDetailsPage(file: state.extra as FileData),
    ),
    GoRoute(
      path: '/file_viewer',
      builder: (context, state) => FileViewerPage(file: state.extra as FileData),
    ),
  ],
  redirect: (context, state) {
    final user = FirebaseAuth.instance.currentUser;
    final isAuthenticated = user != null;
    final isVerified = isAuthenticated ? user.emailVerified : false; 
    
    // Check if Hive box is open, get role
    final userBox = Hive.isBoxOpen('userBox') ? Hive.box<String>('userBox') : null; 
    final role = userBox?.get('role');

    final isAuthPage = [
      '/login',
      '/register',
      '/forgot_password',
      '/',
    ].contains(state.uri.toString());

    // 1. Not logged in OR Not verified: Must go to auth pages.
    if (!isAuthenticated || !isVerified) {
      // Clear local storage if we end up here to ensure a fresh start
      if (userBox != null) userBox.clear();
      return isAuthPage ? null : '/login';
    }

    // 2. Logged in and verified: Redirect away from auth pages to their respective home page.
    if (isAuthPage) {
      if (role == 'Student') {
        return '/student_home';
      } else if (role == 'Faculty') {
        return '/faculty_home';
      }
      
      // Fallback if local role is missing despite Firebase login, force relogin
      if (role == null) {
          // Firebase sign out removes the Firebase user object, forcing redirect back to /login on next check
          FirebaseAuth.instance.signOut(); 
          if (userBox != null) userBox.clear();
          return '/login';
      }
    }

    // 3. Allow navigation (e.g., already on /student_home, or accessing /file_details)
    return null;
  },
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // [START HIVE INITIALIZATION]
  final appDocumentDir = await getApplicationDocumentsDirectory();
  await Hive.initFlutter(appDocumentDir.path);
  // Opens the box for string data storage
  await Hive.openBox<String>('userBox'); 
  // [END HIVE INITIALIZATION]
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
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
      ),
    );
  }
}