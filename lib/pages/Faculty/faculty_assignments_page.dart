import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class FacultyAssignmentsPage extends StatefulWidget {
  const FacultyAssignmentsPage({super.key});

  @override
  State<FacultyAssignmentsPage> createState() => _FacultyAssignmentsPageState();
}

class _FacultyAssignmentsPageState extends State<FacultyAssignmentsPage> {
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Navigate to the home page when the back button is pressed
        context.go('/faculty_home');
        // Return false to prevent the default back button action (closing the app)
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/faculty_home'),
          ),
          title: const Text('Assignments'),
          centerTitle: true,
        ),
        body: const Center(
          child: Text(
            'Faculty Assignments Page',
            style: TextStyle(fontSize: 20),
          ),
        ),
      ),
    );
  }
}

