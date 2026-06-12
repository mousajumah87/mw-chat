import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/io/io_file_stub.dart'
if (dart.library.io) '../../../utils/io/io_file.dart';
import '../../../widgets/ui/mw_avatar.dart';
import '../../../widgets/ui/mw_background.dart';
import '../models/story_audience_service.dart';
import '../models/story_audience_user.dart';
import '../models/story_model.dart';
import '../models/story_repository.dart';

class CreateStoryScreen extends StatefulWidget {
  const CreateStoryScreen({super.key});

  @override
  State<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends State<CreateStoryScreen> {
  final StoryRepository _repo = StoryRepository();
  final StoryAudienceService _audienceService = const StoryAudienceService();

  final TextEditingController _textController = TextEditingController();
  final TextEditingController _linkController = TextEditingController();

  final ImagePicker _picker = ImagePicker();

  StoryVisibility _visibility = StoryVisibility.public;
  StoryMediaType _selectedMediaType = StoryMediaType.text;

  PlatformFile? _selectedFile;
  Uint8List? _videoThumbBytes;

  bool _submitting = false;
  double? _uploadProgress;

  static const int _maxTextStoryChars = 700;
  static const int _maxCaptionChars = 180;
  static const int _maxImageBytes = 10 * 1024 * 1024;
  static const int _maxVideoBytes = 30 * 1024 * 1024;
  static const int _maxVideoSeconds = 30;

  static const List<String> _backgroundPalette = <String>[
    '#121212',
    '#1C1F2A',
    '#2E3A59',
    '#3B1F4A',
    '#5A1F2B',
    '#114B5F',
    '#006D77',
    '#5F0F40',
    '#7B2CBF',
    '#6A040F',
    '#264653',
    '#4A4E69',
  ];

  static const List<String> _textPalette = <String>[
    '#FFFFFF',
    '#F8F9FA',
    '#FFE8D6',
    '#FFD166',
    '#E0FBFC',
    '#CDE7BE',
    '#FFCAD4',
    '#D9EAFD',
    '#000000',
    '#1B1B1B',
  ];

  static const Set<String> _allowedImageExtensions = <String>{
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'heif',
  };

  static const Set<String> _allowedVideoExtensions = <String>{
    'mp4',
    'mov',
    'm4v',
    'webm',
    'mkv',
    'avi',
  };

  String _selectedBackgroundColor = '#121212';
  String _selectedTextColor = '#FFFFFF';
  TextAlign _selectedTextAlign = TextAlign.center;

  final Set<String> _selectedAudienceIds = <String>{};
  final Map<String, StoryAudienceUser> _selectedAudienceUsers = <String, StoryAudienceUser>{};

  bool get _isBusy => _submitting;
  bool get _isTextStory => _selectedMediaType == StoryMediaType.text;
  bool get _isImageStory => _selectedMediaType == StoryMediaType.image;
  bool get _isVideoStory => _selectedMediaType == StoryMediaType.video;

  AppLocalizations get l10n => AppLocalizations.of(context)!;

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  bool get _isArabicUi => Directionality.of(context) == TextDirection.rtl;

  String _alignmentSectionTitle() => l10n.storyTextAlignTitle;

  String _alignmentSectionSubtitle() => l10n.storyTextAlignSubtitle;

  IconData _alignmentIcon(TextAlign align) {
    final isRtl = _isArabicUi;

    switch (align) {
      case TextAlign.left:
        return isRtl
            ? Icons.format_align_right_rounded
            : Icons.format_align_left_rounded;
      case TextAlign.right:
        return isRtl
            ? Icons.format_align_left_rounded
            : Icons.format_align_right_rounded;
      case TextAlign.center:
        return Icons.format_align_center_rounded;
      default:
        return Icons.format_align_center_rounded;
    }
  }

  String _alignmentLabel(TextAlign align) {
    switch (align) {
      case TextAlign.left:
        return _isArabicUi ? l10n.storyTextAlignStart : l10n.storyTextAlignLeft;
      case TextAlign.right:
        return _isArabicUi ? l10n.storyTextAlignEnd : l10n.storyTextAlignRight;
      case TextAlign.center:
        return l10n.storyTextAlignCenter;
      default:
        return l10n.storyTextAlignCenter;
    }
  }

  TextAlign _effectivePreviewTextAlign(String text) {
    if (_selectedTextAlign != TextAlign.center) {
      return _selectedTextAlign;
    }

    final trimmed = text.trim();
    if (trimmed.isEmpty) return TextAlign.center;

    final hasLineBreak = trimmed.contains('\n');
    final words = trimmed.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).length;
    final isLong = trimmed.length > 32 || words > 5;

    return (hasLineBreak || isLong) ? TextAlign.left : TextAlign.center;
  }

  CrossAxisAlignment _effectivePreviewCrossAxisAlignment(TextAlign align) {
    switch (align) {
      case TextAlign.left:
        return CrossAxisAlignment.start;
      case TextAlign.right:
        return CrossAxisAlignment.end;
      case TextAlign.center:
        return CrossAxisAlignment.center;
      default:
        return CrossAxisAlignment.center;
    }
  }

  Alignment _effectivePreviewBoxAlignment(TextAlign align) {
    switch (align) {
      case TextAlign.left:
        return Alignment.centerLeft;
      case TextAlign.right:
        return Alignment.centerRight;
      case TextAlign.center:
        return Alignment.center;
      default:
        return Alignment.center;
    }
  }

  double _dynamicPreviewFontSize({
    required String text,
    required double baseFontSize,
    required double maxWidth,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return baseFontSize.clamp(18.0, 30.0);
    }

    final lines = '\n'.allMatches(trimmed).length + 1;
    final words = trimmed.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).length;
    final length = trimmed.length;

    double size = baseFontSize;

    if (length <= 20 && lines == 1) {
      size = 30;
    } else if (length <= 60 && lines <= 2) {
      size = 24;
    } else if (length <= 120 && lines <= 3) {
      size = 20;
    } else {
      size = 18;
    }

    if (lines >= 4) size -= 1.5;
    if (lines >= 6) size -= 1.5;
    if (words >= 18) size -= 1.0;

    if (maxWidth < 320) size -= 1.5;
    if (maxWidth > 430 && length < 28) size += 1.0;

    return size.clamp(16.0, 32.0);
  }

  MainAxisAlignment _linkPreviewAlignment(TextAlign align) {
    switch (align) {
      case TextAlign.left:
        return MainAxisAlignment.start;
      case TextAlign.right:
        return MainAxisAlignment.end;
      case TextAlign.center:
        return MainAxisAlignment.center;
      default:
        return MainAxisAlignment.center;
    }
  }

  double _storyPreviewTextFontSize(String text, double width) {
    final length = text.trim().length;

    if (width >= 1300) {
      if (length <= 18) return 42;
      if (length <= 45) return 34;
      if (length <= 100) return 28;
      return 24;
    }

    if (width >= 900) {
      if (length <= 18) return 36;
      if (length <= 45) return 30;
      if (length <= 100) return 25;
      return 22;
    }

    if (width >= 600) {
      if (length <= 18) return 30;
      if (length <= 45) return 25;
      if (length <= 100) return 21;
      return 18;
    }

    if (length <= 18) return 24;
    if (length <= 45) return 21;
    if (length <= 100) return 18;
    return 16;
  }

  double _storyPreviewTextCardMaxWidth(double width) {
    if (width >= 1200) return 620;
    if (width >= 900) return 560;
    if (width >= 700) return 500;
    return width;
  }

  double _storyPreviewTextHorizontalPadding(double width) {
    if (width >= 1000) return 30;
    if (width >= 700) return 24;
    return 18;
  }

  double _storyPreviewTextVerticalPadding(double width) {
    if (width >= 1000) return 30;
    if (width >= 700) return 24;
    return 18;
  }

  double _pageHorizontalPadding(double width) {
    if (width >= 1360) return 28;
    if (width >= 1120) return 24;
    if (width >= 760) return 18;
    return 16;
  }

  double _contentMaxWidth(double width) {
    if (width >= 1680) return 1460;
    if (width >= 1440) return 1360;
    if (width >= 1200) return 1240;
    if (width >= 760) return 940;
    return 720;
  }


  bool _showDesktopSidePreview(double width) => width >= 1120;

  bool _showInlinePreview(double width) => !_showDesktopSidePreview(width);

  double _mobilePreviewAspectRatio(double width) {
    if (width >= 700) return 9 / 12.5;
    return 9 / 14.5;
  }

  double _desktopPreviewAspectRatio(double width) {
    if (width >= 1400) return 9 / 16;
    return 9 / 15.2;
  }

  double _previewMaxHeight(double width, double screenHeight) {
    if (width >= 1120) {
      return screenHeight.clamp(620.0, 900.0) * 0.70;
    }
    if (screenHeight <= 700) return 370;
    if (screenHeight <= 820) return 430;
    return 520;
  }

  BoxDecoration _mwCardDecoration({
    double radius = 24,
    double alpha = 0.72, // darker default
    bool warm = false,
  }) {
    final baseColor = Colors.black;

    return BoxDecoration(
      color: baseColor.withValues(alpha: alpha),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: Colors.white.withValues(alpha: warm ? 0.10 : 0.08),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.45),
          blurRadius: 28,
          offset: const Offset(0, 14),
        ),
        if (warm)
          BoxShadow(
            color: kGoldDeep.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
      ],
    );
  }


  @override
  void initState() {
    super.initState();
    _textController.addListener(_refreshPreview);
    _linkController.addListener(_refreshPreview);
  }

  @override
  void dispose() {
    _textController.removeListener(_refreshPreview);
    _linkController.removeListener(_refreshPreview);
    _textController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  void _refreshPreview() {
    if (mounted) setState(() {});
  }

  List<String> _effectiveCustomViewerIds() {
    return _selectedAudienceIds.toList();
  }

  List<StoryAudienceUser> _selectedAudienceUserList() {
    final users = _selectedAudienceIds
        .map((id) => _selectedAudienceUsers[id])
        .whereType<StoryAudienceUser>()
        .toList()
      ..sort((a, b) => a.displayLabel.toLowerCase().compareTo(
        b.displayLabel.toLowerCase(),
      ));

    return users;
  }

  String _selectedAudienceSummaryLabel() {
    final users = _selectedAudienceUserList();

    if (users.isEmpty) {
      return l10n.storyAudienceChoose;
    }

    if (users.length == 1) return users.first.displayLabel;
    if (users.length == 2) {
      return '${users.first.displayLabel} • ${users.last.displayLabel}';
    }

    return '${users.first.displayLabel}, ${users[1].displayLabel} +${users.length - 2}';
  }

  int get _customViewerCount => _selectedAudienceIds.length;

  void _setMediaType(StoryMediaType type) {
    if (_submitting) return;

    setState(() {
      if (_selectedMediaType != type) {
        _selectedMediaType = type;

        if (type == StoryMediaType.text) {
          _selectedFile = null;
          _videoThumbBytes = null;
        } else if ((_selectedFile != null) &&
            ((_isImageStory && type == StoryMediaType.video) ||
                (_isVideoStory && type == StoryMediaType.image))) {
          _selectedFile = null;
          _videoThumbBytes = null;
        }
      }
    });
  }

  Future<void> _showMediaPickerSheet() async {
    if (_submitting || _isTextStory) return;

    FocusScope.of(context).unfocus();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (context) {
        final theme = Theme.of(context);

        return SafeArea(
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: MediaQuery.of(context).textScaler.clamp(
                minScaleFactor: 0.9,
                maxScaleFactor: 1.05,
              ),
            ),
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: _mwCardDecoration(
                  radius: 28,
                  alpha: 0.78, // 🔥 darker like your screenshot
                  warm: true,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isImageStory
                          ? l10n.mediaSheetSelectImage
                          : l10n.mediaSheetSelectVideo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isImageStory
                          ? l10n.mediaSheetImageSubtitle
                          : l10n.mediaSheetVideoSubtitle,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _SheetActionTile(
                      icon: _isImageStory
                          ? Icons.photo_library_outlined
                          : Icons.video_library_outlined,
                      title: _isImageStory
                          ? l10n.mediaGallery
                          : l10n.mediaGalleryVideo,
                      subtitle: _isImageStory
                          ? l10n.mediaGallerySubtitle
                          : l10n.mediaGalleryVideoSubtitle,
                      onTap: () async {
                        Navigator.of(context).pop();
                        if (_isImageStory) {
                          await _pickImage();
                        } else {
                          await (kIsWeb
                              ? _pickVideoWebFallback()
                              : _pickVideo());
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    _SheetActionTile(
                      icon: _isImageStory
                          ? Icons.camera_alt_outlined
                          : Icons.videocam_outlined,
                      title:
                      _isImageStory ? l10n.mediaCamera : l10n.mediaRecord,
                      subtitle: _isImageStory
                          ? l10n.mediaCameraSubtitle
                          : l10n.mediaRecordSubtitle,
                      onTap: () async {
                        Navigator.of(context).pop();
                        if (_isImageStory) {
                          await _captureImage();
                        } else {
                          await _captureVideo();
                        }
                      },
                    ),
                    if (_selectedFile != null) ...[
                      const SizedBox(height: 10),
                      _SheetActionTile(
                        icon: Icons.delete_outline_rounded,
                        title: l10n.mediaRemove,
                        subtitle: l10n.mediaRemoveSubtitle,
                        isDanger: true,
                        onTap: () {
                          Navigator.of(context).pop();
                          _clearSelectedMedia();
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Stream<List<StoryAudienceUser>> _customAudienceStream() {
    return _audienceService.customAudienceFriendsStream(
      currentUid: _currentUid,
    );
  }

  Future<void> _openCustomAudiencePicker() async {
    if (_submitting || _visibility != StoryVisibility.custom) return;

    final initialSelected = <String>{..._selectedAudienceIds};

    debugPrint('CreateStoryScreen currentUid=$_currentUid');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _CustomAudiencePickerSheet(
          stream: _customAudienceStream(),
          initialSelectedIds: initialSelected,
          selectedUsersById: Map<String, StoryAudienceUser>.from(_selectedAudienceUsers),
          onApply: (selectedUsers) {
            if (!mounted) return;
            setState(() {
              _selectedAudienceIds
                ..clear()
                ..addAll(selectedUsers.map((user) => user.id));

              _selectedAudienceUsers
                ..clear()
                ..addEntries(
                  selectedUsers.map(
                        (user) => MapEntry<String, StoryAudienceUser>(user.id, user),
                  ),
                );
            });
          },
        );
      },
    );
  }

  String _fileExtension(String name) {
    final index = name.lastIndexOf('.');
    if (index == -1 || index == name.length - 1) return '';
    return name.substring(index + 1).toLowerCase().trim();
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = <String>['B', 'KB', 'MB', 'GB'];
    double size = bytes.toDouble();
    int unitIndex = 0;

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    final decimals = size >= 100 || unitIndex == 0 ? 0 : 1;
    return '${size.toStringAsFixed(decimals)} ${units[unitIndex]}';
  }

  Future<int> _getFileSizeBytes(PlatformFile file) async {
    if (file.size > 0) return file.size;
    if (file.bytes != null && file.bytes!.isNotEmpty) return file.bytes!.length;

    final path = file.path;
    if (!kIsWeb && path != null && path.trim().isNotEmpty) {
      try {
        final rawFile = ioFile(path.trim());
        return await rawFile.length();
      } catch (_) {
        return 0;
      }
    }

    return 0;
  }

  bool _isValidHttpUrl(String input) {
    final value = input.trim();

    if (value.isEmpty) return true;

    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    if (!uri.hasScheme || !uri.hasAuthority) return false;
    return uri.scheme == 'http' || uri.scheme == 'https';
  }

  Future<Duration?> _readVideoDuration(PlatformFile file) async {
    VideoPlayerController? controller;

    try {
      if (kIsWeb) {
        final bytes = file.bytes;
        if (bytes == null || bytes.isEmpty) return null;

        controller = VideoPlayerController.networkUrl(
          Uri.dataFromBytes(bytes, mimeType: 'video/mp4'),
        );
      } else {
        final path = file.path;
        if (path == null || path.trim().isEmpty) return null;
        controller = VideoPlayerController.file(ioFile(path.trim()));
      }

      await controller.initialize();
      return controller.value.duration;
    } catch (_) {
      return null;
    } finally {
      await controller?.dispose();
    }
  }

  Future<String?> _validateSelectedMediaFile(
      PlatformFile file,
      StoryMediaType mediaType,
      ) async {
    final ext = _fileExtension(file.name);
    final sizeBytes = await _getFileSizeBytes(file);

    if (mediaType == StoryMediaType.image) {
      if (!_allowedImageExtensions.contains(ext)) {
        return l10n.storyValidationInvalidImageType;
      }

      if (sizeBytes > _maxImageBytes) {
        return l10n.storyValidationImageTooLarge(
          _formatBytes(_maxImageBytes),
        );
      }

      return null;
    }

    if (mediaType == StoryMediaType.video) {
      if (!_allowedVideoExtensions.contains(ext)) {
        return l10n.storyValidationInvalidVideoType;
      }

      if (sizeBytes > _maxVideoBytes) {
        return l10n.storyValidationVideoTooLarge(
          _formatBytes(_maxVideoBytes),
        );
      }

      final duration = await _readVideoDuration(file);
      if (duration != null && duration.inSeconds > _maxVideoSeconds) {
        return l10n.storyValidationVideoTooLong(_maxVideoSeconds);
      }

      return null;
    }

    return null;
  }

  Future<void> _applyValidatedMediaSelection(
      PlatformFile file,
      StoryMediaType mediaType, {
        Uint8List? thumb,
      }) async {
    final validationError = await _validateSelectedMediaFile(file, mediaType);
    if (validationError != null) {
      _showError(validationError);
      return;
    }

    if (!mounted) return;

    setState(() {
      _selectedMediaType = mediaType;
      _selectedFile = file;
      _videoThumbBytes = mediaType == StoryMediaType.video ? thumb : null;
    });
  }

  String? _validateBeforeSubmit() {
    final text = _textController.text.trim();
    final customIds = _effectiveCustomViewerIds();
    final linkUrl = _linkController.text.trim();

    if (_visibility == StoryVisibility.custom && customIds.isEmpty) {
      return l10n.storyErrorCustomIds;
    }

    if (_isTextStory) {
      if (text.isEmpty) {
        return l10n.storyErrorEnterText;
      }

      if (text.length > _maxTextStoryChars) {
        return l10n.storyValidationTextTooLong(_maxTextStoryChars);
      }
    } else {
      if (_selectedFile == null) {
        return l10n.storyErrorSelectFile;
      }

      if (text.length > _maxCaptionChars) {
        return l10n.storyValidationCaptionTooLong(_maxCaptionChars);
      }
    }

    if (linkUrl.isNotEmpty && !_isValidHttpUrl(linkUrl)) {
      return l10n.storyValidationInvalidLink;
    }

    return null;
  }

  Future<void> _captureImage() async {
    if (_submitting) return;

    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );

      if (picked == null) return;

      PlatformFile file;
      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        file = PlatformFile(
          name: picked.name,
          size: bytes.length,
          bytes: bytes,
        );
      } else {
        file = PlatformFile(
          name: picked.name,
          path: picked.path,
          size: 0,
        );
      }

      await _applyValidatedMediaSelection(
        file,
        StoryMediaType.image,
      );
    } catch (_) {
      _showError(l10n.storyErrorImageCapture);
    }
  }

  Future<void> _captureVideo() async {
    if (_submitting) return;

    try {
      final XFile? picked = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(seconds: _maxVideoSeconds),
      );

      if (picked == null) return;

      PlatformFile file;
      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        file = PlatformFile(
          name: picked.name,
          size: bytes.length,
          bytes: bytes,
        );
      } else {
        file = PlatformFile(
          name: picked.name,
          path: picked.path,
          size: 0,
        );
      }

      Uint8List? thumb;
      try {
        thumb = await _repo.buildVideoThumbnailBytes(file);
      } catch (_) {
        thumb = null;
      }

      await _applyValidatedMediaSelection(
        file,
        StoryMediaType.video,
        thumb: thumb,
      );
    } catch (_) {
      _showError(l10n.storyErrorVideoRecord);
    }
  }

  Future<void> _pickImage() async {
    if (_submitting) return;

    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );

      if (picked == null) return;

      PlatformFile file;
      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        file = PlatformFile(
          name: picked.name,
          size: bytes.length,
          bytes: bytes,
          path: null,
        );
      } else {
        file = PlatformFile(
          name: picked.name,
          size: 0,
          path: picked.path,
        );
      }

      await _applyValidatedMediaSelection(
        file,
        StoryMediaType.image,
      );
    } catch (_) {
      _showError(l10n.storyErrorPickImage);
    }
  }

  Future<void> _pickVideo() async {
    if (_submitting) return;

    try {
      final XFile? picked = await _picker.pickVideo(
        source: ImageSource.gallery,
      );

      if (picked == null) return;

      PlatformFile file;
      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        file = PlatformFile(
          name: picked.name,
          size: bytes.length,
          bytes: bytes,
          path: null,
        );
      } else {
        file = PlatformFile(
          name: picked.name,
          size: 0,
          path: picked.path,
        );
      }

      Uint8List? thumb;
      try {
        thumb = await _repo.buildVideoThumbnailBytes(file);
      } catch (_) {
        thumb = null;
      }

      await _applyValidatedMediaSelection(
        file,
        StoryMediaType.video,
        thumb: thumb,
      );
    } catch (_) {
      _showError(l10n.storyErrorPickVideo);
    }
  }

  Future<void> _pickVideoWebFallback() async {
    if (_submitting) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi'],
      );

      final file = result?.files.firstOrNull;
      if (file == null) return;

      Uint8List? thumb;
      try {
        thumb = await _repo.buildVideoThumbnailBytes(file);
      } catch (_) {
        thumb = null;
      }

      await _applyValidatedMediaSelection(
        file,
        StoryMediaType.video,
        thumb: thumb,
      );
    } catch (_) {
      _showError(l10n.storyErrorPickVideo);
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final text = _textController.text.trim();
    final customIds = _effectiveCustomViewerIds();
    final linkUrl = _linkController.text.trim();

    final formError = _validateBeforeSubmit();
    if (formError != null) {
      _showError(formError);
      return;
    }

    if (!_isTextStory && _selectedFile != null) {
      final mediaError = await _validateSelectedMediaFile(
        _selectedFile!,
        _selectedMediaType,
      );
      if (mediaError != null) {
        _showError(mediaError);
        return;
      }
    }

    setState(() {
      _submitting = true;
      _uploadProgress = _isTextStory ? null : 0.0;
    });

    try {
      if (_isTextStory) {
        await _repo.createTextStory(
          text: text,
          visibility: _visibility,
          allowedViewerIds: customIds,
          backgroundColor: _selectedBackgroundColor,
          textColor: _selectedTextColor,
          linkUrl: linkUrl.isEmpty ? null : linkUrl,
        );
      } else {
        await _repo.createMediaStory(
          file: _selectedFile!,
          mediaType: _selectedMediaType,
          visibility: _visibility,
          allowedViewerIds: customIds,
          text: text.isEmpty ? null : text,
          backgroundColor: _selectedBackgroundColor,
          textColor: _selectedTextColor,
          linkUrl: linkUrl.isEmpty ? null : linkUrl,
          onProgress: (p) {
            if (!mounted) return;
            setState(() {
              _uploadProgress = p;
            });
          },
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        _buildSnackBar(l10n.storySuccess),
      );

      Navigator.of(context).pop(true);
    } on FirebaseException catch (e, st) {
      debugPrint(
        'create story firebase error: code=${e.code}, message=${e.message}',
      );
      debugPrint('$st');

      String message;
      switch (e.code) {
        case 'unauthorized':
          message = l10n.storyErrorUploadBlocked;
          break;
        case 'permission-denied':
          message = l10n.storyErrorPermission;
          break;
        case 'canceled':
          message = l10n.storyErrorCanceled;
          break;
        default:
          message = (e.message ?? '').trim().isNotEmpty
              ? e.message!.trim()
              : l10n.storyErrorGeneric;
      }

      _showError(message);
    } catch (e, st) {
      debugPrint('create story error: $e');
      debugPrint('$st');
      _showError(l10n.storyErrorGeneric);
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _uploadProgress = null;
        });
      }
    }
  }

  void _clearSelectedMedia() {
    if (_submitting) return;
    setState(() {
      _selectedFile = null;
      _videoThumbBytes = null;
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(_buildSnackBar(message));
  }

  SnackBar _buildSnackBar(String message) {
    return SnackBar(
      content: Text(
        message,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      backgroundColor: kSurfaceAltColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Color _hexToColor(String hex) {
    var value = hex.trim().replaceFirst('#', '');
    if (value.length == 6) value = 'FF$value';
    return Color(int.parse(value, radix: 16));
  }

  String _colorToHex(Color color) {
    int toChannel(double value) => (value * 255.0).round().clamp(0, 255);

    String hex(int channel) =>
        channel.toRadixString(16).padLeft(2, '0').toUpperCase();

    return '#${hex(toChannel(color.r))}${hex(toChannel(color.g))}${hex(toChannel(color.b))}';
  }

  void _updateBackgroundColor(Color color) {
    setState(() {
      _selectedBackgroundColor = _colorToHex(color);
    });
  }

  void _updateTextColor(Color color) {
    setState(() {
      _selectedTextColor = _colorToHex(color);
    });
  }

  String _visibilityLabel(StoryVisibility v) {
    switch (v) {
      case StoryVisibility.public:
        return l10n.storyVisibilityPublic;
      case StoryVisibility.friends:
        return l10n.storyVisibilityFriends;
      case StoryVisibility.custom:
        return l10n.storyVisibilityCustom;
    }
  }

  String _typeLabel(StoryMediaType type) {
    switch (type) {
      case StoryMediaType.text:
        return l10n.storyTypeText;
      case StoryMediaType.image:
        return l10n.storyTypeImage;
      case StoryMediaType.video:
        return l10n.storyTypeVideo;
    }
  }

  Widget _buildTypeSelector() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: StoryMediaType.values.map((type) {
          final selected = _selectedMediaType == type;

          return Expanded(
            child: GestureDetector(
              onTap: () => _setMediaType(type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? kPrimaryGold : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      type == StoryMediaType.text
                          ? Icons.edit_rounded
                          : type == StoryMediaType.image
                          ? Icons.photo
                          : Icons.videocam,
                      color: selected ? Colors.black : Colors.white70,
                      size: 20,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _typeLabel(type),
                      style: TextStyle(
                        color: selected ? Colors.black : Colors.white70,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }


  Widget _buildVisibilitySelector(ThemeData theme) {
    return DropdownButtonFormField<StoryVisibility>(
      initialValue: _visibility,
      dropdownColor: kSurfaceColor,
      style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
      iconEnabledColor: Colors.white70,
      decoration: _inputDecoration(
        context,
        label: l10n.storyVisibilityLabel,
      ),
      items: StoryVisibility.values.map((v) {
        return DropdownMenuItem<StoryVisibility>(
          value: v,
          child: Text(
            _visibilityLabel(v),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: _submitting
          ? null
          : (value) {
        if (value == null) return;
        setState(() {
          _visibility = value;
        });
      },
    );
  }

  Widget _buildAudienceLauncher(BuildContext context) {
    return InkWell(
      onTap: _openCustomAudiencePicker,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.10),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
              child: const Icon(
                Icons.people_alt_outlined,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.storyAudienceChoose,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _selectedAudienceSummaryLabel(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white70,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedAudienceChips() {
    final selectedUsers = _selectedAudienceUserList();

    if (selectedUsers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: selectedUsers.map((user) {
        return InputChip(
          avatar: _AudienceChipAvatar(user: user),
          label: Text(
            user.displayLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          selected: true,
          showCheckmark: false,
          selectedColor: kPrimaryGold.withValues(alpha: 0.18),
          backgroundColor: Colors.white.withValues(alpha: 0.06),
          labelStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.10),
          ),
          onDeleted: _submitting
              ? null
              : () {
            setState(() {
              _selectedAudienceIds.remove(user.id);
              _selectedAudienceUsers.remove(user.id);
            });
          },
          deleteIconColor: Colors.white70,
        );
      }).toList(),
    );
  }

  Widget _buildCustomIdsField(BuildContext context) {
    if (_visibility != StoryVisibility.custom) {
      return const SizedBox.shrink();
    }

    final viewerLabel = l10n.storySelectedViewersCount(_customViewerCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAudienceLauncher(context),
        const SizedBox(height: 12),
        _buildSelectedAudienceChips(),
        if (_selectedAudienceIds.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MiniBadge(label: viewerLabel),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildTextField(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final maxChars = _isTextStory ? _maxTextStoryChars : _maxCaptionChars;
    final keyboardInset = media.viewInsets.bottom;

    return TextField(
      controller: _textController,
      enabled: !_submitting,
      minLines: _isTextStory ? 5 : 2,
      maxLines: _isTextStory ? 8 : 3,
      maxLength: maxChars,
      textAlign: _isTextStory ? _selectedTextAlign : TextAlign.start,
      textInputAction:
      _isTextStory ? TextInputAction.newline : TextInputAction.done,
      textCapitalization: TextCapitalization.sentences,
      keyboardAppearance: Brightness.dark,
      scrollPadding: EdgeInsets.fromLTRB(
        20,
        24,
        20,
        keyboardInset + 140,
      ),
      style: theme.textTheme.bodyLarge?.copyWith(
        color: Colors.white,
        height: 1.42,
      ),
      decoration: _inputDecoration(
        context,
        label: _isTextStory ? l10n.storyTextLabel : l10n.storyCaptionLabel,
        hint: _isTextStory ? l10n.storyTextHint : l10n.storyCaptionHint,
      ).copyWith(
        alignLabelWithHint: true,
        counterStyle: theme.textTheme.bodySmall?.copyWith(
          color: Colors.white54,
        ),
      ),
    );
  }

  Widget _buildLinkField(BuildContext context) {
    final theme = Theme.of(context);
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return TextField(
      controller: _linkController,
      enabled: !_submitting,
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.done,
      autocorrect: false,
      enableSuggestions: false,
      keyboardAppearance: Brightness.dark,
      scrollPadding: EdgeInsets.fromLTRB(
        20,
        24,
        20,
        keyboardInset + 120,
      ),
      style: theme.textTheme.bodyMedium?.copyWith(
        color: Colors.white,
        height: 1.35,
      ),
      decoration: _inputDecoration(
        context,
        label: l10n.storyLinkLabel,
        hint: l10n.storyLinkHint,
        prefixIcon: const Icon(Icons.link_rounded),
      ),
    );
  }

  InputDecoration _inputDecoration(
      BuildContext context, {
        required String label,
        String? hint,
        Widget? prefixIcon,
      }) {
    final theme = Theme.of(context);

    OutlineInputBorder border(Color color) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: color),
      );
    }

    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon,
      filled: true,
      fillColor: const Color(0xFF070707),
      labelStyle: theme.textTheme.bodyMedium?.copyWith(
        color: Colors.white70,
      ),
      hintStyle: theme.textTheme.bodyMedium?.copyWith(
        color: Colors.white38,
      ),
      border: border(Colors.white.withValues(alpha: 0.10)),
      enabledBorder: border(Colors.white.withValues(alpha: 0.10)),
      focusedBorder: border(kPrimaryGold.withValues(alpha: 0.95)),
      errorBorder: border(kErrorColor.withValues(alpha: 0.75)),
      focusedErrorBorder: border(kErrorColor.withValues(alpha: 0.95)),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 18,
      ),
      isDense: false,
    );
  }

  Widget _buildTextAlignmentPicker(ThemeData theme) {
    if (!_isTextStory) return const SizedBox.shrink();

    const alignOptions = <TextAlign>[
      TextAlign.left,
      TextAlign.center,
      TextAlign.right,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _alignmentSectionTitle(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _alignmentSectionSubtitle(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white60,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: alignOptions.map((align) {
              final selected = _selectedTextAlign == align;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Tooltip(
                    message: _alignmentLabel(align),
                    child: Semantics(
                      label: _alignmentLabel(align),
                      button: true,
                      selected: selected,
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedTextAlign = align),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: selected
                                ? kPrimaryGold
                                : Colors.white.withValues(alpha: 0.02),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: selected
                                ? [
                              BoxShadow(
                                color: kPrimaryGold.withValues(alpha: 0.18),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ]
                                : null,
                          ),
                          child: Icon(
                            _alignmentIcon(align),
                            color: selected ? Colors.black : Colors.white70,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildColorPickerSection(ThemeData theme) {
    if (!_isTextStory) return const SizedBox.shrink();

    final selectedBackground = _hexToColor(_selectedBackgroundColor);
    final selectedText = _hexToColor(_selectedTextColor);

    Widget buildPaletteRow({
      required List<String> palette,
      required String selectedHex,
      required ValueChanged<Color> onSelected,
      required bool darkMode,
    }) {
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: palette.map((hex) {
          final color = _hexToColor(hex);
          final selected = selectedHex.toUpperCase() == hex.toUpperCase();

          return Tooltip(
            message: hex,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSelected(color),
                borderRadius: BorderRadius.circular(999),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: Border.all(
                      color: selected
                          ? kPrimaryGold
                          : Colors.white.withValues(alpha: 0.18),
                      width: selected ? 2.4 : 1.1,
                    ),
                    boxShadow: [
                      if (selected)
                        BoxShadow(
                          color: kPrimaryGold.withValues(alpha: 0.28),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: darkMode ? 0.30 : 0.18,
                        ),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: selected
                      ? Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: ThemeData.estimateBrightnessForColor(color) ==
                        Brightness.dark
                        ? Colors.white
                        : Colors.black,
                  )
                      : null,
                ),
              ),
            ),
          );
        }).toList(),
      );
    }

    return _SectionCard(
      title: l10n.storyStyleTitle,
      subtitle: l10n.storyStyleSubtitle,
      warm: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTextAlignmentPicker(theme),
          const SizedBox(height: 20),
          _ColorControlCard(
            title: l10n.storyBackgroundColor,
            subtitle: l10n.storyBackgroundColorSubtitle,
            trailing: _LiveColorChip(
              color: selectedBackground,
              foreground: selectedText,
              label: l10n.storyBackgroundPreviewLabel,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildPaletteRow(
                  palette: _backgroundPalette,
                  selectedHex: _selectedBackgroundColor,
                  onSelected: _updateBackgroundColor,
                  darkMode: true,
                ),
                const SizedBox(height: 14),
                _SpectrumColorPicker(
                  selectedColor: selectedBackground,
                  onChanged: _updateBackgroundColor,
                  darkMode: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _ColorControlCard(
            title: l10n.storyTextColor,
            subtitle: l10n.storyTextColorSubtitle,
            trailing: _LiveColorChip(
              color: selectedText,
              foreground: selectedBackground,
              label: l10n.storyTextPreviewLabel,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildPaletteRow(
                  palette: _textPalette,
                  selectedHex: _selectedTextColor,
                  onSelected: _updateTextColor,
                  darkMode: false,
                ),
                const SizedBox(height: 14),
                _SpectrumColorPicker(
                  selectedColor: selectedText,
                  onChanged: _updateTextColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaActions(ThemeData theme) {
    if (_isTextStory) return const SizedBox.shrink();

    final hasFile = _selectedFile != null;

    return _SectionCard(
      title: l10n.storyMediaTitle,
      subtitle: _isImageStory
          ? l10n.storyMediaSubtitleImage
          : l10n.storyMediaSubtitleVideo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _showMediaPickerSheet,
            borderRadius: BorderRadius.circular(22),
            child: Ink(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.50),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: hasFile
                      ? kPrimaryGold.withValues(alpha: 0.24)
                      : Colors.white.withValues(alpha: 0.08),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                  if (hasFile)
                    BoxShadow(
                      color: kGoldDeep.withValues(alpha: 0.08),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: mwGradient,
                      boxShadow: [
                        BoxShadow(
                          color: kGoldDeep.withValues(alpha: 0.20),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Icon(
                      _isImageStory
                          ? (hasFile
                          ? Icons.photo_library_rounded
                          : Icons.add_photo_alternate_outlined)
                          : (hasFile
                          ? Icons.video_file_rounded
                          : Icons.video_call_outlined),
                      color: Colors.black,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          hasFile
                              ? l10n.storyChangeMedia
                              : l10n.storySelectMedia,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hasFile
                              ? _selectedFile!.name
                              : l10n.storyPickerHint,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: hasFile ? Colors.white70 : Colors.white60,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.06),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                    child: const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white70,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _isImageStory
                      ? Icons.info_outline_rounded
                      : Icons.ondemand_video_rounded,
                  size: 18,
                  color: Colors.white60,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.storyMediaRulesTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isImageStory
                            ? l10n.storyValidationImageRules(
                          _formatBytes(_maxImageBytes),
                        )
                            : l10n.storyValidationVideoRules(
                          _formatBytes(_maxVideoBytes),
                          _maxVideoSeconds,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white60,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedMediaPreview() {
    final file = _selectedFile;
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final screenHeight = media.size.height;

    Widget buildEmptyState({
      required IconData icon,
      required String text,
    }) {
      return _buildStoryPreviewViewport(
        screenWidth: screenWidth,
        screenHeight: screenHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: MediaQuery(
                data: media.copyWith(
                  textScaler: media.textScaler.clamp(
                    minScaleFactor: 0.9,
                    maxScaleFactor: 1.05,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      color: Colors.white38,
                      size: 42,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white60,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget brokenImageFallback() {
      return const Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: 48,
          color: Colors.white70,
        ),
      );
    }

    if (file == null) {
      return buildEmptyState(
        icon: Icons.auto_awesome_mosaic_rounded,
        text: _isImageStory
            ? l10n.storyNoImageSelected
            : l10n.storyNoVideoSelected,
      );
    }

    final effectiveSize = file.size > 0 ? file.size : (file.bytes?.length ?? 0);
    final sizeLabel = '${file.name} • ${_formatBytes(effectiveSize)}';

    Widget mediaChild = const SizedBox.shrink();

    if (_isImageStory) {
      if (kIsWeb && file.bytes != null && file.bytes!.isNotEmpty) {
        mediaChild = Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.black),
            InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: Image.memory(
                  file.bytes!,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (context, error, stackTrace) =>
                      brokenImageFallback(),
                ),
              ),
            ),
          ],
        );
      } else if (!kIsWeb && (file.path ?? '').trim().isNotEmpty) {
        mediaChild = Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.black),
            InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: Image(
                  image: FileImageAdapter(file.path!.trim()),
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (context, error, stackTrace) =>
                      brokenImageFallback(),
                ),
              ),
            ),
          ],
        );
      } else {
        mediaChild = Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: const Icon(
            Icons.image_outlined,
            size: 48,
            color: Colors.white70,
          ),
        );
      }
    } else if (_isVideoStory) {
      mediaChild = Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black),
          if (_videoThumbBytes != null && _videoThumbBytes!.isNotEmpty)
            Center(
              child: Image.memory(
                _videoThumbBytes!,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.black,
                ),
              ),
            )
          else
            Container(
              color: Colors.white.withValues(alpha: 0.03),
            ),
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.04),
              ),
              boxShadow: [
                BoxShadow(
                  color: kGoldDeep.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.48),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                size: 38,
                color: Colors.white,
              ),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.storyVideoSelected,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return _MediaPreviewCard(
      onRemove: _submitting ? null : _clearSelectedMedia,
      footerText: sizeLabel,
      child: _buildStoryPreviewViewport(
        screenWidth: screenWidth,
        screenHeight: screenHeight,
        child: mediaChild,
      ),
    );
  }

  double _previewCardMaxWidth(double width) {
    if (_showDesktopSidePreview(width)) return 420;
    if (width >= 700) return 460;
    return double.infinity;
  }

  Widget _buildStoryPreviewViewport({
    required Widget child,
    required double screenWidth,
    required double screenHeight,
  }) {
    final previewAspectRatio = _showDesktopSidePreview(screenWidth)
        ? _desktopPreviewAspectRatio(screenWidth)
        : _mobilePreviewAspectRatio(screenWidth);

    final maxHeight = _previewMaxHeight(screenWidth, screenHeight);
    final maxWidth = _previewCardMaxWidth(screenWidth);

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        ),
        child: AspectRatio(
          aspectRatio: previewAspectRatio,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              color: Color.lerp(kSurfaceColor, Colors.black, 0.42),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextStoryPreview(ThemeData theme, double availableWidth) {
    if (!_isTextStory) return const SizedBox.shrink();

    final media = MediaQuery.of(context);
    final width = media.size.width;
    final screenHeight = media.size.height;

    final bg = _hexToColor(_selectedBackgroundColor);
    final fg = _hexToColor(_selectedTextColor);
    final text = _textController.text.trim();
    final link = _linkController.text.trim();

    final fontSize = _storyPreviewTextFontSize(text, width);
    final cardMaxWidth = _storyPreviewTextCardMaxWidth(availableWidth);
    final textHPad = _storyPreviewTextHorizontalPadding(width);
    final textVPad = _storyPreviewTextVerticalPadding(width);
    final effectiveTextAlign = _effectivePreviewTextAlign(text);

    final previewAspectRatio = _showDesktopSidePreview(width)
        ? _desktopPreviewAspectRatio(width)
        : _mobilePreviewAspectRatio(width);

    final maxHeight = _previewMaxHeight(width, screenHeight);

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: _showDesktopSidePreview(width) ? 420 : 460,
          maxHeight: maxHeight,
        ),
        child: AspectRatio(
          aspectRatio: previewAspectRatio,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: RadialGradient(
                center: const Alignment(0, -0.18),
                radius: 1.18,
                colors: [
                  Color.lerp(bg, Colors.white, 0.03) ?? bg,
                  Color.lerp(bg, Colors.black, 0.06) ?? bg,
                  Color.lerp(bg, Colors.black, 0.34) ?? bg,
                ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.03),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.10),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                ),
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 2, 2, 10),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: 0.24),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.10),
                              ),
                            ),
                            child: const Icon(
                              Icons.person_rounded,
                              color: Colors.white70,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              l10n.storyYourStory,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l10n.storyNow,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: Colors.white70,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: cardMaxWidth),
                          child: MediaQuery(
                            data: media.copyWith(
                              textScaler: media.textScaler.clamp(
                                minScaleFactor: 0.9,
                                maxScaleFactor: 1.1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: _effectivePreviewCrossAxisAlignment(effectiveTextAlign),
                              children: [
                                Flexible(
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final maxWidth = constraints.maxWidth;
                                      final previewText = text.isEmpty
                                          ? l10n.storyPreviewPlaceholder
                                          : text;

                                      final computedFontSize = _dynamicPreviewFontSize(
                                        text: previewText,
                                        baseFontSize: fontSize,
                                        maxWidth: maxWidth,
                                      );

                                      return AnimatedContainer(
                                        duration: const Duration(milliseconds: 220),
                                        curve: Curves.easeOutCubic,
                                        width: double.infinity,
                                        alignment: _effectivePreviewBoxAlignment(effectiveTextAlign),
                                        padding: EdgeInsets.symmetric(
                                          horizontal: textHPad,
                                          vertical: textVPad * 0.9,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.10),
                                          borderRadius: BorderRadius.circular(30),
                                          border: Border.all(
                                            color: Colors.white.withValues(alpha: 0.05),
                                          ),
                                        ),
                                        child: SingleChildScrollView(
                                          physics: const ClampingScrollPhysics(),
                                          child: AnimatedDefaultTextStyle(
                                            duration: const Duration(milliseconds: 220),
                                            curve: Curves.easeOutCubic,
                                            style: theme.textTheme.headlineMedium!.copyWith(
                                              color: fg,
                                              fontWeight: FontWeight.w500,
                                              fontSize: computedFontSize,
                                              height: 1.25,
                                            ),
                                            child: Text(
                                              previewText,
                                              textAlign: effectiveTextAlign,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                if (link.isNotEmpty) ...[
                                  const SizedBox(height: 14),
                                  Align(
                                    alignment: effectiveTextAlign == TextAlign.left
                                        ? Alignment.centerLeft
                                        : effectiveTextAlign == TextAlign.right
                                        ? Alignment.centerRight
                                        : Alignment.center,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.20),
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(
                                          color: fg.withValues(alpha: 0.26),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment: _linkPreviewAlignment(effectiveTextAlign),
                                        children: [
                                          Icon(
                                            Icons.open_in_new_rounded,
                                            size: 16,
                                            color: fg,
                                          ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              link,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: effectiveTextAlign,
                                              style: theme.textTheme.labelLarge?.copyWith(
                                                color: fg,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgress(ThemeData theme) {
    if (_uploadProgress == null) return const SizedBox.shrink();

    final pct = ((_uploadProgress ?? 0) * 100).clamp(0, 100).toInt();

    return _SectionCard(
      title: l10n.storyUploadingTitle,
      subtitle: l10n.storyUploadingSubtitle,
      warm: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$pct%',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: _uploadProgress,
              backgroundColor: Colors.white.withValues(alpha: 0.10),
              valueColor: const AlwaysStoppedAnimation<Color>(kPrimaryGold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopSummary(ThemeData theme) {
    final visibilityText = _visibilityLabel(_visibility);
    final typeText = _typeLabel(_selectedMediaType);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _mwCardDecoration(
        radius: 28,
        alpha: 0.66,
        warm: true,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: mwGradient,
              boxShadow: [
                BoxShadow(
                  color: kGoldDeep.withValues(alpha: 0.24),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.auto_stories_rounded,
              color: Colors.black,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: MediaQuery.of(context).textScaler.clamp(
                  minScaleFactor: 0.9,
                  maxScaleFactor: 1.05,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.storyCreateTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isTextStory
                        ? l10n.storyDetailsSubtitleText
                        : l10n.storyDetailsSubtitleMedia,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MiniBadge(label: typeText),
                      _MiniBadge(label: visibilityText),
                      if (!_isTextStory && _selectedFile != null)
                        _MiniBadge(label: _selectedFile!.name),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildInlinePreviewSection(ThemeData theme, double availableWidth) {
    return _SectionCard(
      title: l10n.storyPreviewTitle,
      subtitle: _isTextStory ? l10n.storyPreviewText : l10n.storyPreviewMedia,
      warm: true,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: KeyedSubtree(
          key: ValueKey(_selectedMediaType.name),
          child: _isTextStory
              ? _buildTextStoryPreview(theme, availableWidth)
              : _buildSelectedMediaPreview(),
        ),
      ),
    );
  }

  Widget _buildMainForm(
      ThemeData theme, {
        required bool showInlinePreview,
        required double availableWidth,
      }) {
    return _SectionCard(
      title: l10n.storyDetailsTitle,
      subtitle: _isTextStory
          ? l10n.storyDetailsSubtitleText
          : l10n.storyDetailsSubtitleMedia,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildVisibilitySelector(theme),
          const SizedBox(height: 16),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: _buildCustomIdsField(context),
          ),
          if (_visibility == StoryVisibility.custom) const SizedBox(height: 16),
          _buildTextField(context),
          const SizedBox(height: 16),
          _buildLinkField(context),
          if (showInlinePreview && _isTextStory) ...[
            const SizedBox(height: 18),
            _buildInlinePreviewSection(theme, availableWidth),
          ],
        ],
      ),
    );
  }


  Widget _buildDesktopPreviewColumn(ThemeData theme, double width) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title: l10n.storyPreviewTitle,
          subtitle: _isTextStory ? l10n.storyPreviewText : l10n.storyPreviewMedia,
          warm: true,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: KeyedSubtree(
              key: ValueKey(_selectedMediaType.name),
              child: _isTextStory
                  ? _buildTextStoryPreview(theme, width * 0.34)
                  : _buildSelectedMediaPreview(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_uploadProgress != null) _buildProgress(theme),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final width = size.width;
    final theme = Theme.of(context);

    final showSidePreview = _showDesktopSidePreview(width);
    final showInlinePreview = _showInlinePreview(width);

    final horizontalPadding = _pageHorizontalPadding(width);
    final maxWidth = _contentMaxWidth(width);

    final formColumn = <Widget>[
      _buildTopSummary(theme),
      const SizedBox(height: 16),
      _SectionCard(
        title: l10n.storyTypeTitle,
        subtitle: l10n.storyTypeSubtitle,
        child: _buildTypeSelector(),
      ),
      const SizedBox(height: 16),
      _buildMainForm(
        theme,
        showInlinePreview: showInlinePreview,
        availableWidth: width - (horizontalPadding * 2),
      ),
      if (_isTextStory) ...[
        const SizedBox(height: 16),
        _buildColorPickerSection(theme),
      ],
      if (!_isTextStory) ...[
        const SizedBox(height: 16),
        _buildMediaActions(theme),
        if (showInlinePreview) ...[
          const SizedBox(height: 16),
          _buildInlinePreviewSection(theme, width - (horizontalPadding * 2)),
        ],
      ],
      if (!showSidePreview && _uploadProgress != null) ...[
        const SizedBox(height: 16),
        _buildProgress(theme),
      ],
      const SizedBox(height: 20),
      SizedBox(
        height: 56,
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _isBusy ? null : _submit,
          icon: _submitting
              ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
            ),
          )
              : const Icon(Icons.send_rounded),
          label: Text(
            _submitting ? l10n.storyPosting : l10n.storyPost,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimaryGold,
            foregroundColor: Colors.black,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: Colors.black,
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.94),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          l10n.storyCreateTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        leading: Navigator.of(context).canPop()
            ? IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        )
            : null,
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: MwBackground(
          reduceEffects: true,
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.54),
                          Colors.black.withValues(alpha: 0.32),
                          Colors.black.withValues(alpha: 0.74),
                        ],
                        stops: const [0.0, 0.34, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 0.95,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.34),
                          Colors.black.withValues(alpha: 0.58),
                        ],
                        stops: const [0.0, 0.68, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                bottom: false,
                child: AbsorbPointer(
                  absorbing: _submitting,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final media = MediaQuery.of(context);
                      final keyboardInset = media.viewInsets.bottom;
                      final safeBottom = media.padding.bottom;
                      final topSpacing =
                          kToolbarHeight + media.padding.top + 12;

                      return AnimatedPadding(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        padding: EdgeInsets.only(bottom: keyboardInset),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: maxWidth,
                              minHeight: 0,
                            ),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                horizontalPadding,
                                topSpacing,
                                horizontalPadding,
                                keyboardInset > 0 ? 12 : (safeBottom + 12),
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius:
                                  BorderRadius.circular(showSidePreview ? 34 : 28),
                                  color: Colors.black.withValues(
                                    alpha: showSidePreview ? 0.28 : 0.18,
                                  ),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.05),
                                  ),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.all(showSidePreview ? 14 : 0),
                                  child: showSidePreview
                                      ? Row(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 12,
                                        child: SingleChildScrollView(
                                          physics:
                                          const BouncingScrollPhysics(
                                            parent:
                                            AlwaysScrollableScrollPhysics(),
                                          ),
                                          keyboardDismissBehavior:
                                          ScrollViewKeyboardDismissBehavior
                                              .onDrag,
                                          padding: EdgeInsets.only(
                                            bottom: keyboardInset > 0
                                                ? 24
                                                : (safeBottom + 12),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                            children: formColumn,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 20),
                                      Expanded(
                                        flex: 8,
                                        child: SingleChildScrollView(
                                          physics:
                                          const BouncingScrollPhysics(
                                            parent:
                                            AlwaysScrollableScrollPhysics(),
                                          ),
                                          keyboardDismissBehavior:
                                          ScrollViewKeyboardDismissBehavior
                                              .onDrag,
                                          padding: EdgeInsets.only(
                                            bottom: safeBottom + 12,
                                          ),
                                          child: _buildDesktopPreviewColumn(
                                            theme,
                                            width,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                      : ListView(
                                    physics:
                                    const BouncingScrollPhysics(
                                      parent:
                                      AlwaysScrollableScrollPhysics(),
                                    ),
                                    keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior
                                        .onDrag,
                                    padding: EdgeInsets.fromLTRB(
                                      0,
                                      0,
                                      0,
                                      keyboardInset > 0
                                          ? 28
                                          : (safeBottom + 16),
                                    ),
                                    children: [
                                      ...formColumn,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AudienceSection {
  const _AudienceSection({
    required this.title,
    required this.users,
  });

  final String title;
  final List<StoryAudienceUser> users;
}

class _CustomAudiencePickerSheet extends StatefulWidget {
  const _CustomAudiencePickerSheet({
    required this.stream,
    required this.initialSelectedIds,
    required this.selectedUsersById,
    required this.onApply,
  });

  final Stream<List<StoryAudienceUser>> stream;
  final Set<String> initialSelectedIds;
  final Map<String, StoryAudienceUser> selectedUsersById;
  final ValueChanged<List<StoryAudienceUser>> onApply;

  @override
  State<_CustomAudiencePickerSheet> createState() =>
      _CustomAudiencePickerSheetState();
}

class _CustomAudiencePickerSheetState extends State<_CustomAudiencePickerSheet> {
  late final TextEditingController _searchController;
  late Set<String> _selectedIds;
  late Map<String, StoryAudienceUser> _selectedUsersById;
  String _search = '';

  AppLocalizations get l10n => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _selectedIds = <String>{...widget.initialSelectedIds};
    _selectedUsersById =
    Map<String, StoryAudienceUser>.from(widget.selectedUsersById);
    _searchController = TextEditingController()
      ..addListener(() {
        if (!mounted) return;
        setState(() {
          _search = _searchController.text.trim().toLowerCase();
        });
      });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<StoryAudienceUser> _sortUsers(List<StoryAudienceUser> users) {
    final sorted = List<StoryAudienceUser>.from(users);
    sorted.sort((a, b) {
      if (a.isFavorite != b.isFavorite) {
        return a.isFavorite ? -1 : 1;
      }

      final aTime = a.lastInteractionAt?.millisecondsSinceEpoch ?? 0;
      final bTime = b.lastInteractionAt?.millisecondsSinceEpoch ?? 0;
      if (aTime != bTime) return bTime.compareTo(aTime);

      return a.displayLabel.toLowerCase().compareTo(
        b.displayLabel.toLowerCase(),
      );
    });
    return sorted;
  }

  List<StoryAudienceUser> _filterUsers(List<StoryAudienceUser> users) {
    final query = _search.trim().toLowerCase();

    if (query.isEmpty) return users;

    return users.where((user) {
      final display = user.displayLabel.toLowerCase();
      final username = user.username.toLowerCase();
      final firstName = user.firstName.toLowerCase();
      final lastName = user.lastName.toLowerCase();

      return display.contains(query) ||
          username.contains(query) ||
          firstName.contains(query) ||
          lastName.contains(query);
    }).toList();
  }

  List<_AudienceSection> _buildSections(List<StoryAudienceUser> users) {
    if (users.isEmpty) return const [];

    final favorites = users.where((u) => u.isFavorite).toList();
    final recent = users
        .where((u) => !u.isFavorite && u.lastInteractionAt != null)
        .toList();
    final others = users
        .where((u) => !u.isFavorite && u.lastInteractionAt == null)
        .toList();

    final sections = <_AudienceSection>[];

    if (favorites.isNotEmpty) {
      sections.add(
        _AudienceSection(
          title: l10n.storyAudienceFavorites,
          users: favorites,
        ),
      );
    }

    if (recent.isNotEmpty) {
      sections.add(
        _AudienceSection(
          title: l10n.storyAudienceRecent,
          users: recent,
        ),
      );
    }

    if (others.isNotEmpty) {
      sections.add(
        _AudienceSection(
          title: l10n.storyAudienceAllFriends,
          users: others,
        ),
      );
    }

    return sections;
  }

  void _toggleUser(StoryAudienceUser user) {
    final selected = _selectedIds.contains(user.id);
    HapticFeedback.selectionClick();

    setState(() {
      if (selected) {
        _selectedIds.remove(user.id);
        _selectedUsersById.remove(user.id);
      } else {
        _selectedIds.add(user.id);
        _selectedUsersById[user.id] = user;
      }
    });
  }

  void _selectAll(List<StoryAudienceUser> users) {
    if (users.isEmpty) return;

    HapticFeedback.selectionClick();
    setState(() {
      for (final user in users) {
        if (user.id.trim().isEmpty) continue;
        _selectedIds.add(user.id);
        _selectedUsersById[user.id] = user;
      }
    });
  }

  void _deselectAll() {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedIds.clear();
      _selectedUsersById.clear();
    });
  }

  Widget _buildBulkActionsRow(
      ThemeData theme,
      List<StoryAudienceUser> users,
      ) {
    final hasUsers = users.isNotEmpty;
    final allSelected =
        hasUsers && users.every((user) => _selectedIds.contains(user.id));
    final hasSelection = _selectedIds.isNotEmpty;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton(
          onPressed: hasUsers && !allSelected ? () => _selectAll(users) : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.12),
            ),
            backgroundColor: Colors.white.withValues(alpha: 0.04),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          child: Text(
            l10n.storyAudienceSelectAll,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        OutlinedButton(
          onPressed: hasSelection ? _deselectAll : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.12),
            ),
            backgroundColor: Colors.white.withValues(alpha: 0.04),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          child: Text(
            l10n.storyAudienceDeselectAll,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserTile(ThemeData theme, StoryAudienceUser user) {
    if (user.id.trim().isEmpty) return const SizedBox.shrink();

    final selected = _selectedIds.contains(user.id);
    final displayName = user.displayLabel.trim().isNotEmpty
        ? user.displayLabel.trim()
        : 'Unknown';
    final subtitle = user.subtitleLabel.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _toggleUser(user),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? kPrimaryGold.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? kPrimaryGold.withValues(alpha: 0.52)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              _AudienceAvatar(user: user),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (user.isFavorite) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: kPrimaryGold.withValues(alpha: 0.95),
                          ),
                        ],
                      ],
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? kPrimaryGold : Colors.transparent,
                  border: Border.all(
                    color: selected ? kPrimaryGold : Colors.white54,
                  ),
                ),
                child: selected
                    ? const Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: Colors.black,
                )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<StoryAudienceUser> _selectedUsersForApply() {
    final selectedUsers = _selectedUsersById.values
        .where((user) => _selectedIds.contains(user.id))
        .toList()
      ..sort(
            (a, b) => a.displayLabel.toLowerCase().compareTo(
          b.displayLabel.toLowerCase(),
        ),
      );

    return selectedUsers;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          decoration: BoxDecoration(
            color: Color.lerp(kSurfaceAltColor, kGoldDeep, 0.08)!
                .withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: kGoldDeep.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.82,
            child: StreamBuilder<List<StoryAudienceUser>>(
              stream: widget.stream,
              builder: (context, snapshot) {
                final rawUsers = snapshot.data ?? const <StoryAudienceUser>[];
                final allUsers = _sortUsers(_filterUsers(rawUsers));
                final sections = _buildSections(allUsers);
                final isLoading =
                    snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData;

                return Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        l10n.storyAudienceChoose,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        l10n.storyAudienceSearchFriends,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                          height: 1.40,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: TextField(
                        controller: _searchController,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white,
                        ),
                        decoration: InputDecoration(
                          hintText: l10n.storyAudienceSearchFriends,
                          hintStyle: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white38,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: Colors.white70,
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.05),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(
                              color: kPrimaryGold.withValues(alpha: 0.90),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _buildBulkActionsRow(theme, allUsers),
                      ),
                    ),
                    Expanded(
                      child: isLoading
                          ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            kPrimaryGold,
                          ),
                        ),
                      )
                          : allUsers.isEmpty
                          ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _search.trim().isNotEmpty
                                ? l10n.storyAudienceSearchFriends
                                : l10n.storyAudienceAllFriends,
                            textAlign: TextAlign.center,
                            style:
                            theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white60,
                            ),
                          ),
                        ),
                      )
                          : ListView(
                        padding:
                        const EdgeInsets.fromLTRB(14, 0, 14, 14),
                        keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                        children: [
                          for (final section in sections) ...[
                            _buildSectionHeader(
                              theme,
                              section.title,
                              section.users.length,
                            ),
                            ...section.users.map(
                                  (user) => Padding(
                                padding:
                                const EdgeInsets.only(bottom: 10),
                                child: _buildUserTile(theme, user),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () {
                            final selectedUsers = _selectedUsersForApply();
                            widget.onApply(selectedUsers);
                            Navigator.of(context).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimaryGold,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: Text(
                            _selectedIds.isEmpty
                                ? l10n.storyAudienceChoose
                                : '${l10n.storyAudienceChoose} (${_selectedIds.length})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: Colors.black,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _AudienceAvatar extends StatelessWidget {
  const _AudienceAvatar({required this.user});

  final StoryAudienceUser user;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = (user.photoUrl ?? '').trim().isNotEmpty;

    return MwAvatar(
      radius: 24,
      avatarType: 'bear',
      profileUrl: hasPhoto ? user.photoUrl : null,
      initials: _initials(user),
      hideRealAvatar: false,
      showRing: false,
      isOnline: false,
      showOnlineDot: false,
      showOnlineGlow: false,
      backgroundColor: Colors.white.withValues(alpha: 0.08),
    );
  }

  String _initials(StoryAudienceUser user) {
    final first = user.firstName.trim().isNotEmpty
        ? user.firstName.trim()[0]
        : '';
    final last = user.lastName.trim().isNotEmpty
        ? user.lastName.trim()[0]
        : '';

    final value = (first + last).toUpperCase();
    if (value.isNotEmpty) return value;

    final parts = user.displayLabel.trim().split(RegExp(r'\s+'));
    if (parts.isNotEmpty) {
      final f = parts.first.isNotEmpty ? parts.first[0] : '';
      final l = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
      final fallback = (f + l).toUpperCase();
      if (fallback.isNotEmpty) return fallback;
    }

    return 'U';
  }
}

class _AudienceChipAvatar extends StatelessWidget {
  const _AudienceChipAvatar({required this.user});

  final StoryAudienceUser user;

  @override
  Widget build(BuildContext context) {
    return _AudienceAvatar(user: user);
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.warm = false,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool warm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final base = warm
        ? Color.lerp(kSurfaceAltColor, kGoldDeep, 0.10)!
        : Color.lerp(kSurfaceColor, Colors.black, 0.22)!;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            base.withValues(alpha: 0.48),
            base.withValues(alpha: 0.34),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: Colors.white.withValues(alpha: warm ? 0.10 : 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
          if (warm)
            BoxShadow(
              color: kGoldDeep.withValues(alpha: 0.04),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: MediaQuery.of(context).textScaler.clamp(
            minScaleFactor: 0.9,
            maxScaleFactor: 1.1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if ((subtitle ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white70,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (warm) ...[
                  const SizedBox(width: 12),
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: kPrimaryGold.withValues(alpha: 0.92),
                      boxShadow: [
                        BoxShadow(
                          color: kGoldDeep.withValues(alpha: 0.22),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: MediaQuery.of(context).textScaler.clamp(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.0,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ColorControlCard extends StatelessWidget {
  const _ColorControlCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if ((subtitle ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white60,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _LiveColorChip extends StatelessWidget {
  const _LiveColorChip({
    required this.color,
    required this.foreground,
    required this.label,
  });

  final Color color;
  final Color foreground;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color.computeLuminance() > 0.55 ? Colors.black : Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SpectrumColorPicker extends StatelessWidget {
  const _SpectrumColorPicker({
    required this.selectedColor,
    required this.onChanged,
    this.darkMode = false,
  });

  final Color selectedColor;
  final ValueChanged<Color> onChanged;
  final bool darkMode;

  static const List<Color> _hueStops = <Color>[
    Color(0xFFFF4D4D),
    Color(0xFFFF9F1C),
    Color(0xFFFFD166),
    Color(0xFF2EC4B6),
    Color(0xFF00BBF9),
    Color(0xFF4361EE),
    Color(0xFF8338EC),
    Color(0xFFFF006E),
    Color(0xFFFF4D4D),
  ];

  Color _colorFromHue(double hue, {double saturation = 0.82, double value = 0.95}) {
    return HSVColor.fromAHSV(1, hue.clamp(0, 360), saturation.clamp(0, 1), value.clamp(0, 1)).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final hsv = HSVColor.fromColor(selectedColor);
    final normalizedHue = (hsv.hue / 360).clamp(0.0, 1.0);
    final toneValue = darkMode ? hsv.value.clamp(0.18, 0.78) : hsv.value.clamp(0.18, 1.0);
    final normalizedTone = darkMode
        ? ((toneValue - 0.18) / 0.60).clamp(0.0, 1.0)
        : ((toneValue - 0.18) / 0.82).clamp(0.0, 1.0);

    final hueColor = _colorFromHue(hsv.hue, saturation: hsv.saturation < 0.35 ? 0.82 : hsv.saturation);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GradientSlider(
          value: normalizedHue,
          colors: _hueStops,
          onChanged: (value) {
            final updated = HSVColor.fromColor(selectedColor).withHue(value * 360);
            final next = updated.withSaturation(updated.saturation < 0.35 ? 0.82 : updated.saturation);
            onChanged(next.toColor());
          },
        ),
        const SizedBox(height: 12),
        _GradientSlider(
          value: normalizedTone,
          colors: darkMode
              ? <Color>[
            Colors.black,
            Color.lerp(hueColor, Colors.black, 0.72)!,
            Color.lerp(hueColor, Colors.black, 0.36)!,
            hueColor,
          ]
              : <Color>[
            Colors.black,
            Color.lerp(hueColor, Colors.white, 0.12)!,
            hueColor,
            Colors.white,
          ],
          onChanged: (value) {
            final nextValue = darkMode ? (0.18 + (value * 0.60)) : (0.18 + (value * 0.82));
            final updated = HSVColor.fromColor(selectedColor)
                .withHue(hsv.hue)
                .withSaturation(darkMode ? 0.78 : (hsv.saturation < 0.35 ? 0.75 : hsv.saturation.clamp(0.35, 0.95)))
                .withValue(nextValue.clamp(0.18, darkMode ? 0.78 : 1.0));
            onChanged(updated.toColor());
          },
        ),
      ],
    );
  }
}

class _GradientSlider extends StatelessWidget {
  const _GradientSlider({
    required this.value,
    required this.colors,
    required this.onChanged,
  });

  final double value;
  final List<Color> colors;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        final thumbX = (trackWidth - 26) * value.clamp(0.0, 1.0);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) {
            final local = (details.localPosition.dx / trackWidth).clamp(0.0, 1.0);
            onChanged(local);
          },
          onTapDown: (details) {
            final local = (details.localPosition.dx / trackWidth).clamp(0.0, 1.0);
            onChanged(local);
          },
          child: SizedBox(
            height: 32,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 16,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: colors),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: thumbX,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.65),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.28),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
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
}

class _MediaPreviewCard extends StatelessWidget {
  const _MediaPreviewCard({
    required this.child,
    required this.footerText,
    this.onRemove,
  });

  final Widget child;
  final String footerText;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.06),
            Colors.white.withValues(alpha: 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: MediaQuery.of(context).textScaler.clamp(
            minScaleFactor: 0.9,
            maxScaleFactor: 1.05,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            child,
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        footerText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                    ],
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    onPressed: onRemove,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.28),
                    ),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


class _SheetActionTile extends StatelessWidget {
  const _SheetActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDanger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = isDanger ? kErrorColor : Colors.white;

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: MediaQuery.of(context).textScaler.clamp(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDanger
                        ? kErrorColor.withValues(alpha: 0.12)
                        : Colors.white.withValues(alpha: 0.08),
                  ),
                  child: Icon(icon, color: fg),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FileImageAdapter extends ImageProvider<FileImageAdapter> {
  const FileImageAdapter(this.path);

  final String path;

  @override
  Future<FileImageAdapter> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<FileImageAdapter>(this);
  }

  @override
  ImageStreamCompleter loadImage(
      FileImageAdapter key,
      ImageDecoderCallback decode,
      ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      debugLabel: path,
    );
  }

  Future<ui.Codec> _loadAsync(
      FileImageAdapter key,
      ImageDecoderCallback decode,
      ) async {
    final bytes = await _readBytesFromPath(path);
    if (bytes.isEmpty) {
      throw StateError('Could not load image bytes.');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) {
    return other is FileImageAdapter && other.path == path;
  }

  @override
  int get hashCode => path.hashCode;
}

Future<Uint8List> _readBytesFromPath(String path) async {
  if (kIsWeb) return Uint8List(0);

  final file = ioFile(path);
  return file.readAsBytes();
}

extension _FirstOrNullExt<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}