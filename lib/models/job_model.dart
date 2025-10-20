// job_model.dart

class JobModel {
  final String eligibility;
  final String experience;
  final String jobDescription;
  final String jobTitle;
  final String jobType;
  final String lastDateToApply;
  final String linkToApply;
  final String location;
  final String recruiter;
  final String salary;
  final String uploadedTime;
  final String workMode;

  JobModel({
    required this.eligibility,
    required this.experience,
    required this.jobDescription,
    required this.jobTitle,
    required this.jobType,
    required this.lastDateToApply,
    required this.linkToApply,
    required this.location,
    required this.recruiter,
    required this.salary,
    required this.uploadedTime,
    required this.workMode,
  });

  // Factory constructor to create a JobModel from a Firebase document map
  factory JobModel.fromMap(Map<String, dynamic> data) {
    return JobModel(
      eligibility: data['eligibility'] ?? 'N/A',
      experience: data['experience'] ?? 'Fresher',
      jobDescription: data['jobDescription'] ?? 'No description provided.',
      jobTitle: data['jobTitle'] ?? 'Job Title Not Specified',
      jobType: data['jobType'] ?? 'Full-Time',
      lastDateToApply: data['lastDateToApply'] ?? 'No Deadline',
      linkToApply: data['linkToApply'] ?? '#',
      location: data['location'] ?? 'Anywhere',
      recruiter: data['recruiter'] ?? 'Confidential',
      salary: data['salary'] ?? 'Not Disclosed',
      uploadedTime: data['uploadedTime'] ?? 'Unknown',
      workMode: data['workMode'] ?? 'WFO',
    );
  }
}