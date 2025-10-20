import 'package:flutter/material.dart';

class StudentAssignmentPage extends StatelessWidget {
  const StudentAssignmentPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Assignments',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF87CEEB), // Light Blue
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icon representing a task or document
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF87CEEB).withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.assignment_turned_in_outlined,
                  size: 80,
                  color: Color(0xFF4682B4), // Steel Blue
                ),
              ),
              const SizedBox(height: 40),
              
              // Primary Message
              const Text(
                'No Active Assignments Found',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              
              // Instructional Text
              Text(
                'Please ask your faculty members to upload the assignments for your current branch and year. Check back later!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 60),

              // Decorative Button (Placeholder for refresh or navigation)
              OutlinedButton.icon(
                onPressed: () {
                  // Placeholder action - e.g., trigger a refresh or show a message
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Simulating assignment check...')),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4682B4),
                  side: const BorderSide(color: Color(0xFF4682B4), width: 1.5),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.refresh),
                label: const Text(
                  'Refresh List',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
