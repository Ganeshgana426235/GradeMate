// lib/models/college_data.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class CollegeData {
  final String id; // Firestore Document ID for the college
  final String name; // Short, unique name (e.g., "mlritm")
  final String fullName; // Full display name (e.g., "Malla Reddy Institute of Technology and Management")
  final String emailDomain; // Email domain (e.g., "@mlritm.ac.in")
  final String? code; // Code is optional, used for student roll no validation (e.g., "ce" for 21CE123)
  final List<String> branches;
  final List<String> regulations;
  final List<String> courseYear; // Renamed from 'years' to 'courseYear'

  CollegeData({
    required this.id,
    required this.name,
    required this.fullName,
    required this.emailDomain,
    this.code,
    this.branches = const [],
    this.regulations = const [],
    this.courseYear = const [], // Initialized as empty list
  });

  // Factory constructor to create a CollegeData from a Firestore document
  factory CollegeData.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CollegeData(
      id: doc.id,
      name: (data['name'] as String? ?? '').trim().toLowerCase(),
      fullName: (data['fullName'] as String? ?? '').trim(),
      emailDomain: (data['emailDomain'] as String? ?? '').trim().toLowerCase(),
      code: (data['code'] as String?)?.trim().toLowerCase(),
      // Ensure these are correctly cast from List<dynamic> to List<String>
      branches: List<String>.from(data['branches']?.map((b) => (b as String).trim().toLowerCase()) ?? []),
      regulations: List<String>.from(data['regulations']?.map((r) => (r as String).trim().toLowerCase()) ?? []),
      courseYear: List<String>.from(data['courseYear']?.map((y) => (y as String).trim()) ?? []),
    );
  }

  // Method to convert CollegeData to a Firestore-compatible map
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'fullName': fullName,
      'emailDomain': emailDomain,
      'code': code,
      'branches': branches,
      'regulations': regulations,
      'courseYear': courseYear,
    };
  }
}