import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:math';

class RemindersPage extends StatefulWidget {
  const RemindersPage({super.key});

  @override
  State<RemindersPage> createState() => _RemindersPageState();
}

// FIX: Add WidgetsBindingObserver to listen for app lifecycle changes
class _RemindersPageState extends State<RemindersPage> with WidgetsBindingObserver {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _userRole;

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final FlutterTts flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    // FIX: Add observer
    WidgetsBinding.instance.addObserver(this);
    _fetchUserRole();
    _initializeNotifications();
  }

  @override
  void dispose() {
    // FIX: Remove observer
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // FIX: New method to re-check permissions when user returns to the app
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _requestPermissions(); // Re-check permissions on resume
    }
  }

  /// ✅ Initializes local notifications and requests all necessary permissions.
  Future<void> _initializeNotifications() async {
    try {
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    } catch (e) {
      print("Error initializing timezone: $e");
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings();

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    );

    await _requestPermissions();
  }
  
  /// ✅ Handles all permission requests using permission_handler
  Future<void> _requestPermissions() async {
    // 1. Standard Notification Permission
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    // 2. Exact Alarm Permission
    var alarmStatus = await Permission.scheduleExactAlarm.status;
    if (alarmStatus.isDenied) {
      if (mounted) {
        await _showPermissionDialog(
          title: 'Alarm Permission Needed',
          content: 'To ensure your reminders are perfectly on time, this app needs the "Alarms & Reminders" permission. Please tap "Open Settings" and enable it.',
        );
      }
    }
  }

  /// ✅ Explains why the permission is needed and sends user to settings.
  Future<void> _showPermissionDialog({
      required String title,
      required String content}) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(content),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Open Settings'),
              onPressed: () async {
                  await openAppSettings();
                  Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }


  /// ✅ Handles notification taps. When tapped, it will speak the reminder description.
  void onDidReceiveNotificationResponse(NotificationResponse response) async {
    if (response.payload != null && response.payload!.isNotEmpty) {
      await flutterTts.setPitch(1.0);
      await flutterTts.speak("Reminder: ${response.payload!}");
    }
  }

  Future<void> _fetchUserRole() async {
    final user = _auth.currentUser;
    if (user != null && user.email != null) {
      try {
        final doc = await _firestore.collection('users').doc(user.email).get();
        if (mounted && doc.exists) {
          setState(() {
            _userRole = doc.data()?['role'];
          });
        }
      } catch (e) {
        print('Error fetching user role: $e');
      }
    }
  }

  void _navigateBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      if (_userRole == 'Faculty') {
        context.go('/faculty_home');
      } else if (_userRole == 'Student') {
        context.go('/student_home');
      } else {
        context.go('/login');
      }
    }
  }

  Future<void> _showReminderDialog({DocumentSnapshot? reminderDoc}) async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    DateTime? selectedDate;
    TimeOfDay? selectedTime;
    String recurrence = 'Once';

    if (reminderDoc != null) {
      final data = reminderDoc.data() as Map<String, dynamic>;
      titleController.text = data['title'];
      descriptionController.text = data['description'];
      final reminderTime = (data['reminderTime'] as Timestamp).toDate();
      selectedDate = reminderTime;
      selectedTime = TimeOfDay.fromDateTime(reminderTime);
      recurrence = data['recurrence'] ?? 'Once';
    }

    return showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(reminderDoc == null ? 'New Reminder' : 'Edit Reminder'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'Reminder Title'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(labelText: 'Description'),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            selectedDate == null
                                ? 'No date chosen'
                                : DateFormat('yMd').format(selectedDate!),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: selectedDate ?? DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate: DateTime(2100),
                            );
                            if (date != null) {
                              setDialogState(() => selectedDate = date);
                            }
                          },
                          child: const Text('Choose Date'),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            selectedTime == null
                                ? 'No time chosen'
                                : selectedTime!.format(context),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final time = await showTimePicker(
                              context: context,
                              initialTime: selectedTime ?? TimeOfDay.now(),
                            );
                            if (time != null) {
                              setDialogState(() => selectedTime = time);
                            }
                          },
                          child: const Text('Choose Time'),
                        ),
                      ],
                    ),
                    DropdownButtonFormField<String>(
                      value: recurrence,
                      items: ['Once', 'Daily', 'Weekly', 'Monthly']
                          .map((label) => DropdownMenuItem(
                                value: label,
                                child: Text(label),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => recurrence = value);
                        }
                      },
                      decoration: const InputDecoration(labelText: 'Repeat'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async { // Make async
                    if (titleController.text.isNotEmpty &&
                        descriptionController.text.isNotEmpty &&
                        selectedDate != null &&
                        selectedTime != null) {
                      
                      // FIX: Re-check permission right before scheduling
                      var status = await Permission.scheduleExactAlarm.status;
                      if (!status.isGranted) {
                          _requestPermissions(); // Ask again if denied
                          return;
                      }

                      final reminderDateTime = DateTime(
                        selectedDate!.year,
                        selectedDate!.month,
                        selectedDate!.day,
                        selectedTime!.hour,
                        selectedTime!.minute,
                      );

                      if (reminderDateTime.isBefore(DateTime.now())) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Cannot set a reminder for a past time.'),
                          backgroundColor: Colors.orange,
                        ));
                        return;
                      }

                      if (reminderDoc == null) {
                        _addReminder(
                          titleController.text,
                          descriptionController.text,
                          reminderDateTime,
                          recurrence,
                        );
                      } else {
                        _updateReminder(
                          reminderDoc,
                          titleController.text,
                          descriptionController.text,
                          reminderDateTime,
                          recurrence,
                        );
                      }
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  CollectionReference get _remindersCollection {
      final user = _auth.currentUser;
      if (user == null || user.email == null) {
          throw Exception("User not logged in");
      }
      return _firestore
          .collection('users')
          .doc(user.email)
          .collection('reminders');
  }


  void _addReminder(String title, String description, DateTime reminderTime, String recurrence) async {
    final notificationId = Random().nextInt(100000);
    try {
        await _remindersCollection.add({
          'title': title,
          'description': description,
          'reminderTime': Timestamp.fromDate(reminderTime),
          'recurrence': recurrence,
          'notificationId': notificationId,
        });

        _scheduleNotification(notificationId, title, description, reminderTime, recurrence);
    } catch (e) {
        print("Error adding reminder: $e");
    }
  }

  void _updateReminder(DocumentSnapshot doc, String title, String description, DateTime reminderTime, String recurrence) async {
    final data = doc.data() as Map<String, dynamic>;
    final int oldNotificationId = data['notificationId'] ?? Random().nextInt(100000);

    await flutterLocalNotificationsPlugin.cancel(oldNotificationId);
    
    final newNotificationId = Random().nextInt(100000);

    await doc.reference.update({
      'title': title,
      'description': description,
      'reminderTime': Timestamp.fromDate(reminderTime),
      'recurrence': recurrence,
      'notificationId': newNotificationId,
    });

    _scheduleNotification(newNotificationId, title, description, reminderTime, recurrence);
  }

  /// ✅ Schedules the notification to fire like an alarm.
  Future<void> _scheduleNotification(
      int id, String title, String body, DateTime scheduledTime, String recurrence) async {
    
    var status = await Permission.scheduleExactAlarm.status;
    if (!status.isGranted) {
        print("Exact alarm permission not granted. Scheduling will fail.");
        if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Alarm permission is required for reminders.'),
                backgroundColor: Colors.red,
            ));
        }
        return; // Don't even try to schedule
    }
    
    DateTimeComponents? dateTimeComponents;
    switch (recurrence) {
      case 'Daily':
        dateTimeComponents = DateTimeComponents.time;
        break;
      case 'Weekly':
        dateTimeComponents = DateTimeComponents.dayOfWeekAndTime;
        break;
      case 'Monthly':
        dateTimeComponents = DateTimeComponents.dayOfMonthAndTime;
        break;
      default:
        dateTimeComponents = null; // For 'Once'
    }

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'alarm_channel_id',
      'Alarms',
      channelDescription: 'Channel for reminder alarms',
      importance: Importance.max,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound('alarm'),
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);

    final tz.TZDateTime tzTime = tz.TZDateTime.from(scheduledTime, tz.local);
    print('Scheduling notification for: $tzTime with ID: $id');

    try {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          id,
          title,
          body,
          tzTime,
          platformDetails,
          payload: body,
          matchDateTimeComponents: dateTimeComponents,
          androidScheduleMode: AndroidScheduleMode.alarmClock,
        );
    } catch (e) {
        print("Error scheduling notification: $e");
    }
  }

  void _deleteReminder(String docId, int notificationId) {
    try {
        _remindersCollection.doc(docId).delete();
        flutterLocalNotificationsPlugin.cancel(notificationId);
    } catch(e) {
        print("Error deleting reminder: $e");
    }
  }

  IconData _getRecurrenceIcon(String recurrence) {
    switch (recurrence) {
      case 'Daily':
        return Icons.repeat;
      case 'Weekly':
        return Icons.calendar_view_week;
      case 'Monthly':
        return Icons.calendar_month;
      default:
        return Icons.alarm;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _navigateBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: _navigateBack,
          ),
          title: const Text('Reminders & Alarms'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 1,
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: _remindersCollection.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(child: Text("Error loading reminders. Please log in again."));
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text(
                    'No reminders set.\nTap the + button to add one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ),
              );
            }
            final reminders = snapshot.data!.docs;
            return ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: reminders.length,
              itemBuilder: (context, index) {
                final reminder = reminders[index];
                final data = reminder.data() as Map<String, dynamic>;
                final reminderTime = (data['reminderTime'] as Timestamp).toDate();
                final recurrence = data['recurrence'] ?? 'Once';
                final notificationId = data['notificationId'] ?? 0;

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: InkWell(
                    onTap: () => _showReminderDialog(reminderDoc: reminder),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Icon(_getRecurrenceIcon(recurrence),
                              color: Colors.blue[800], size: 32),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(data['title'],
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 4),
                                Text(data['description'],
                                    style: const TextStyle(color: Colors.black54)),
                                const SizedBox(height: 8),
                                Text(
                                  DateFormat('MMM d, yyyy \'at\' HH:mm')
                                      .format(reminderTime),
                                  style: TextStyle(
                                      color: Colors.grey[700], fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.redAccent),
                            onPressed: () =>
                                _deleteReminder(reminder.id, notificationId),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showReminderDialog(),
          backgroundColor: Colors.blue[800],
          child: const Icon(Icons.add_alarm, color: Colors.white),
        ),
      ),
    );
  }
}

