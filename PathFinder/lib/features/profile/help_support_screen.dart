import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final faqs = [
      {
        'q': 'How do I add a new vehicle?',
        'a': 'Only Owners and Managers can add vehicles. Go to the Fleet tab and tap the "+" button in the top right corner. Enter the vehicle details to register it.'
      },
      {
        'q': 'How does Geofencing work?',
        'a': 'You can define custom geographical zones. If a vehicle enters or leaves these zones, an automated alert will be triggered based on your notification settings.'
      },
      {
        'q': 'What does "Engine Lock" do?',
        'a': 'The Engine Lock command sends an immediate signal to disable the vehicle\'s ignition system remotely, preventing the vehicle from being started. This is highly recommended during theft situations.'
      },
      {
        'q': 'I am not receiving push notifications.',
        'a': 'Ensure you have enabled Push Notifications in your device Settings, and that alerts are turned on in the Push Notifications section of your PathFinder Profile.'
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Support'),
        backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        foregroundColor: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
        iconTheme: IconThemeData(color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
        elevation: 0,
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Frequently Asked Questions',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final faq = faqs[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? AppColors.dividerDark : AppColors.dividerLight),
                    ),
                    child: ExpansionTile(
                      title: Text(
                        faq['q']!,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                        ),
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          faq['a']!,
                          style: TextStyle(
                            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              childCount: faqs.length,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 32),
                  Text(
                    'Still need help?',
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Opening Support Chat...')),
                        );
                      },
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Contact Support'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Opening Email Client...')),
                      );
                    },
                    icon: const Icon(Icons.email_outlined),
                    label: const Text('Email support@pathfinder.com'),
                  ),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
