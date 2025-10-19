const functions = require('firebase-functions/v2'); // Use v2 for latest syntax and runtime
const { onDocumentCreated } = require('firebase-functions/v2/firestore'); // Specific import for document trigger
const admin = require('firebase-admin');

// Ensure Firebase Admin SDK is initialized (required for Firestore and FCM)
admin.initializeApp();

const db = admin.firestore();
const fcm = admin.messaging();

/**
 * Cloud Function triggered when a new document is created in the 
 * notifications_queue subcollection of any college.
 * * NOTE: This uses the modern Firebase Functions (v2) syntax.
 */
exports.sendNewFileNotification = onDocumentCreated(
  'colleges/{collegeId}/notifications_queue/{notificationId}',
  async (event) => {
    
    // Check if data exists
    if (!event.data) {
      functions.logger.warn('No data found in event, returning.');
      return null;
    }
    
    // The data written by the faculty app (the trigger document)
    const triggerData = event.data.data();
    
    const { collegeId, notificationId } = event.params;
    const branch = triggerData.branch || '';
    const regulation = triggerData.regulation || '';
    const year = triggerData.year || '';
    const subject = triggerData.subject || 'Unknown Subject';
    const uploaderName = triggerData.uploaderName || 'Unknown Faculty';
    const fileName = triggerData.title || 'a new file/link'; // CRITICAL: Extract file name here

    // --- FATAL ERROR CHECK (Keep this for resilience) ---
    if (!branch || !regulation || !year || !collegeId) {
        functions.logger.error(`FATAL ERROR: Missing critical path data in trigger document. CollegeId: ${collegeId}, Branch: ${branch}, Regulation: ${regulation}, Year: ${year}.`);
        await event.data.ref.delete(); 
        return null;
    }
    // -----------------------------------------------------

    functions.logger.info(`Processing new file notification for College ID: ${collegeId}, Doc ID: ${notificationId}`);
    
    // 1. Construct the notification content
    const payload = {
      notification: {
        // *** UPDATED TITLE ***
        title: `New ${subject} Material Added`,
        // *** UPDATED BODY ***
        body: `A new study file ${fileName} has been uploaded by ${uploaderName} in ${branch} / ${year} (${regulation}).`,
      },
      android: { 
        notification: {
          channelId: 'new_file_channel',
          sound: 'default',
        },
        priority: 'high',
      },
      data: {
        type: 'NEW_COURSE_FILE',
        collegeId,
        branch,
        regulation,
        year,
        subject,
      },
    };

    // 2. Query for students matching the criteria
    let studentTokens = [];
    try {
      let studentQuery = db.collection('users')
        .where('role', '==', 'Student')
        .where('collegeId', '==', collegeId);

      if (branch) studentQuery = studentQuery.where('branch', '==', branch);
      if (regulation) studentQuery = studentQuery.where('regulation', '==', regulation);
      if (year) studentQuery = studentQuery.where('year', '==', year);

      const studentsSnapshot = await studentQuery.get();

      studentsSnapshot.forEach(doc => {
        const student = doc.data();
        if (student.fcmToken) {
          studentTokens.push(student.fcmToken);
        }
      });
      
    } catch (error) {
      functions.logger.error("Error querying students:", error);
      await event.data.ref.delete(); 
      return null;
    }

    if (studentTokens.length === 0) {
      functions.logger.warn(`No student tokens found for criteria: ${branch}/${regulation}/${year}. Check student user fields for exact match.`);
      await event.data.ref.delete(); 
      return null;
    }

    functions.logger.info(`Found ${studentTokens.length} students. Sending FCM message.`);

    // 3. Send the notification using multicast (to many tokens at once)
    try {
      const response = await fcm.sendEachForMulticast({
        tokens: studentTokens,
        ...payload,
      });

      functions.logger.info('FCM Send results:', response);
      
    } catch (error) {
      functions.logger.error("Error sending FCM message:", error);
    }
    
    // 4. Clean up the trigger document
    await event.data.ref.delete();
    
    return null;
  });
