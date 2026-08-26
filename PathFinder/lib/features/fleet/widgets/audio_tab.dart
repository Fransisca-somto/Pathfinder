import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/vehicle_model.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../core/providers/socket_provider.dart';
import '../../../core/services/api_client.dart';
import 'package:just_audio/just_audio.dart';

class AudioTab extends ConsumerStatefulWidget {
  final VehicleModel vehicle;
  final bool isDark;

  const AudioTab({
    super.key,
    required this.vehicle,
    required this.isDark,
  });

  @override
  ConsumerState<AudioTab> createState() => _AudioTabState();
}

class _AudioTabState extends ConsumerState<AudioTab> {
  final List<Map<String, dynamic>> _audioFiles = [];
  bool _isLoading = false;
  final AudioPlayer _player = AudioPlayer();
  String? _currentlyPlayingUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchAudio();
    });

    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (mounted) {
          setState(() {
            _currentlyPlayingUrl = null;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _fetchAudio() async {
    setState(() => _isLoading = true);
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.get('/api/upload/${widget.vehicle.deviceId}');
      
      if (response != null && response is List) {
        final fetchedAudio = response
            .where((item) => item['type'] == 'AUDIO')
            .map((item) => {
                  'url': item['url'],
                  'time': DateTime.parse(item['created_at']).toLocal(),
                })
            .toList();
            
        if (mounted) {
          setState(() {
            _audioFiles.clear();
            _audioFiles.addAll(fetchedAudio);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load audio')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    ref.listen(newMediaProvider, (previous, next) {
      if (next.hasValue && next.value != null) {
        final data = next.value!;
        if (data['deviceId'] == widget.vehicle.deviceId && data['type'] == 'AUDIO') {
          setState(() {
            _audioFiles.insert(0, {
              'url': data['mediaUrl'],
              'time': DateTime.now(),
            });
          });
        }
      }
    });

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Audio Events',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                ),
              ),
              IconButton(
                icon: _isLoading 
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.secondary))
                    : Icon(Icons.refresh, color: AppColors.secondary),
                onPressed: _isLoading ? null : () {
                  _fetchAudio();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Refreshing audio history...')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading && _audioFiles.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _audioFiles.isEmpty
              ? Center(child: Text("No audio recorded yet. Tap record to start!", style: TextStyle(color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)))
              : ListView.separated(
              itemCount: _audioFiles.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final event = _audioFiles[index];
                final url = event['url'] as String;
                final timestamp = event['time'] as DateTime;
                final timeStr = '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.secondary.withOpacity(0.1),
                    child: Icon(Icons.audiotrack, color: AppColors.secondary),
                  ),
                  title: Text(
                    'Remote Recording',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                    ),
                  ),
                  subtitle: Text(
                    '$timeStr • Tap to play',
                    style: TextStyle(
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    ),
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      _currentlyPlayingUrl == url ? Icons.stop : Icons.play_arrow, 
                      color: AppColors.secondary
                    ),
                    onPressed: () async {
                      try {
                        if (_currentlyPlayingUrl == url) {
                          await _player.stop();
                          setState(() => _currentlyPlayingUrl = null);
                        } else {
                          setState(() => _currentlyPlayingUrl = url);
                          await _player.setUrl(url);
                          _player.play();
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Failed to play audio')),
                          );
                          setState(() => _currentlyPlayingUrl = null);
                        }
                      }
                    },
                  ),
                  onTap: () async {
                    try {
                      if (_currentlyPlayingUrl == url) {
                        await _player.stop();
                        setState(() => _currentlyPlayingUrl = null);
                      } else {
                        setState(() => _currentlyPlayingUrl = url);
                        await _player.setUrl(url);
                        _player.play();
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Failed to play audio')),
                        );
                        setState(() => _currentlyPlayingUrl = null);
                      }
                    }
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
