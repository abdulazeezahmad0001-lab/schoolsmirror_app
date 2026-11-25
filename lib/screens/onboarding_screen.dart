import 'package:flutter/material.dart';
import '../services/app_flags.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // The 3 slide images from your folder
  final List<Map<String, String>> _slides = [
    {
      'image': 'assets/images/slide1.jpg',
      'title': 'Welcome to SchoolsMirror',
      'desc': 'The ultimate portal for Admins, Teachers, and Students to manage academics effortlessly.',
    },
    {
      'image': 'assets/images/slide2.jpg',
      'title': 'Manage Everything',
      'desc': 'Create exams, track student results, and manage staff all in one secure place.',
    },
    {
      'image': 'assets/images/slide3.jpg',
      'title': 'Learn Anywhere',
      'desc': 'Access CBT exams and results on the go, even without an internet connection.',
    },
  ];

  static const _primary = Color(0xFF3A57A5);

  @override
  void initState() {
    super.initState();
    // Mark it as seen the moment it is shown: a new install sees it once, never again.
    AppFlags.markOnboardingSeen();
  }

  void _completeOnboarding() async {
    await AppFlags.markOnboardingSeen();

    if (mounted) {
      // Replace with your login route
      Navigator.of(context).pushReplacementNamed('/');
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Skip Button
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _completeOnboarding,
                child: const Text(
                  'Skip',
                  style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            
            // Slide Images
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (int page) {
                  setState(() => _currentPage = page);
                },
                itemCount: _slides.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Image.asset(
                              _slides[index]['image']!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported, size: 80, color: Colors.grey),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          _slides[index]['title']!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0A1929),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _slides[index]['desc']!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.grey,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Dots Indicator & Next Button
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Dots
                  Row(
                    children: List.generate(
                      _slides.length,
                      (index) => buildDot(index),
                    ),
                  ),
                  
                  // Next/Get Started Button
                  ElevatedButton(
                    onPressed: () {
                      if (_currentPage == _slides.length - 1) {
                        _completeOnboarding();
                      } else {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeIn,
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      elevation: 0,
                    ),
                    child: Text(
                      _currentPage == _slides.length - 1 ? 'Get Started' : 'Next',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildDot(int index) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(right: 8),
      height: 8,
      width: _currentPage == index ? 24 : 8,
      decoration: BoxDecoration(
        color: _currentPage == index ? _primary : Colors.grey.shade300,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}