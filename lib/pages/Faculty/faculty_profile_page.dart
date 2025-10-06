import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:grademate/widgets/bottom_nav_bar.dart';

class FacultyProfilePage extends StatefulWidget {
  const FacultyProfilePage({super.key});

  @override
  State<FacultyProfilePage> createState() => _FacultyProfilePageState();
}

class _FacultyProfilePageState extends State<FacultyProfilePage> {
  int _selectedIndex = 3; // Index for the 'Profile' tab

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
          'Edit Profile',
          style: TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            // Profile Image
            const CircleAvatar(
              radius: 60,
              backgroundColor: Colors.grey,
              backgroundImage: NetworkImage('https://placehold.co/120x120/cccccc/000000?text=Faculty'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Dr. Anya Sharma',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const Text(
              'Professor, Computer Science',
              style: TextStyle(
                fontSize: 16,
                color: Colors.blue,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 40),

            // Name Field
            _buildTextField(
              'Name',
              'Dr. Anya Sharma',
              Icons.person_outline,
            ),
            const SizedBox(height: 20),

            // Email Field
            _buildTextField(
              'Email',
              'anya.sharma@example.com',
              Icons.email_outlined,
            ),
            const SizedBox(height: 20),

            // Phone Number Field
            _buildTextField(
              'Phone Number',
              'Enter your phone number',
              Icons.phone_android_outlined,
            ),
            const SizedBox(height: 20),

            // Designation Field for Faculty
            _buildTextField(
              'Designation',
              'e.g., Professor, Computer Science',
              Icons.work_outline,
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavBar(
        selectedIndex: _selectedIndex,
        onItemTapped: (index) {
          if (index == 0) {
            context.go('/faculty_home');
          } else if (index == 1) {
            context.go('/faculty_courses');
          } else if (index == 2) {
             context.go('/faculty_my_files');
          } else if (index == 3) {
            // Stay on this page
          }
        },
      ),
    );
  }

  Widget _buildTextField(String label, String hint, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            readOnly: true, // Placeholder fields
            decoration: InputDecoration(
              hintText: hint,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              prefixIcon: Icon(icon, color: Colors.grey),
            ),
          ),
        ),
      ],
    );
  }
}