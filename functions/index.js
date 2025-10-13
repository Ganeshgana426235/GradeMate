const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

exports.sendPushNotification = functions.firestore
  .document("notifications_queue/{notificationId}")
  .onCreate(async (snap, context) => {
    const notificationData = snap.data();

    // Get all students matching the criteria
    const usersRef = admin.firestore().collection("users");
    const snapshot = await usersRef
      .where("role", "==", "Student")
      .where("collegeId", "==", notificationData.collegeId)
      .where("branch", "==", notificationData.branch.toLowerCase())
      .where("regulation", "==", notificationData.regulation)
      .where("year", "==", notificationData.year)
      .get();

    if (snapshot.empty) {
      console.log("No matching students found.");
      return;
    }

    const tokens = [];
    snapshot.forEach((doc) => {
      const fcmTokens = doc.data().fcmTokens;
      if (fcmTokens && Array.isArray(fcmTokens)) {
        tokens.push(...fcmTokens);
      }
    });

    if (tokens.length === 0) {
      console.log("No FCM tokens to send notifications to.");
      return;
    }

    // Notification payload
    const payload = {
      notification: {
        title: `New file in ${notificationData.subject}`,
        body: `${notificationData.uploaderName} uploaded "${notificationData.fileName}"`,
      },
    };

    // Send notifications
    try {
      const response = await admin.messaging().sendToDevice(tokens, payload);
      console.log("Successfully sent message:", response);

      // Optionally, you can clean up failed tokens here
    } catch (error) {
      console.log("Error sending message:", error);
    }
  });