import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Import Riverpod
import 'package:assiist_front_end/providers/auth_providers.dart'; // Import providers
import 'package:assiist_front_end/theme/app_styles.dart'; // For styling
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:assiist_front_end/core/models/user_profile.dart';
import 'package:assiist_front_end/core/repositories/user_profile_repository.dart';
import 'package:assiist_front_end/providers/repository_providers.dart';
import 'package:assiist_front_end/core/errors/exceptions.dart';

class LoginScreen extends ConsumerStatefulWidget {
  // Use ConsumerStatefulWidget
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  // Get Firebase Auth instance
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInWithEmail() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      print('Attempting email sign-in with Firebase Auth...');
      final UserCredential userCredential = await _auth
          .signInWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );

      final User? user = userCredential.user;
      if (user != null) {
        print('Firebase Auth sign-in successful. UID: ${user.uid}');
        final String? idToken = await user.getIdToken();

        if (idToken != null) {
          print('Obtained Firebase ID Token.');
          ref.read(accessTokenProvider.notifier).state = idToken;

          try {
            final userProfileRepo = ref.read(userProfileRepositoryProvider);
            print(
              '[DEBUG] Attempting to fetch user profile for UID: ${user.uid}',
            );
            final UserProfile? userProfile =
                await userProfileRepo.getUserProfile();

            if (userProfile != null) {
              print(
                '[DEBUG] Got user profile: ID=${userProfile.id}, FirebaseUID=${userProfile.firebaseUid}',
              );
              if (userProfile.accountId != null) {
                print(
                  '[DEBUG] Setting account ID in provider from profile: ${userProfile.accountId}',
                );
                ref.read(currentAccountIdProvider.notifier).state =
                    userProfile.accountId;
                print(
                  '[DEBUG] Account ID set in provider: ${ref.read(currentAccountIdProvider)}',
                );
              } else {
                print('[DEBUG] WARNING: User profile has null accountId!');
                throw ServerException(
                  'User profile missing required account ID',
                );
              }
              ref.read(userProfileProvider.notifier).state = userProfile;
              print(
                '[DEBUG] Set user profile with backend ID: ${userProfile.id}',
              );
            } else {
              print('[DEBUG] No profile found for user');
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _errorMessage = 'Account not found. Please contact support.';
                });
              }
              return;
            }
          } on NotFoundException catch (e) {
            print('[DEBUG] User profile not found: $e');
            if (mounted) {
              setState(() {
                _isLoading = false;
                _errorMessage = 'Account not found. Please contact support.';
              });
            }
            return;
          } on ServerException catch (e) {
            print('[DEBUG] Server error with user profile: $e');
            if (mounted) {
              setState(() {
                _isLoading = false;
                _errorMessage =
                    'Error loading user profile. Please try again or contact support.';
              });
            }
            return;
          } catch (e) {
            print('[DEBUG] Error working with user profile: $e');
            if (mounted) {
              setState(() {
                _isLoading = false;
                _errorMessage =
                    'Error loading user profile. Please try again or contact support.';
              });
            }
            return;
          }

          ref.read(locationIdProvider.notifier).state = null;

          if (mounted) {
            Navigator.pushReplacementNamed(context, '/dashboard');
          }
        } else {
          print('Error: Could not retrieve ID token after login.');
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMessage =
                  'Authentication successful, but failed to retrieve token.';
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Authentication failed: User data not found.';
          });
        }
      }
    } on FirebaseAuthException catch (e) {
      print('Firebase Auth Error: ${e.code} - ${e.message}');
      String friendlyMessage;
      switch (e.code) {
        case 'user-not-found':
          friendlyMessage = 'No user found for that email.';
          break;
        case 'wrong-password':
          friendlyMessage = 'Incorrect password provided.';
          break;
        case 'invalid-email':
          friendlyMessage = 'The email address is not valid.';
          break;
        case 'user-disabled':
          friendlyMessage = 'This user account has been disabled.';
          break;
        default:
          friendlyMessage = 'An unexpected authentication error occurred.';
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = friendlyMessage;
        });
      }
    } catch (e) {
      print('Generic Error during email sign-in: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'An unexpected error occurred. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: AppStyles.subtleBackgroundColor(
        context,
      ), // Use theme-aware background
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo with gradient styling
              ShaderMask(
                shaderCallback:
                    (bounds) => AppStyles.gradientAccent.createShader(bounds),
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 120.0,
                  height: 120.0,
                  color:
                      CupertinoColors.white, // Base color for gradient overlay
                ),
              ),
              const SizedBox(height: 40),
              Text(
                'Welcome to Assiist',
                // Use theme-aware text color
                style: CupertinoTheme.of(context)
                    .textTheme
                    .navLargeTitleTextStyle
                    .copyWith(color: AppStyles.primaryTextColor(context)),
              ),
              const SizedBox(height: 40),

              // Email Field
              CupertinoTextField(
                controller: _emailController,
                placeholder: 'Email',
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                style: AppStyles.inputTextStyle(context),
                placeholderStyle: AppStyles.placeholderTextStyle(context),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color:
                      CupertinoTheme.of(context).brightness == Brightness.dark
                          ? CupertinoColors.systemGrey6.withOpacity(0.15)
                          : CupertinoColors.white,
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
              const SizedBox(height: 16),

              // Password Field
              CupertinoTextField(
                controller: _passwordController,
                placeholder: 'Password',
                obscureText: true,
                style: AppStyles.inputTextStyle(context),
                placeholderStyle: AppStyles.placeholderTextStyle(context),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color:
                      CupertinoTheme.of(context).brightness == Brightness.dark
                          ? CupertinoColors.systemGrey6.withOpacity(0.15)
                          : CupertinoColors.white,
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
              const SizedBox(height: 24),

              // Error Message Display
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: CupertinoColors.systemRed.resolveFrom(context),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

              // Sign In Button
              if (_isLoading)
                const CupertinoActivityIndicator(radius: 15.0)
              else
                AppStyles.filledButton(
                  context: context,
                  text: 'Sign In',
                  onPressed: _signInWithEmail,
                ),

              // TODO: Add Sign Up / Forgot Password options if needed
              // TODO: Re-enable Google Sign-In UI when ready
              // const SizedBox(height: 20),
              //
              // // OR Separator
              // Text(
              //   'OR',
              //   style: TextStyle(
              //     color: CupertinoColors.systemGrey.resolveFrom(context),
              //   ),
              // ),
              // const SizedBox(height: 20),
              //
              // // Google Sign In Button
              // CupertinoButton(
              //   color: CupertinoColors.white,
              //   onPressed: _signInWithGoogle,
              //   child: Row(
              //     mainAxisSize: MainAxisSize.min,
              //     children: [
              //       // Remove Image.asset placeholder
              //       // Image.asset('assets/google_logo.png', height: 20.0),
              //       // const SizedBox(width: 10),
              //       const Text(
              //         'Sign in with Google',
              //         style: TextStyle(color: CupertinoColors.black),
              //       ),
              //     ],
              //   ),
              // ),
            ],
          ),
        ),
      ),
    );
  }
}
