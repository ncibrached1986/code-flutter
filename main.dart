+-import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:math';

// ==================== Global Variables & Services ====================
InterstitialAd? _interstitialAd;
Timer? _adTimer;
bool _isAdLoaded = false; 
final FirebaseAuth _auth = FirebaseAuth.instance;

// ==================== Ad Service ====================
class AdService {
  static InterstitialAd? _interstitialAd;
  static bool _isAdLoaded = false;
  
  static Future<void> loadInterstitialAd() async {
    await InterstitialAd.load(
      adUnitId: 'ca-app-pub-7014781234855247/6006727847',
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          _interstitialAd = ad;
          _isAdLoaded = true;
          _interstitialAd?.setImmersiveMode(true);
        },
        onAdFailedToLoad: (LoadAdError error) {
          _interstitialAd = null;
          _isAdLoaded = false;
          // إعادة المحاولة بعد 5 ثواني في حالة فشل التحميل
          Timer(const Duration(seconds: 5), () => loadInterstitialAd());
        },
      ),
    );
  }

  static void showInterstitialAd(BuildContext context) async {
    if (_isAdLoaded && _interstitialAd != null) {
      _interstitialAd?.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (InterstitialAd ad) {
          PointsService.updatePointsAfterAd().then((_) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('You earned ${PointsService.currentPoints.toStringAsFixed(2)} Points for watching the ad!'),
                duration: const Duration(seconds: 3),
              ),
            );
          });
          ad.dispose();
          _interstitialAd = null;
          _isAdLoaded = false;
          loadInterstitialAd();
        },
        onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
          ad.dispose();
          _interstitialAd = null;
          _isAdLoaded = false;
          loadInterstitialAd();
        },
      );
      _interstitialAd?.show();
    } else {
      await loadInterstitialAd();
      // حاول مرة أخرى بعد ثانية إذا لم يكن الإعلان جاهزاً
      Timer(const Duration(seconds: 1), () {
        if (_isAdLoaded && _interstitialAd != null) {
          _interstitialAd?.show();
        }
      });
    }
  }

  static void startAdTimer() {
    _adTimer?.cancel();
    _adTimer = Timer.periodic(const Duration(seconds: 70), (timer) {
      if (MyApp.navigatorKey.currentContext != null) {
        showInterstitialAd(MyApp.navigatorKey.currentContext!);
      }
    });
  }
}

// ==================== Points Service ====================
class PointsService {
  static double currentPoints = 0.0;

  static Future<double> getAdReward() async {
    final prefs = await SharedPreferences.getInstance();
    String? userId = _auth.currentUser?.uid;
    if (userId == null) return 0.0;
    
    double currentPoints = prefs.getDouble('points_$userId') ?? 0.0;
    
    if (currentPoints >= 1500) return 0.01;
    if (currentPoints >= 1000) return 0.1;
    if (currentPoints >= 700) return 0.2;
    if (currentPoints >= 500) return 0.5;
    return 1.0;
  }

  static Future<void> updatePointsAfterAd() async {
    double reward = await getAdReward();
    final prefs = await SharedPreferences.getInstance();
    String? userId = _auth.currentUser?.uid;
    if (userId == null) return;
    
    double newPoints = currentPoints + reward;
    
    await prefs.setDouble('points_$userId', newPoints);
    currentPoints = newPoints;
  }

  static Future<void> loadPoints() async {
    final prefs = await SharedPreferences.getInstance();
    String? userId = _auth.currentUser?.uid;
    if (userId == null) {
      currentPoints = 0.0;
      return;
    }
    currentPoints = prefs.getDouble('points_$userId') ?? 0.0;
  }

  static Future<void> resetPoints() async {
    final prefs = await SharedPreferences.getInstance();
    String? userId = _auth.currentUser?.uid;
    if (userId == null) return;
    
    await prefs.setDouble('points_$userId', 0.0);
    currentPoints = 0.0;
  }

  static Future<void> savePoints() async {
    final prefs = await SharedPreferences.getInstance();
    String? userId = _auth.currentUser?.uid;
    if (userId == null) return;
    
    await prefs.setDouble('points_$userId', currentPoints);
  }

  static Future<void> deleteUserPoints(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('points_$userId');
  }
}

// ==================== Permission Service ====================
class PermissionService {
  static Future<bool> checkOverlayPermission() async {
    try {
      return await MethodChannel('overlay_permission').invokeMethod('checkPermission');
    } on PlatformException {
      return false;
    }
  }

  static Future<void> requestOverlayPermission(BuildContext context) async {
    try {
      bool granted = await MethodChannel('overlay_permission')
          .invokeMethod('requestPermission');
      
      if (granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permission granted to display over other apps')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permission denied')),
        );
      }
    } on PlatformException {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error requesting permission')),
      );
    }
  }
}

// ==================== Authentication Service ====================
class AuthService {
  static Future<User?> signInWithEmailAndPassword(String email, String password) async {
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await PointsService.loadPoints();
      return userCredential.user;
    } catch (e) {
      print('Error signing in: $e');
      return null;
    }
  }

  static Future<User?> createUserWithEmailAndPassword(String email, String password) async {
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await PointsService.loadPoints();
      return userCredential.user;
    } catch (e) {
      print('Error creating user: $e');
      return null;
    }
  }

  static Future<void> signOut() async {
    await PointsService.savePoints();
    await _auth.signOut();
  }

  static Future<User?> getCurrentUser() async {
    return _auth.currentUser;
  }

  static Future<void> deleteUser() async {
    User? user = _auth.currentUser;
    if (user != null) {
      String userId = user.uid;
      await PointsService.deleteUserPoints(userId);
      await user.delete();
    }
  }

  static Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      print('Error sending password reset email: $e');
      throw e;
    }
  }
}

// ==================== App Main ====================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp();
  await MobileAds.instance.initialize().then((initializationStatus) {
    print("ttttttttttttttttttttttttttttttttttttttttttttttttttttttttttt");
    print('AdMob initialized: ${initializationStatus.adapterStatuses}');
    print("ttttttttttttttttttttttttttttttttttttttttttttttttttttttttttt");
  });
  await AndroidAlarmManager.initialize();
  
  // تحميل أول إعلان عند بدء التشغيل
  AdService.loadInterstitialAd();
  AdService.startAdTimer();
  
  runApp(const MyApp());
}

@pragma('vm:entry-point')
void showAdOnPowerButton() async {
  WidgetsFlutterBinding.ensureInitialized(); 
  
  await MobileAds.instance.initialize(); // تأكد من تهيئة الإعلانات
  
  if (AdService._isAdLoaded && AdService._interstitialAd != null) {
    AdService._interstitialAd?.show();
  } else {
    await AdService.loadInterstitialAd();
    await Future.delayed(const Duration(seconds: 1)); // انتظر ثانية للتحميل
    if (AdService._isAdLoaded && AdService._interstitialAd != null) {
      AdService._interstitialAd?.show();
    }
  }
}

// ==================== App Structure ====================
class MyApp extends StatelessWidget {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'NJR Earn Cash',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const AppStartupScreen(),
      routes: {
        '/home': (context) => const MainHomeScreen(),
        '/earnPoints': (context) => const EarnPointsScreen(),
        '/games': (context) => const GamesScreen(),
        '/withdraw': (context) => const WithdrawScreen(), 
      },
    );
  }
}

// ==================== Login Screen ====================
class LoginScreen extends StatefulWidget {
  final VoidCallback? onSignUpPressed;
  final VoidCallback? onLoginSuccess;

  const LoginScreen({super.key, this.onSignUpPressed, this.onLoginSuccess});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    final user = await AuthService.signInWithEmailAndPassword(email, password);

    setState(() => _isLoading = false);

    if (user != null) {
      widget.onLoginSuccess?.call();
    } else {
      setState(() => _errorMessage = 'Invalid email or password');
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email first')),
      );
      return;
    }

    try {
      await AuthService.resetPassword(email);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset email sent to $email')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending reset email: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Scaffold(
      backgroundColor: const Color(0xFF13239f),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: screenWidth * 0.05,
            vertical: screenHeight * 0.02,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Login',
                  style: TextStyle(
                    fontSize: screenHeight * 0.04,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: screenHeight * 0.03),
                if (_errorMessage != null)
                  Padding(
                    padding: EdgeInsets.only(bottom: screenHeight * 0.02),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Colors.red, 
                        fontSize: screenHeight * 0.02,
                      ),
                    ),
                  ),
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    labelStyle: const TextStyle(color: Colors.white),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white),
                      borderRadius: BorderRadius.circular(screenWidth * 0.03),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.yellow),
                      borderRadius: BorderRadius.circular(screenWidth * 0.03),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!value.contains('@')) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                SizedBox(height: screenHeight * 0.02),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: const TextStyle(color: Colors.white),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white),
                      borderRadius: BorderRadius.circular(screenWidth * 0.03),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.yellow),
                      borderRadius: BorderRadius.circular(screenWidth * 0.03),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility : Icons.visibility_off,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                  obscureText: _obscurePassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                SizedBox(height: screenHeight * 0.01),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      AdService.showInterstitialAd(context);
                      _resetPassword();
                    },
                    child: Text(
                      'Forgot Password?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: screenHeight * 0.018,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: screenHeight * 0.02),
                _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : ElevatedButton(
                        onPressed: () {
                          AdService.showInterstitialAd(context);
                          _login();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.yellowAccent,
                          padding: EdgeInsets.symmetric(
                              horizontal: screenWidth * 0.1, 
                              vertical: screenHeight * 0.02),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(screenWidth * 0.03),
                          ),
                        ),
                        child: Text(
                          'Login',
                          style: TextStyle(
                              color: Colors.black,
                              fontSize: screenHeight * 0.022,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                SizedBox(height: screenHeight * 0.02),
                TextButton(
                  onPressed: () {
                    AdService.showInterstitialAd(context);
                    widget.onSignUpPressed?.call();
                  },
                  child: Text(
                    "Don't have an account? Sign up",
                    style: TextStyle(
                      color: Colors.white, 
                      fontSize: screenHeight * 0.02
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

// ==================== Sign Up Screen ====================
class SignUpScreen extends StatefulWidget {
  final VoidCallback? onLoginPressed;
  final VoidCallback? onSignUpSuccess;

  const SignUpScreen({super.key, this.onLoginPressed, this.onSignUpSuccess});

  @override
  _SignUpScreenState createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = 'Passwords do not match');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    final user = await AuthService.createUserWithEmailAndPassword(email, password);

    setState(() => _isLoading = false);

    if (user != null) {
      widget.onSignUpSuccess?.call();
    } else {
      setState(() => _errorMessage = 'Failed to create account. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Scaffold(
      backgroundColor: const Color(0xFF13239f),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: screenWidth * 0.05,
            vertical: screenHeight * 0.02,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Sign Up',
                  style: TextStyle(
                    fontSize: screenHeight * 0.04,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: screenHeight * 0.03),
                if (_errorMessage != null)
                  Padding(
                    padding: EdgeInsets.only(bottom: screenHeight * 0.02),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Colors.red, 
                        fontSize: screenHeight * 0.02,
                      ),
                    ),
                  ),
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    labelStyle: const TextStyle(color: Colors.white),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white),
                      borderRadius: BorderRadius.circular(screenWidth * 0.03),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.yellow),
                      borderRadius: BorderRadius.circular(screenWidth * 0.03),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!value.contains('@')) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                SizedBox(height: screenHeight * 0.02),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: const TextStyle(color: Colors.white),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white),
                      borderRadius: BorderRadius.circular(screenWidth * 0.03),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.yellow),
                      borderRadius: BorderRadius.circular(screenWidth * 0.03),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility : Icons.visibility_off,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                  obscureText: _obscurePassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                SizedBox(height: screenHeight * 0.02),
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    labelStyle: const TextStyle(color: Colors.white),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white),
                      borderRadius: BorderRadius.circular(screenWidth * 0.03),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.yellow),
                      borderRadius: BorderRadius.circular(screenWidth * 0.03),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword ? Icons.visibility : Icons.visibility_off,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                  obscureText: _obscureConfirmPassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please confirm your password';
                    }
                    return null;
                  },
                ),
                SizedBox(height: screenHeight * 0.03),
                _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : ElevatedButton(
                        onPressed: () {
                          AdService.showInterstitialAd(context);
                          _signUp();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.yellowAccent,
                          padding: EdgeInsets.symmetric(
                              horizontal: screenWidth * 0.1, 
                              vertical: screenHeight * 0.02),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(screenWidth * 0.03),
                          ),
                        ),
                        child: Text(
                          'Sign Up',
                          style: TextStyle(
                              color: Colors.black,
                              fontSize: screenHeight * 0.022,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                SizedBox(height: screenHeight * 0.02),
                TextButton(
                  onPressed: () {
                    AdService.showInterstitialAd(context);
                    widget.onLoginPressed?.call();
                  },
                  child: Text(
                    'Already have an account? Login',
                    style: TextStyle(
                      color: Colors.white, 
                      fontSize: screenHeight * 0.02
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}

// ==================== App Startup Screen ====================
class AppStartupScreen extends StatefulWidget {
  const AppStartupScreen({super.key});

  @override
  State<AppStartupScreen> createState() => _AppStartupScreenState();
}

class _AppStartupScreenState extends State<AppStartupScreen> {
  bool _isFirstLaunch = true;
  bool _isLoading = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkAuthState();
    _checkFirstLaunch();
  }

  Future<void> _checkAuthState() async {
    final user = await AuthService.getCurrentUser();
    setState(() {
      _isLoggedIn = user != null;
      if (_isLoggedIn) {
        PointsService.loadPoints();
      }
    });
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    bool isFirstLaunch = prefs.getBool('first_launch') ?? true;
    
    setState(() {
      _isFirstLaunch = isFirstLaunch;
      _isLoading = false;
    });
    
    if (isFirstLaunch) {
      await prefs.setBool('first_launch', false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    if (_isFirstLaunch) {
      return const OnboardingScreen();
    }
    
    return _isLoggedIn ? const MainHomeScreen() : const AuthWrapperScreen();
  }
}

// ==================== Auth Wrapper Screen ====================
class AuthWrapperScreen extends StatefulWidget {
  const AuthWrapperScreen({super.key});

  @override
  _AuthWrapperScreenState createState() => _AuthWrapperScreenState();
}

class _AuthWrapperScreenState extends State<AuthWrapperScreen> {
  bool _showLogin = true;

  void _toggleAuthScreen() {
    AdService.showInterstitialAd(context);
    setState(() => _showLogin = !_showLogin);
  }

  void _onAuthSuccess() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const MainHomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _showLogin
        ? LoginScreen(
            onSignUpPressed: _toggleAuthScreen,
            onLoginSuccess: _onAuthSuccess,
          )
        : SignUpScreen(
            onLoginPressed: _toggleAuthScreen,
            onSignUpSuccess: _onAuthSuccess,
          );
  }
}

// ==================== Onboarding Screens ====================
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, String>> _onboardingPages = [
    {
      'image': 'assets/images/onboarding1.jpg',
      'title': 'NGR Earn Cash',
      'description': "It will help you earn profits by increasing your points.",
    },
    {
      'image': 'assets/images/onboarding2.jpg',
      'title': 'NJR Earn Cash',
      'description': "It will help you download all your favorite games through the games section.",
    },
  ];

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Scaffold(
      backgroundColor: const Color(0xFF13239f),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: _onboardingPages.length,
            onPageChanged: (int page) => setState(() => _currentPage = page),
            itemBuilder: (context, index) => OnboardingPage(
              image: _onboardingPages[index]['image']!,
              title: _onboardingPages[index]['title']!,
              description: _onboardingPages[index]['description']!,
            ),
          ),
          Positioned(
            top: screenHeight * 0.05,
            right: screenWidth * 0.05,
            child: TextButton(
              onPressed: () {
                AdService.showInterstitialAd(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const AuthWrapperScreen()),
                );
              },
              child: Text(
                'Skip',
                style: TextStyle(
                  color: Colors.white, 
                  fontSize: screenHeight * 0.022
                ),
              ),
            ),
          ),
          Positioned(
            bottom: screenHeight * 0.05,
            left: 0,
            right: 0,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _onboardingPages.length,
                      (index) => Container(
                        margin: EdgeInsets.symmetric(horizontal: screenWidth * 0.01),
                        width: screenWidth * 0.02,
                        height: screenWidth * 0.02,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _currentPage == index
                              ? Colors.white
                              : Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      AdService.showInterstitialAd(context);
                      if (_currentPage < _onboardingPages.length - 1) {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeIn,
                        );
                      } else {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => const AuthWrapperScreen()),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.yellowAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(screenWidth * 0.05),
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: screenWidth * 0.06,
                        vertical: screenHeight * 0.015,
                      ),
                    ),
                    child: Text(
                      _currentPage == _onboardingPages.length - 1
                          ? 'Start now'
                          : 'Next',
                      style: TextStyle(
                        color: Colors.black, 
                        fontSize: screenHeight * 0.02
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OnboardingPage extends StatelessWidget {
  final String image;
  final String title;
  final String description;

  const OnboardingPage({
    super.key,
    required this.image,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Container(
      padding: EdgeInsets.all(screenWidth * 0.05),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            image,
            height: screenHeight * 0.6,
            width: screenWidth,
            fit: BoxFit.contain,
          ),
          SizedBox(height: screenHeight * 0.04),
          Text(
            title,
            style: TextStyle(
              color: Colors.white,
              fontSize: screenHeight * 0.03,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: screenHeight * 0.02),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.1),
            child: Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white, 
                fontSize: screenHeight * 0.022
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== Main Home Screen ====================
class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> with WidgetsBindingObserver {
  bool _hasOverlayPermission = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initApp();
    PointsService.loadPoints();
  }

  Future<void> _initApp() async {
    _hasOverlayPermission = await PermissionService.checkOverlayPermission();
    
    if (_hasOverlayPermission) {
      await AndroidAlarmManager.periodic(
        const Duration(seconds: 1),
        0,
        showAdOnPowerButton,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _hasOverlayPermission) {
      AndroidAlarmManager.oneShot(
        Duration.zero,
        1,
        showAdOnPowerButton,
      );
    }
  }

  Future<void> _withdrawPoints() async {
    if (PointsService.currentPoints < 2000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need at least 2000 points to withdraw')),
      );
      return;
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Withdrawal request successful, transfer within 24 hours')),
    );
    
    await PointsService.resetPoints();
    setState(() {});
  }

  Widget _buildDrawer() {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade700, Colors.blue.shade400],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                CircleAvatar(
                  radius: screenWidth * 0.08,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person, size: screenWidth * 0.1, color: Colors.blue),
                ),
                SizedBox(height: screenHeight * 0.01),
                Text(
                  "Settings",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: screenHeight * 0.03,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: Icon(Icons.settings, size: screenWidth * 0.06),
            title: Text(
              'Display over other apps',
              style: TextStyle(fontSize: screenHeight * 0.02),
            ),
            trailing: Switch(
              value: _hasOverlayPermission,
              onChanged: (value) {
                AdService.showInterstitialAd(context);
                PermissionService.requestOverlayPermission(context);
              },
            ),
          ),
          Divider(height: screenHeight * 0.02),
          ListTile(
            leading: Icon(Icons.privacy_tip, size: screenWidth * 0.06),
            title: Text(
              'Privacy Policy',
              style: TextStyle(fontSize: screenHeight * 0.02),
            ),
            onTap: () {
              AdService.showInterstitialAd(context);
              _launchURL('https://sites.google.com/view/njr-earn-cash-privacy/accueil');
            },
          ),
          ListTile(
            leading: Icon(Icons.info, size: screenWidth * 0.06),
            title: Text(
              "About Us",
              style: TextStyle(fontSize: screenHeight * 0.02),
            ),
            onTap: () {
              AdService.showInterstitialAd(context);
              _openAboutUs();
            },
          ),
          ListTile(
            leading: Icon(Icons.phone, size: screenWidth * 0.06),
            title: Text(
              "Contact us",
              style: TextStyle(fontSize: screenHeight * 0.02),
            ),
            onTap: () {
              AdService.showInterstitialAd(context);
              _launchURL('tel:+21621096984');
            },
          ),
          ListTile(
            leading: Icon(Icons.email, size: screenWidth * 0.06),
            title: Text(
              "Send Email",
              style: TextStyle(fontSize: screenHeight * 0.02),
            ),
            onTap: () {
              AdService.showInterstitialAd(context);
              _launchURL('mailto:njrearncash@gmail.com');
            },
          ),
          Divider(height: screenHeight * 0.02),
          ListTile(
            leading: Icon(Icons.exit_to_app, size: screenWidth * 0.06),
            title: Text(
              'Log out',
              style: TextStyle(fontSize: screenHeight * 0.02),
            ),
            onTap: () {
              AdService.showInterstitialAd(context);
              _logout();
            },
          ),
          ListTile(
            leading: Icon(Icons.delete, size: screenWidth * 0.06, color: Colors.red),
            title: Text(
              'Delete my account', 
              style: TextStyle(
                fontSize: screenHeight * 0.02,
                color: Colors.red
              ),
            ),
            onTap: () {
              AdService.showInterstitialAd(context);
              _deleteAccount();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _launchURL(String url) async {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch URL')),
      );
    }
  }

  void _openAboutUs() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('About the app'),
            backgroundColor: Colors.yellowAccent,
          ),
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF13239f),
                  Color(0xFF782ec1),
                  Color(0xFF7120c0),
                ],
                stops: [0.0, 0.7, 0.9],
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: Text(
                        '🟡 Earn money easily with NJR Earn Cash!',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Looking for a smart and easy way to earn money effortlessly?',
                      style: TextStyle(fontSize: 18, color: Colors.white),
                        textDirection: TextDirection.ltr,

                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'With NJR Earn Cash app, you can get daily points just by using your phone normally!',
                      style: TextStyle(fontSize: 18, color: Colors.white),
                        textDirection: TextDirection.ltr,

                    ),
                    const SizedBox(height: 30),
                    Row(
                      children: [
                        Expanded(child: Container()),

                        const Text(
                          '💡 How does the app work?',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.yellowAccent,
                          ),
                            textDirection: TextDirection.ltr,
                            

                        ),
                      
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildFeatureItem('We show you customized content and ads on the lock screen'),
                    _buildFeatureItem('Open your phone as usual by swiping in any direction'),
                    _buildFeatureItem('Every day of use = guaranteed points'),
                    _buildFeatureItem('Redeem points for gift cards from popular stores'),
                    const SizedBox(height: 30),
                    Row(
                      children: [
                        Expanded(child: Container()),

                        const Text(
                          '🎁 App Features:',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.yellowAccent,
                          ),
                            textDirection: TextDirection.ltr,
                        
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildFeatureItem('✔️ No need to open ads'),
                    _buildFeatureItem('✔️ No excessive battery consumption'),
                    _buildFeatureItem('✔️ Instant points redemption'),
                    _buildFeatureItem('✔️ Safe and easy to use'),
                    _buildFeatureItem('✔️ Real daily rewards'),
                    const SizedBox(height: 30),
                    const Center(
                      child: Text(
                        'Make your lock screen an additional source of income. Download NJR Earn Cash now and start earning rewards immediately!',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                        textDirection: TextDirection.ltr,

                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: ElevatedButton(
                        onPressed: () {
                          AdService.showInterstitialAd(context);
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.yellowAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Back',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 16, color: Colors.white),
                        textDirection: TextDirection.ltr,

            ),
            
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    await AuthService.signOut();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const AuthWrapperScreen()),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Successfully logged out')),
    );
  }

  Future<void> _deleteAccount() async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account'),
        content: const Text("Are you sure you want to delete your account? This cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      await AuthService.deleteUser();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AuthWrapperScreen()),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account deleted successfully')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(
          'NJR Earn Cash', 
          style: TextStyle(
            color: Colors.white,
            fontSize: screenHeight * 0.025,
          ),
        ),
        backgroundColor: const Color.fromARGB(255, 47, 2, 131),
        actions: [
          IconButton(
            icon: Icon(
              Icons.settings, 
              color: Colors.white,
              size: screenWidth * 0.06,
            ),
            onPressed: () {
              AdService.showInterstitialAd(context);
              _scaffoldKey.currentState?.openEndDrawer();
            },
          ),
        ],
      ),
      endDrawer: _buildDrawer(),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF13239f),
              Color(0xFF782ec1),
              Color(0xFF7120c0),
            ],
            stops: [0.0, 0.7, 0.9],
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(vertical: screenHeight * 0.02),
                child: Text(
                  'WELCOME BACK!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: screenHeight * 0.03,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                width: screenWidth * 0.8,
                margin: EdgeInsets.all(screenWidth * 0.05),
                padding: EdgeInsets.all(screenWidth * 0.04),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(screenWidth * 0.05),
                  color: const Color.fromARGB(255, 22, 36, 43),
                ),
                child: Column(
                  children: [
                    Text(
                      'Your Current Balance:',
                      style: TextStyle(
                        fontSize: screenHeight * 0.022,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.01),
                    Text(
                      PointsService.currentPoints.toStringAsFixed(2),
                      style: TextStyle(
                        fontSize: screenHeight * 0.03,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Points',
                      style: TextStyle(
                        fontSize: screenHeight * 0.022,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 10,),
                    InkWell(
                      onTap: (){
                        AdService.showInterstitialAd(context);
                        setState(() {});
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        height: 30,
                        width: 140,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: const Color.fromARGB(255, 24, 2, 121)
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.refresh,color: Colors.white,),
                            Text("Refresh",style: TextStyle(color: Colors.white,fontSize: 18),),
                          ],
                        ),
                      ),
                    )
                  ],
                ),
              ),
              SizedBox(height: screenHeight * 0.02),
              Container(
                height: screenHeight * 0.15,
                width: screenWidth * 0.25,
                padding: EdgeInsets.only(top: screenHeight * 0.02),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 47, 2, 131),
                  border: const Border(
                    left: BorderSide(color: Colors.grey, width: 3),
                    right: BorderSide(color: Colors.grey, width: 3),
                    top: BorderSide(color: Colors.grey, width: 3),
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(10),
                    topRight: Radius.circular(10),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.lock, 
                      color: Colors.white, 
                      size: screenWidth * 0.05
                    ),
                    SizedBox(height: screenHeight * 0.01),
                    Icon(
                      Icons.image, 
                      color: Colors.white, 
                      size: screenWidth * 0.12
                    ),
                  ],
                ),
              ),
              SizedBox(height: screenHeight * 0.02),
              Text(
                "You're earning while your phone\n is locked!",
                style: TextStyle(
                  color: Colors.white, 
                  fontSize: screenHeight * 0.022
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: screenHeight * 0.04),
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          AdService.showInterstitialAd(context);
                          Navigator.pushNamed(context, '/earnPoints');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color.fromARGB(255, 87, 30, 245),
                          padding: EdgeInsets.symmetric(
                            horizontal: screenWidth * 0.1,
                            vertical: screenHeight * 0.02,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(screenWidth * 0.03),
                          ),
                        ),
                        child: Text(
                          'Earn Points',
                          style: TextStyle(
                            fontSize: screenHeight * 0.02,
                            color: Colors.white
                          ),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          AdService.showInterstitialAd(context);
                          Navigator.pushNamed(context, '/games');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color.fromARGB(255, 23, 28, 58),
                          padding: EdgeInsets.symmetric(
                            horizontal: screenWidth * 0.05,
                            vertical: screenHeight * 0.02,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(screenWidth * 0.03),
                          ),
                        ),
                        child: Text(
                          "Recommended Apps",
                          style: TextStyle(
                            fontSize: screenHeight * 0.02,
                            color: Colors.white
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: screenHeight * 0.02),
                  ElevatedButton(
                    onPressed: () {
                      AdService.showInterstitialAd(context);
                      Navigator.pushNamed(context, '/withdraw');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 38, 3, 134),
                      padding: EdgeInsets.symmetric(
                        horizontal: screenWidth * 0.1,
                        vertical: screenHeight * 0.02,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(screenWidth * 0.03),
                      ),
                    ),
                    child: Text(
                      "Redeem Gift Cards",
                      style: TextStyle(
                        fontSize: screenHeight * 0.02,
                        color: Colors.white
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: screenHeight * 0.05),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== Earn Points Screen ====================
class EarnPointsScreen extends StatefulWidget {
  const EarnPointsScreen({super.key});

  @override
  State<EarnPointsScreen> createState() => _EarnPointsScreenState();
}

class _EarnPointsScreenState extends State<EarnPointsScreen> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _hasOverlayPermission = false;
  List<bool> _boxOpened = List.generate(6, (index) => false);
  List<double> _boxRewards = List.generate(6, (index) => 0.0);
  DateTime? _lastOpenedTime;
  bool _canOpenBoxes = true;
  Timer? _timer;
  Duration _remainingTime = Duration.zero;
  late SharedPreferences _prefs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPoints();
    _initOverlayPermission();
  }

  Future<void> _initPoints() async {
    _prefs = await SharedPreferences.getInstance();
    _checkLastOpenedTime();
    _generateRandomRewards();
  }

  Future<void> _checkLastOpenedTime() async {
    final lastOpenedMillis = _prefs.getInt('last_opened_time');
    
    if (lastOpenedMillis != null) {
      _lastOpenedTime = DateTime.fromMillisecondsSinceEpoch(lastOpenedMillis);
      final now = DateTime.now();
      final difference = now.difference(_lastOpenedTime!);
      
      if (difference.inHours < 24) {
        setState(() {
          _canOpenBoxes = false;
          _remainingTime = Duration(hours: 24) - difference;
        });
        _startTimer();
      } else {
        setState(() => _canOpenBoxes = true);
      }
    } else {
      setState(() => _canOpenBoxes = true);
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingTime.inSeconds > 0) {
          _remainingTime = _remainingTime - const Duration(seconds: 1);
        } else {
          _canOpenBoxes = true;
          _timer?.cancel();
        }
      });
    });
  }

  void _generateRandomRewards() {
    final random = Random();
    setState(() {
      _boxRewards = List.generate(6, (index) => 
        PointsService.currentPoints >= 200 
          ? 0.01 + random.nextDouble() * 0.89
          : (random.nextInt(6) + 1).toDouble());
    });
  }

  Future<void> _initOverlayPermission() async {
    _hasOverlayPermission = await PermissionService.checkOverlayPermission();
  }

  void _openBox(int index) async {
    if (!_canOpenBoxes || _boxOpened[index]) return;

    AdService.showInterstitialAd(context);

    final now = DateTime.now();
    await _prefs.setInt('last_opened_time', now.millisecondsSinceEpoch);
    
    setState(() {
      _boxOpened[index] = true;
      _canOpenBoxes = false;
      _lastOpenedTime = now;
      _remainingTime = const Duration(hours: 24);
    });
    
    _startTimer();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Congratulations!', textAlign: TextAlign.center),
        content: Text(
          'You earned ${_boxRewards[index].toStringAsFixed(2)} points!',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              PointsService.currentPoints += _boxRewards[index];
              PointsService.savePoints();
              Future.delayed(const Duration(milliseconds: 500), () {
                Navigator.pop(context);
              });
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String hours = twoDigits(duration.inHours);
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _hasOverlayPermission) {
      AndroidAlarmManager.oneShot(
        Duration.zero,
        1,
        showAdOnPowerButton,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Widget _buildDrawer() {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade700, Colors.blue.shade400],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                CircleAvatar(
                  radius: screenWidth * 0.08,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person, size: screenWidth * 0.1, color: Colors.blue),
                ),
                SizedBox(height: screenHeight * 0.01),
                Text(
                  "Settings",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: screenHeight * 0.03,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: Icon(Icons.settings, size: screenWidth * 0.06),
            title: Text(
              'Display over other apps',
              style: TextStyle(fontSize: screenHeight * 0.02),
            ),
            trailing: Switch(
              value: _hasOverlayPermission,
              onChanged: (value) {
                AdService.showInterstitialAd(context);
                PermissionService.requestOverlayPermission(context);
              },
            ),
          ),
          Divider(height: screenHeight * 0.02),
          ListTile(
            leading: Icon(Icons.privacy_tip, size: screenWidth * 0.06),
            title: Text(
              'Privacy Policy',
              style: TextStyle(fontSize: screenHeight * 0.02),
            ),
            onTap: () {
              AdService.showInterstitialAd(context);
              _launchURL('https://sites.google.com/view/njr-earn-cash-privacy/accueil');
            },
          ),
          ListTile(
            leading: Icon(Icons.info, size: screenWidth * 0.06),
            title: Text(
              "About Us",
              style: TextStyle(fontSize: screenHeight * 0.02),
            ),
            onTap: () {
              AdService.showInterstitialAd(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AboutUsScreen()),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.phone, size: screenWidth * 0.06),
            title: Text(
              "Contact us",
              style: TextStyle(fontSize: screenHeight * 0.02),
            ),
            onTap: () {
              AdService.showInterstitialAd(context);
              _launchURL('tel:+21621096984');
            },
          ),
          Divider(height: screenHeight * 0.02),
          ListTile(
            leading: Icon(Icons.exit_to_app, size: screenWidth * 0.06),
            title: Text(
              'Log out',
              style: TextStyle(fontSize: screenHeight * 0.02),
            ),
            onTap: () async {
              AdService.showInterstitialAd(context);
              await AuthService.signOut();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Successfully logged out')),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.delete, size: screenWidth * 0.06, color: Colors.red),
            title: Text(
              'Delete my account', 
              style: TextStyle(
                fontSize: screenHeight * 0.02,
                color: Colors.red
              ),
            ),
            onTap: () {
              AdService.showInterstitialAd(context);
              _deleteAccount();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _launchURL(String url) async {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch URL')),
      );
    }
  }

  Future<void> _deleteAccount() async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account'),
        content: const Text("Are you sure you want to delete your account? This cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      await AuthService.deleteUser();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AuthWrapperScreen()),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account deleted successfully')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(
          'Collect your points',
          style: TextStyle(fontSize: screenHeight * 0.025),
        ),
        backgroundColor: Colors.yellowAccent,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            size: screenWidth * 0.06,
          ),
          onPressed: () {
            AdService.showInterstitialAd(context);
            Navigator.pop(context);
          },
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.settings,
              size: screenWidth * 0.06,
            ),
            onPressed: () {
              AdService.showInterstitialAd(context);
              _scaffoldKey.currentState?.openEndDrawer();
            },
          ),
        ],
      ),
      endDrawer: _buildDrawer(),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF13239f),
              Color(0xFF782ec1),
              Color(0xFF7120c0),
            ],
            stops: [0.0, 0.7, 0.9],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(screenWidth * 0.05),
          child: Column(
            children: [
              Text(
                'Choose a fund to earn points',
                style: TextStyle(
                  fontSize: screenHeight * 0.03,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: screenHeight * 0.02),
              Text(
                'Your current points: ${PointsService.currentPoints.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: screenHeight * 0.02,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: screenHeight * 0.03),
              if (!_canOpenBoxes)
                Column(
                  children: [
                    Text(
                      "You can open the chests again after:",
                      style: TextStyle(
                        fontSize: screenHeight * 0.02,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.01),
                    Text(
                      _formatDuration(_remainingTime),
                      style: TextStyle(
                        fontSize: screenHeight * 0.03,
                        color: Colors.yellow,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.02),
                  ],
                ),
              Expanded(
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 1,
                    crossAxisSpacing: screenWidth * 0.03,
                    mainAxisSpacing: screenHeight * 0.02,
                  ),
                  itemCount: 6,
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () => _openBox(index),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _boxOpened[index] || !_canOpenBoxes
                              ? Colors.grey 
                              : const Color.fromARGB(255, 255, 230, 0),
                          borderRadius: BorderRadius.circular(screenWidth * 0.03),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 5,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Center(
                          child: _boxOpened[index]
                              ? Text(
                                  _boxRewards[index].toStringAsFixed(2),
                                  style: TextStyle(
                                    fontSize: screenHeight * 0.03,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  Icons.card_giftcard,
                                  size: screenWidth * 0.1,
                                  color: Colors.black,
                                ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== Games Screen ====================
class GamesScreen extends StatefulWidget {
  const GamesScreen({super.key});

  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> with WidgetsBindingObserver {
  final List<GameItem> _games = [
    GameItem(
      name: 'Subway Surfers',
      imageUrl: 'https://play-lh.googleusercontent.com/SVQIX_fYcu5mc5no24fElzW7Dg_7O6Zq8C1X1i10VSIz5Q0p7i4V1e3v-FzqLLuMIw',
      playStoreUrl: 'https://play.google.com/store/apps/details?id=com.kiloo.subwaysurf',
    ),
    GameItem(
      name: 'Candy Crush Saga',
      imageUrl: 'https://play-lh.googleusercontent.com/TLUeelx8wcpEzf3hoqeLxPs3ai1tdGtAZT2kNf6s5ggbD5o2K_P7UVfNN6W1U0a9Sw',
      playStoreUrl: 'https://play.google.com/store/apps/details?id=com.king.candycrushsaga',
    ),
    GameItem(
      name: 'PUBG Mobile',
      imageUrl: 'https://play-lh.googleusercontent.com/JRd05pyBH41qjgsJuWduRJpDeZG0Hnb0yjf2nWqO7VaGKL10-G5UIygxED-WNOc3pg',
      playStoreUrl: 'https://play.google.com/store/apps/details?id=com.tencent.ig',
    ),
    GameItem(
      name: 'Clash of Clans',
      imageUrl: 'https://play-lh.googleusercontent.com/LByrur1mTmPeNr0ljI-uAUcct1rzmTv5EWu8TQo9dHv5O8DhP9MqBZ3xX8Wn7xW__Y',
      playStoreUrl: 'https://play.google.com/store/apps/details?id=com.supercell.clashofclans',
    ),
    GameItem(
      name: 'Free Fire',
      imageUrl: 'https://play-lh.googleusercontent.com/VSwHQjcAttxsLE47RuS4PqpC4LT7lCoSjE7Hx5AW_yCxtDvcnsHHvm5CTuL5BPN-uRTP',
      playStoreUrl: 'https://play.google.com/store/apps/details?id=com.dts.freefireth',
    ),
    GameItem(
      name: 'Temple Run 2',
      imageUrl: 'https://play-lh.googleusercontent.com/ZyWNGIfzUyoajtFcD7NhMksHEZh37f-MkHVGr5Yfefa-5HjSOBCgjkpEkOETT94NnVM',
      playStoreUrl: 'https://play.google.com/store/apps/details?id=com.imangi.templerun2',
    ),
    GameItem(
      name: 'Clash Royale',
      imageUrl: 'https://play-lh.googleusercontent.com/5LIMaa7WTNy34X6NgB7AgQ-y0tF5W74KIC8B3QojyFvVORo-0U8l1Y8h-OwEtheBqg',
      playStoreUrl: 'https://play.google.com/store/apps/details?id=com.supercell.clashroyale',
    ),
    GameItem(
      name: '8 Ball Pool',
      imageUrl: 'https://play-lh.googleusercontent.com/8HX0xgZQY3BZ3yJ8pBIAJxY6J5X5Z5X5Z5X5Z5X5Z5X5Z5X5Z5X5Z5X5Z5X5Z5',
      playStoreUrl: 'https://play.google.com/store/apps/details?id=com.miniclip.eightballpool',
    ),
  ];

  final List<GameLink> _gameLinks = [
    GameLink(
      name: 'Game Link 1',
      url: 'https://www.gamee.forum/click?offer_id=23783&pub_id=271445&pub_sub_id=ADD_PUBLISHER_ID_HERE&pub_click_id=ADD_CLICK_ID_HERE',
    ),
    GameLink(
      name: 'Game Link 2',
      url: 'https://www.gamee.forum/click?offer_id=29653&pub_id=271445&pub_sub_id=ADD_PUBLISHER_ID_HERE&pub_click_id=ADD_CLICK_ID_HERE',
    ),
    GameLink(
      name: 'Game Link 3',
      url: 'https://www.gamee.forum/click?offer_id=31679&pub_id=271445&pub_sub_id=ADD_PUBLISHER_ID_HERE&pub_click_id=ADD_CLICK_ID_HERE',
    ),
    GameLink(
      name: 'Game Link 4',
      url: 'https://www.gamee.forum/click?offer_id=32369&pub_id=271445&pub_sub_id=ADD_PUBLISHER_ID_HERE&pub_click_id=ADD_CLICK_ID_HERE',
    ),
    GameLink(
      name: 'Game Link 5',
      url: 'https://www.gamee.forum/click?offer_id=32723&pub_id=271445&pub_sub_id=ADD_PUBLISHER_ID_HERE&pub_click_id=ADD_CLICK_ID_HERE',
    ),
    GameLink(
      name: 'Game Link 6',
      url: 'https://www.gamee.forum/click?offer_id=32834&pub_id=271445&pub_sub_id=ADD_PUBLISHER_ID_HERE&pub_click_id=ADD_CLICK_ID_HERE',
    ),
    GameLink(
      name: 'Game Link 7',
      url: 'https://www.gamee.forum/click?offer_id=33028&pub_id=271445&pub_sub_id=ADD_PUBLISHER_ID_HERE&pub_click_id=ADD_CLICK_ID_HERE',
    ),
    GameLink(
      name: 'Game Link 8',
      url: 'https://www.gamee.forum/click?offer_id=33176&pub_id=271445&pub_sub_id=ADD_PUBLISHER_ID_HERE&pub_click_id=ADD_CLICK_ID_HERE',
    ),
    GameLink(
      name: 'Game Link 9',
      url: 'https://www.gamee.forum/click?offer_id=33188&pub_id=271445&pub_sub_id=ADD_PUBLISHER_ID_HERE&pub_click_id=ADD_CLICK_ID_HERE',
    ),
  ];

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _hasOverlayPermission = false;
  int _selectedTab = 0; // 0 for games, 1 for links

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initOverlayPermission();
  }

  Future<void> _initOverlayPermission() async {
    _hasOverlayPermission = await PermissionService.checkOverlayPermission();
  }

  Future<void> _launchGameOnPlayStore(String url) async {
    AdService.showInterstitialAd(context);
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      throw 'Could not launch $url';
    }
  }

  Future<void> _launchGameLink(String url) async {
    AdService.showInterstitialAd(context);
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch game link')),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _hasOverlayPermission) {
      AndroidAlarmManager.oneShot(
        Duration.zero,
        1,
        showAdOnPowerButton,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Widget _buildDrawer() {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade700, Colors.blue.shade400],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                CircleAvatar(
                  radius: screenWidth * 0.08,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person, size: screenWidth * 0.1, color: Colors.blue),
                ),
                SizedBox(height: screenHeight * 0.01),
                Text(
                  "Settings",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: screenHeight * 0.03,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: Icon(Icons.settings, size: screenWidth * 0.06),
            title: Text(
              'Display over other apps',
              style: TextStyle(fontSize: screenHeight * 0.02),
            ),
            trailing: Switch(
              value: _hasOverlayPermission,
              onChanged: (value) {
                AdService.showInterstitialAd(context);
                PermissionService.requestOverlayPermission(context);
              },
            ),
          ),
          Divider(height: screenHeight * 0.02),
          ListTile(
            leading: Icon(Icons.privacy_tip, size: screenWidth * 0.06),
            title: Text(
              'Privacy Policy',
              style: TextStyle(fontSize: screenHeight * 0.02),
            ),
            onTap: () {
              AdService.showInterstitialAd(context);
              _launchURL('https://sites.google.com/view/njr-earn-cash-privacy/accueil');
            },
          ),
          ListTile(
            leading: Icon(Icons.info, size: screenWidth * 0.06),
            title: Text(
              "About Us",
              style: TextStyle(fontSize: screenHeight * 0.02),
            ),
            onTap: () {
              AdService.showInterstitialAd(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AboutUsScreen()),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.phone, size: screenWidth * 0.06),
            title: Text(
              "Contact us",
              style: TextStyle(fontSize: screenHeight * 0.02),
            ),
            onTap: () {
              AdService.showInterstitialAd(context);
              _launchURL('tel:+21621096984');
            },
          ),
          Divider(height: screenHeight * 0.02),
          ListTile(
            leading: Icon(Icons.exit_to_app, size: screenWidth * 0.06),
            title: Text(
              'Log out',
              style: TextStyle(fontSize: screenHeight * 0.02),
            ),
            onTap: () async {
              AdService.showInterstitialAd(context);
              await AuthService.signOut();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Successfully logged out')),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.delete, size: screenWidth * 0.06, color: Colors.red),
            title: Text(
              'Delete my account', 
              style: TextStyle(
                fontSize: screenHeight * 0.02,
                color: Colors.red
              ),
            ),
            onTap: () {
              AdService.showInterstitialAd(context);
              _deleteAccount();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _launchURL(String url) async {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch URL')),
      );
    }
  }

 Future<void> _deleteAccount() async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account'),
        content: const Text("Are you sure you want to delete your account? This cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      await AuthService.deleteUser();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AuthWrapperScreen()),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account deleted successfully')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(
          'Games & Links',
          style: TextStyle(fontSize: screenHeight * 0.025),
        ),
        backgroundColor: Colors.yellowAccent,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            size: screenWidth * 0.06,
          ),
          onPressed: () {
            AdService.showInterstitialAd(context);
            Navigator.pop(context);
          },
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.settings,
              size: screenWidth * 0.06,
            ),
            onPressed: () {
              AdService.showInterstitialAd(context);
              _scaffoldKey.currentState?.openEndDrawer();
            },
          ),
        ],
      ),
      endDrawer: _buildDrawer(),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF13239f),
              Color(0xFF782ec1),
              Color(0xFF7120c0),
            ],
            stops: [0.0, 0.7, 0.9],
          ),
        ),
        child: Column(
          children: [
            // Tab selector
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      AdService.showInterstitialAd(context);
                      setState(() => _selectedTab = 0);
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(vertical: screenHeight * 0.015),
                      decoration: BoxDecoration(
                        color: _selectedTab == 0 ? Colors.blue : Colors.grey,
                      ),
                      child: Center(
                        child: Text(
                          'Games',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: screenHeight * 0.02,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      AdService.showInterstitialAd(context);
                      setState(() => _selectedTab = 1);
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(vertical: screenHeight * 0.015),
                      decoration: BoxDecoration(
                        color: _selectedTab == 1 ? Colors.blue : Colors.grey,
                      ),
                      child: Center(
                        child: Text(
                          'Game Links',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: screenHeight * 0.02,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            
            // Content based on selected tab
            Expanded(
              child: _selectedTab == 0 
                  ? _buildGamesGrid() 
                  : _buildLinksList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGamesGrid() {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return GridView.builder(
      padding: EdgeInsets.all(screenWidth * 0.03),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.8,
        crossAxisSpacing: screenWidth * 0.03,
        mainAxisSpacing: screenHeight * 0.02,
      ),
      itemCount: _games.length,
      itemBuilder: (context, index) {
        return InkWell(
          onTap: () => _launchGameOnPlayStore(_games[index].playStoreUrl),
          child: Card(
            elevation: 5,
            child: Column(
              children: [
                Expanded(
                  child: Image.network(
                    _games[index].imageUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(screenWidth * 0.02),
                  child: Text(
                    _games[index].name,
                    style: TextStyle(
                      fontSize: screenHeight * 0.02,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLinksList() {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return ListView.builder(
      padding: EdgeInsets.all(screenWidth * 0.03),
      itemCount: _gameLinks.length,
      itemBuilder: (context, index) {
        return Card(
          elevation: 3,
          margin: EdgeInsets.only(bottom: screenHeight * 0.01),
          child: ListTile(
            leading: Icon(Icons.link, color: Colors.blue),
            title: Text(
              _gameLinks[index].name,
              style: TextStyle(fontSize: screenHeight * 0.02),
            ),
            trailing: Icon(Icons.arrow_forward_ios, size: screenWidth * 0.04),
            onTap: () => _launchGameLink(_gameLinks[index].url),
          ),
        );
      },
    );
  }
}

// ==================== Withdraw Screen ====================
class WithdrawScreen extends StatefulWidget {
  const WithdrawScreen({super.key});

  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _hasOverlayPermission = false;

  @override
  void initState() {
    super.initState();
    _initOverlayPermission();
  }

  Future<void> _initOverlayPermission() async {
    _hasOverlayPermission = await PermissionService.checkOverlayPermission();
  }

  Future<void> _handleWithdraw(String option) async {
    AdService.showInterstitialAd(context);
    
    if (PointsService.currentPoints < 2000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You need at least 2000 points to withdraw'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // هنا يمكنك إضافة منطق السحب حسب الخيار المحدد
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Withdrawal request for $option submitted successfully'),
        duration: const Duration(seconds: 3),
      ),
    );

    await PointsService.resetPoints();
    setState(() {});
  }

  Widget _buildDrawer() {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade700, Colors.blue.shade400],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                CircleAvatar(
                  radius: screenWidth * 0.08,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person, size: screenWidth * 0.1, color: Colors.blue),
                ),
                SizedBox(height: screenHeight * 0.01),
                Text(
                  "Settings",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: screenHeight * 0.03,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: Icon(Icons.settings, size: screenWidth * 0.06),
            title: Text(
              'Display over other apps',
              style: TextStyle(fontSize: screenHeight * 0.02),
            ),
            trailing: Switch(
              value: _hasOverlayPermission,
              onChanged: (value) {
                AdService.showInterstitialAd(context);
                PermissionService.requestOverlayPermission(context);
              },
            ),
          ),
          Divider(height: screenHeight * 0.02),
          ListTile(
            leading: Icon(Icons.privacy_tip, size: screenWidth * 0.06),
            title: Text(
              'Privacy Policy',
              style: TextStyle(fontSize: screenHeight * 0.02),
            ),
            onTap: () {
              AdService.showInterstitialAd(context);
              _launchURL('https://sites.google.com/view/njr-earn-cash-privacy/accueil');
            },
          ),
          ListTile(
            leading: Icon(Icons.info, size: screenWidth * 0.06),
            title: Text(
              "About Us",
              style: TextStyle(fontSize: screenHeight * 0.02),
            ),
            onTap: () {
              AdService.showInterstitialAd(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AboutUsScreen()),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.phone, size: screenWidth * 0.06),
            title: Text(
              "Contact us",
              style: TextStyle(fontSize: screenHeight * 0.02),
            ),
            onTap: () {
              AdService.showInterstitialAd(context);
              _launchURL('tel:+21621096984');
            },
          ),
          Divider(height: screenHeight * 0.02),
          ListTile(
            leading: Icon(Icons.exit_to_app, size: screenWidth * 0.06),
            title: Text(
              'Log out',
              style: TextStyle(fontSize: screenHeight * 0.02),
            ),
            onTap: () async {
              AdService.showInterstitialAd(context);
              await AuthService.signOut();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Successfully logged out')),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.delete, size: screenWidth * 0.06, color: Colors.red),
            title: Text(
              'Delete my account', 
              style: TextStyle(
                fontSize: screenHeight * 0.02,
                color: Colors.red
              ),
            ),
            onTap: () {
              AdService.showInterstitialAd(context);
              _deleteAccount();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _launchURL(String url) async {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch URL')),
      );
    }
  }

  Future<void> _deleteAccount() async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account'),
        content: const Text("Are you sure you want to delete your account? This cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      await AuthService.deleteUser();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AuthWrapperScreen()),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account deleted successfully')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(
          'Withdraw Points',
          style: TextStyle(fontSize: screenHeight * 0.025),
        ),
        backgroundColor: Colors.yellowAccent,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            size: screenWidth * 0.06,
          ),
          onPressed: () {
            AdService.showInterstitialAd(context);
            Navigator.pop(context);
          },
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.settings,
              size: screenWidth * 0.06,
            ),
            onPressed: () {
              AdService.showInterstitialAd(context);
              _scaffoldKey.currentState?.openEndDrawer();
            },
          ),
        ],
      ),
      endDrawer: _buildDrawer(),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF13239f),
              Color(0xFF782ec1),
              Color(0xFF7120c0),
            ],
            stops: [0.0, 0.7, 0.9],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(screenWidth * 0.05),
          child: Column(
            children: [
              Text(
                'Choose a withdrawal method',
                style: TextStyle(
                  fontSize: screenHeight * 0.03,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: screenHeight * 0.02),
              Text(
                'Your current points: ${PointsService.currentPoints.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: screenHeight * 0.02,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: screenHeight * 0.03),
              Expanded(
                child: GridView(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1.2,
                    crossAxisSpacing: screenWidth * 0.05,
                    mainAxisSpacing: screenHeight * 0.02,
                  ),
                  children: [
                    _buildWithdrawCard(
                      icon: Icons.payment,
                      title: 'PayPal',
                      color: Colors.blue,
                      onTap: () => _handleWithdraw('PayPal'),
                    ),
                    _buildWithdrawCard(
                      icon: Icons.credit_card,
                      title: 'MasterCard',
                      color: Colors.red,
                      onTap: () => _handleWithdraw('MasterCard'),
                    ),
                    _buildWithdrawCard(
                      icon: Icons.shopping_bag,
                      title: 'Buy Games',
                      color: Colors.green,
                      onTap: () => _handleWithdraw('Games'),
                    ),
                    _buildWithdrawCard(
                      icon: Icons.card_giftcard,
                      title: 'Gift Cards',
                      color: Colors.orange,
                      onTap: () => _handleWithdraw('Gift Cards'),
                    ),
                    _buildWithdrawCard(
                      icon: Icons.phone_android,
                      title: 'Mobile Credit',
                      color: Colors.purple,
                      onTap: () => _handleWithdraw('Mobile Credit'),
                    ),
                    _buildWithdrawCard(
                      icon: Icons.money,
                      title: 'Cash Transfer',
                      color: Colors.teal,
                      onTap: () => _handleWithdraw('Cash Transfer'),
                    ),
                  ],
                ),
              ),
              SizedBox(height: screenHeight * 0.02),
              Text(
                'Minimum withdrawal: 2000 points',
                style: TextStyle(
                  fontSize: screenHeight * 0.018,
                  color: Colors.yellow,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWithdrawCard({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withOpacity(0.7), color],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 40,
                color: Colors.white,
              ),
              SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== Models & Helper Classes ====================
class GameItem {
  final String name;
  final String imageUrl;
  final String playStoreUrl;

  GameItem({
    required this.name,
    required this.imageUrl,
    required this.playStoreUrl,
  });
}

class GameLink {
  final String name;
  final String url;

  GameLink({
    required this.name,
    required this.url,
  });
}

class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About the app'),
        backgroundColor: Colors.yellowAccent,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF13239f),
              Color(0xFF782ec1),
              Color(0xFF7120c0),
            ],
            stops: [0.0, 0.7, 0.9],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: Text(
                    '🟡 Earn money easily with NJR Earn Cash!',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                        textDirection: TextDirection.ltr,

                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Looking for a smart and easy way to earn money effortlessly?',
                  style: TextStyle(fontSize: 18, color: Colors.white),
                        textDirection: TextDirection.ltr,

                ),
                const SizedBox(height: 10),
                const Text(
                  'With NJR Earn Cash app, you can get daily points just by using your phone normally!',
                  style: TextStyle(fontSize: 18, color: Colors.white),
                        textDirection: TextDirection.ltr,

                ),
                const SizedBox(height: 30),
                Row(
                  children: [
                        Expanded(child: Container()),

                    const Text(
                      '💡 How does the app work?',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.yellowAccent,
                      ),
                            textDirection: TextDirection.ltr,
                    
                    ),

                  ],
                ),
                const SizedBox(height: 10),
                _buildFeatureItem('We show you customized content and ads on the lock screen'),
                _buildFeatureItem('Open your phone as usual by swiping in any direction'),
                _buildFeatureItem('Every day of use = guaranteed points'),
                _buildFeatureItem('Redeem points for gift cards from popular stores'),
                const SizedBox(height: 30),
                Row(
                  children: [
                        Expanded(child: Container()),

                    const Text(
                      '🎁 App Features:',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.yellowAccent,
                      ),
                            textDirection: TextDirection.ltr,
                    
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildFeatureItem('✔️ No need to open ads'),
                _buildFeatureItem('✔️ No excessive battery consumption'),
                _buildFeatureItem('✔️ Instant points redemption'),
                _buildFeatureItem('✔️ Safe and easy to use'),
                _buildFeatureItem('✔️ Real daily rewards'),
                const SizedBox(height: 30),
                const Center(
                  child: Text(
                    'Make your lock screen an additional source of income. Download NJR Earn Cash now and start earning rewards immediately!',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                        textDirection: TextDirection.ltr,

                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: ElevatedButton(
                    onPressed: () {
                      AdService.showInterstitialAd(context);
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.yellowAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Back',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 16, color: Colors.white),
                        textDirection: TextDirection.ltr,
              
            ),
          ),
        ],
      ),
    );
  }
}