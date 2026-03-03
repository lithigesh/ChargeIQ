import 'package:flutter/material.dart';
import '../utils/app_snackbar.dart';

class PremiumPlansScreen extends StatelessWidget {
  const PremiumPlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Custom Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(
                top: 60,
                left: 20,
                right: 20,
                bottom: 50,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(40),
                  bottomRight: Radius.circular(40),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back button & Title
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        'Premium Plans',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  // Header content
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Unlock More\nPower',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Choose the perfect plan for your EV charging needs.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 15,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.stars_rounded,
                          color: Colors.amberAccent,
                          size: 64,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Plan Cards
            Transform.translate(
              offset: const Offset(0, -30),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _buildPlanCard(
                      context,
                      title: 'Basic',
                      price: 'Free',
                      description: 'Essential features for everyday charging.',
                      features: [
                        'Access to public chargers',
                        'Basic routing',
                        'Pay-as-you-go',
                      ],
                      buttonText: 'Downgrade',
                      isCurrentPlan: false,
                      color: Colors.grey.shade700,
                      isDarkTheme: false,
                    ),
                    const SizedBox(height: 24),
                    _buildPlanCard(
                      context,
                      title: 'Pro',
                      price: '₹499',
                      period: '/mo',
                      description: 'Advanced features for frequent drivers.',
                      features: [
                        'AI-powered station selection',
                        'Discounted charging rates',
                        'Priority support',
                        'Advanced route planning',
                      ],
                      buttonText: 'Current Plan',
                      isCurrentPlan: true,
                      isPopular: true,
                      color: const Color(0xFF1565C0),
                      isDarkTheme: false,
                    ),
                    const SizedBox(height: 24),
                    _buildPlanCard(
                      context,
                      title: 'Ultra',
                      price: '₹999',
                      period: '/mo',
                      description: 'The ultimate charging experience.',
                      features: [
                        'Everything in Pro',
                        'Zero transaction fees',
                        'Free home charger installation consult',
                        'Exclusive partner perks',
                      ],
                      buttonText: 'Subscribe Now',
                      isCurrentPlan: false,
                      color: const Color(0xFF7E57C2),
                      isDarkTheme: true,
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconForPlan(String title) {
    switch (title.toLowerCase()) {
      case 'basic':
        return Icons.electric_car_outlined;
      case 'pro':
        return Icons.bolt_rounded;
      case 'ultra':
        return Icons.diamond_rounded;
      default:
        return Icons.star_border_rounded;
    }
  }

  Widget _buildPlanCard(
    BuildContext context, {
    required String title,
    required String price,
    String period = '',
    required String description,
    required List<String> features,
    required String buttonText,
    required bool isCurrentPlan,
    required Color color,
    bool isPopular = false,
    required bool isDarkTheme,
  }) {
    final bool isGradient = isDarkTheme;

    final bgDecoration = isGradient
        ? BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7E57C2), Color(0xFF512DA8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF512DA8).withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          )
        : BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: isPopular
                ? Border.all(color: color.withValues(alpha: 0.5), width: 2)
                : Border.all(color: Colors.transparent, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: bgDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon & Title & Price
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isGradient
                          ? Colors.white.withValues(alpha: 0.2)
                          : color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      _getIconForPlan(title),
                      color: isGradient ? Colors.white : color,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: isGradient ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        price,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: isGradient ? Colors.white : color,
                        ),
                      ),
                      if (period.isNotEmpty)
                        Text(
                          period,
                          style: TextStyle(
                            fontSize: 14,
                            color: isGradient
                                ? Colors.white.withValues(alpha: 0.7)
                                : Colors.grey.shade500,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                description,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: isGradient
                      ? Colors.white.withValues(alpha: 0.85)
                      : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 24),
              const Divider(color: Colors.transparent, height: 1),
              // Features
              ...features.map(
                (feature) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.check_circle_rounded,
                          color: isGradient ? Colors.white : color,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          feature,
                          style: TextStyle(
                            fontSize: 15,
                            color: isGradient
                                ? Colors.white.withValues(alpha: 0.95)
                                : Colors.black87,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isCurrentPlan
                      ? null
                      : () {
                          AppSnackBar.info(
                            context,
                            'Premium plans are coming soon!',
                            icon: Icons.hourglass_empty,
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isGradient ? Colors.white : color,
                    foregroundColor: isGradient ? color : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: isGradient ? 8 : 0,
                    shadowColor: isGradient
                        ? Colors.black.withValues(alpha: 0.3)
                        : Colors.transparent,
                    disabledBackgroundColor: isGradient
                        ? Colors.white.withValues(alpha: 0.2)
                        : const Color(0xFFF0F0F0),
                    disabledForegroundColor: isGradient
                        ? Colors.white.withValues(alpha: 0.6)
                        : Colors.grey.shade500,
                  ),
                  child: Text(
                    buttonText,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (isPopular)
          Positioned(
            top: -12,
            right: 28,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00D26A), Color(0xFF00B259)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00D26A).withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.local_fire_department,
                    color: Colors.white,
                    size: 14,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'MOST POPULAR',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
