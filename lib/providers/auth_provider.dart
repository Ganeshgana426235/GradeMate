import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isLoading = false;

  // Expose authentication status
  bool get isAuthenticated => _auth.currentUser != null;
  bool get isLoading => _isLoading;

  // Constructor to listen to auth state changes
  AuthProvider() {
    _auth.authStateChanges().listen((User? user) {
      // This listener will automatically notify listeners when auth state changes
      // No need for explicit notifyListeners() here unless you have other state
      // that depends on `user` object properties.
      print('Auth state changed: User is ${user == null ? 'signed out' : 'signed in'}');
      notifyListeners(); // Ensure UI reacts to auth state changes
    });
  }

  // --- Login Method ---
  Future<void> signIn(String email, String password) async {
    _setLoading(true);
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      print('User logged in successfully!');
    } on FirebaseAuthException catch (e) {
      String message;
      if (e.code == 'user-not-found') {
        message = 'No user found for that email.';
      } else if (e.code == 'wrong-password') {
        message = 'Wrong password provided.';
      } else if (e.code == 'invalid-email') {
        message = 'The email address is not valid.';
      } else if (e.code == 'user-disabled') {
        message = 'This user account has been disabled.';
      } else {
        message = e.message ?? 'An unknown error occurred during login.';
      }
      print('Login error: $message');
      throw Exception(message); // Re-throw to be caught by UI
    } catch (e) {
      print('Unexpected login error: $e');
      throw Exception('An unexpected error occurred. Please try again.');
    } finally {
      _setLoading(false);
    }
  }

  // --- Password Reset Method ---
  Future<void> sendPasswordResetEmail(String email) async {
    _setLoading(true);
    try {
      await _auth.sendPasswordResetEmail(email: email);
      print('Password reset email sent to $email');
    } on FirebaseAuthException catch (e) {
      String message;
      if (e.code == 'user-not-found') {
        message = 'No user found for that email.';
      } else if (e.code == 'invalid-email') {
        message = 'The email address is not valid.';
      } else {
        message = e.message ?? 'An unknown error occurred while sending reset email.';
      }
      print('Password reset error: $message');
      throw Exception(message);
    } catch (e) {
      print('Unexpected password reset error: $e');
      throw Exception('An unexpected error occurred. Please try again.');
    } finally {
      _setLoading(false);
    }
  }

  // --- Logout Method ---
  Future<void> signOut() async {
    _setLoading(true);
    try {
      await _auth.signOut();
      print('User signed out.');
    } catch (e) {
      print('Error signing out: $e');
      throw Exception('Failed to sign out. Please try again.');
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  // Add this getter to access the current user from Firebase Auth
  User? get currentUser => _auth.currentUser;
}