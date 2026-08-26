import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/vehicle_model.dart';
import '../../../core/providers/socket_provider.dart';
import '../../../core/services/api_client.dart';

class CameraTab extends ConsumerStatefulWidget {
  final VehicleModel vehicle;
  final bool isDark;

  const CameraTab({
    super.key,
    required this.vehicle,
    required this.isDark,
  });

  @override
  ConsumerState<CameraTab> createState() => _CameraTabState();
}

class _CameraTabState extends ConsumerState<CameraTab> {
  final List<Map<String, dynamic>> _images = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchImages();
    });
  }

  Future<void> _fetchImages() async {
    setState(() => _isLoading = true);
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.get('/api/upload/${widget.vehicle.deviceId}');
      
      if (response != null && response is List) {
        final fetchedImages = response
            .where((item) => item['type'] == 'IMAGE')
            .map((item) => {
                  'url': item['url'],
                  'time': DateTime.parse(item['created_at']).toLocal(),
                })
            .toList();
            
        if (mounted) {
          setState(() {
            _images.clear();
            _images.addAll(fetchedImages);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load images')));
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
        if (data['deviceId'] == widget.vehicle.deviceId && data['type'] == 'IMAGE') {
          setState(() {
            _images.insert(0, {
              'url': data['mediaUrl'],
              'time': DateTime.now(),
            });
          });
        }
      }
    });

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Camera Gallery',
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
                  _fetchImages();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Refreshing gallery...')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading && _images.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _images.isEmpty 
              ? Center(child: Text("No photos recorded yet. Trigger the camera!", style: TextStyle(color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)))
              : GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 4 / 3,
              ),
              itemCount: _images.length,
              itemBuilder: (context, index) {
                final image = _images[index];
                final url = image['url'] as String;
                final timestamp = image['time'] as DateTime;
                final timeStr = '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';

                return GestureDetector(
                  onTap: () => _showFullScreenImage(context, url, timeStr),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          url,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                              child: const Center(child: CircularProgressIndicator()),
                            );
                          },
                        ),
                        // Timestamp Overlay
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.black87, Colors.transparent],
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                              ),
                            ),
                            child: Text(
                              timeStr,
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, String imageUrl, String timeStr) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            fit: StackFit.expand,
            children: [
              InteractiveViewer(
                panEnabled: true,
                minScale: 1.0,
                maxScale: 4.0,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                ),
              ),
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Positioned(
                bottom: 40,
                left: 20,
                child: Text(
                  'Captured: $timeStr',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              )
            ],
          ),
        );
      },
    );
  }
}
