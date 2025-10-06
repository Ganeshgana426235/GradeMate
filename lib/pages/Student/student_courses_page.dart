import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:grademate/widgets/bottom_nav_bar.dart';

class StudentCoursesPage extends StatefulWidget {
  const StudentCoursesPage({super.key});

  @override
  State<StudentCoursesPage> createState() => _StudentCoursesPageState();
}

class _StudentCoursesPageState extends State<StudentCoursesPage> {
  int _selectedIndex = 1; // Index for the '2nd Option' tab

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            context.go('/student_home');
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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

            // Shared with me Section
            const Text(
              'Shared with me',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),

            // Academic Year 2023-2024
            _buildAcademicYearCard(
              'Academic Year 2023-2024',
              'Calculus Notes, Linear Algebra, Differential Equations, Probability Theory',
              [
                _buildCourseTile('Calculus Notes', 'Dr. Eleanor Vance'),
                _buildCourseTile('Linear Algebra', 'Prof. Samuel Harper'),
                _buildCourseTile('Differential Equations', 'Dr. Eleanor Vance'),
                _buildCourseTile('Probability Theory', 'Prof. Samuel Harper'),
              ],
            ),
            const SizedBox(height: 16),

            // Academic Year 2022-2023
            _buildAcademicYearCard(
              'Academic Year 2022-2023',
              'Course 1, Course 2, Course 3',
              [
                _buildCourseTile('Course 1', 'Prof. Jane Doe'),
                _buildCourseTile('Course 2', 'Dr. John Smith'),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavBar(
        selectedIndex: _selectedIndex,
        onItemTapped: (index) {
          if (index == 0) {
            context.go('/student_home');
          } else if (index == 1) {
            // Stay on this page
          } else if (index == 2) {
            context.go('/student_my_files');
          } else if (index == 3) {
            context.go('/student_profile');
          }
        },
      ),
    );
  }

  Widget _buildAcademicYearCard(String year, String courseSummary, List<Widget> courseTiles) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!, width: 1),
      ),
      child: ExpansionTile(
        title: Text(
          year,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          courseSummary,
          style: TextStyle(color: Colors.grey[600]),
        ),
        children: courseTiles,
      ),
    );
  }

  Widget _buildCourseTile(String courseName, String facultyName) {
    return ListTile(
      leading: const Icon(Icons.description_outlined, color: Colors.black54),
      title: Text(courseName),
      subtitle: Text(facultyName, style: TextStyle(color: Colors.grey[600])),
      trailing: const Icon(Icons.more_horiz),
      onTap: () {
        // TODO: Implement course tile tap action
      },
    );
  }
}