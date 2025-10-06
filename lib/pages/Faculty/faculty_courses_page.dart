import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:grademate/widgets/bottom_nav_bar.dart';

class FacultyCoursesPage extends StatefulWidget {
  const FacultyCoursesPage({super.key});

  @override
  State<FacultyCoursesPage> createState() => _FacultyCoursesPageState();
}

class _FacultyCoursesPageState extends State<FacultyCoursesPage> {
  int _selectedIndex = 1; // Index for the '2nd Option' tab

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

    if (index == 0) {
      context.go('/faculty_home');
    } else if (index == 1) {
      // Stay on this page
    } else if (index == 2) {
      context.go('/faculty_my_files');
    } else if (index == 3) {
      context.go('/faculty_profile');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            context.go('/faculty_home');
          },
        ),
        title: const Text(
          'Courses',
          style: TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.black),
            onPressed: () {
              // TODO: Implement 'add new course' functionality
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            // Search Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: const TextField(
                decoration: InputDecoration(
                  icon: Icon(Icons.search, color: Colors.grey),
                  hintText: 'Search',
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Course List
            _buildCourseTile(
              Icons.folder_outlined,
              'CSE',
              'Computer Science and Engineering',
            ),
            _buildCourseTile(
              Icons.folder_outlined,
              'CSD',
              'Computer Science and Design',
            ),
            _buildCourseTile(
              Icons.folder_outlined,
              'CSM',
              'Computer Science and Machine Learning',
            ),
            _buildCourseTile(
              Icons.folder_outlined,
              'ECE',
              'Electronics and Communication Engineering',
            ),
            _buildCourseTile(
              Icons.folder_outlined,
              'EEE',
              'Electrical and Electronics Engineering',
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavBar(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
      ),
    );
  }

  Widget _buildCourseTile(IconData icon, String title, String subtitle) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue[800]),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey)),
      trailing: const Icon(Icons.more_horiz),
      onTap: () {
        // TODO: Implement course tile tap action
      },
    );
  }
}