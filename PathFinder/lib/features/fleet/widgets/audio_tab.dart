import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/vehicle_model.dart';
import '../../../shared/widgets/custom_button.dart';

class AudioTab extends StatelessWidget {
  final VehicleModel vehicle;
  final bool isDark;

  const AudioTab({
    super.key,
    required this.vehicle,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    // Generate dummy audio triggers
    final List<Map<String, dynamic>> dummyAudioEvents = List.generate(
      8,
      (index) {
        final timestamp = DateTime.now().subtract(Duration(hours: index * 5, minutes: index * 12));
        final timeStr = '${timestamp.day}/${timestamp.month} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
        return {
          'id': 'audio_$index',
          'timestamp': timeStr,
          'duration': '30s',
          'trigger': index % 3 == 0 ? 'Manual Request' : 'Sudden Noise Trigger',
        };
      },
    );

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Record Button Section
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Column(
              children: [
                Icon(
                  Icons.mic,
                  size: 48,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Live Cabin Audio',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Request a 30-second audio clip from the cabin. It may take a minute to process and download.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
                ),
                const SizedBox(height: 24),
                CustomButton(
                  label: 'Record Audio (30s)',
                  icon: Icons.fiber_manual_record,
                  color: AppColors.danger,
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Audio recording request sent to device.')),
                    );
                  },
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 32),
          
          // History List
          Text(
            'Recent Audio Events',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: dummyAudioEvents.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final event = dummyAudioEvents[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.secondary.withOpacity(0.1),
                    child: Icon(Icons.play_arrow, color: AppColors.secondary),
                  ),
                  title: Text(
                    event['trigger'],
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                    ),
                  ),
                  subtitle: Text(
                    '${event['timestamp']} • ${event['duration']}',
                    style: TextStyle(
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    ),
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.download, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Downloading audio file...')),
                      );
                    },
                  ),
                  onTap: () {
                    // Would typically open an inline audio player
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Playing audio clip...')),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
