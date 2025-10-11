import 'package:flutter/material.dart';

class StudentProfilePage extends StatefulWidget {
  const StudentProfilePage({super.key});

  @override
  State<StudentProfilePage> createState() => _StudentProfilePageState();
}

class _StudentProfilePageState extends State<StudentProfilePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
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
              backgroundImage: NetworkImage(
                  'https://placehold.co/120x120/cccccc/000000?text=Student'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Your Name',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const Text(
              'Student',
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
              'Your Name',
              Icons.person_outline,
            ),
            const SizedBox(height: 20),

            // Email Field
            _buildTextField(
              'Email',
              'your.email@example.com',
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

            // Branch Field for Student
            _buildTextField(
              'Branch',
              'e.g., Computer Science',
              Icons.school_outlined,
            ),
          ],
        ),
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
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              prefixIcon: Icon(icon, color: Colors.grey),
            ),
          ),
        ),
      ],
    );
  }
}