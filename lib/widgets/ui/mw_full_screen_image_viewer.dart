import 'package:flutter/material.dart';

/// Full-screen image viewer for ImageProvider (File/Memory/CachedNetwork)
/// - pinch zoom + pan
/// - double-tap zoom
/// - swipe-down to dismiss (only when not zoomed)
class MwFullScreenImageViewer extends StatefulWidget {
  final ImageProvider provider;
  final String heroTag;

  const MwFullScreenImageViewer({
    super.key,
    required this.provider,
    required this.heroTag,
  });

  @override
  State<MwFullScreenImageViewer> createState() => _MwFullScreenImageViewerState();
}

class _MwFullScreenImageViewerState extends State<MwFullScreenImageViewer> {
  final TransformationController _transform = TransformationController();
  TapDownDetails? _doubleTapDetails;

  double _dragDy = 0.0;
  bool _isDraggingDown = false;

  static const double _dismissThreshold = 140.0;
  static const double _maxBgFadeDistance = 420.0;

  double get _currentScale => _transform.value.storage[0];
  bool get _isZoomed => _currentScale > 1.01;

  void _resetZoom() {
    _transform.value = Matrix4.identity();
  }

  void _handleDoubleTap() {
    if (_isZoomed) {
      setState(_resetZoom);
      return;
    }

    final d = _doubleTapDetails;
    if (d == null) return;

    const double scale = 2.6;
    final tap = d.localPosition;

    final zoomed = Matrix4.identity()
      ..translate(-tap.dx * (scale - 1), -tap.dy * (scale - 1))
      ..scale(scale);

    setState(() => _transform.value = zoomed);
  }

  void _onVerticalDragStart(DragStartDetails d) {
    if (_isZoomed) return;
    _isDraggingDown = true;
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    if (!_isDraggingDown || _isZoomed) return;
    setState(() {
      _dragDy += d.delta.dy;
      if (_dragDy < 0) _dragDy = 0;
    });
  }

  void _onVerticalDragEnd(DragEndDetails d) {
    if (!_isDraggingDown || _isZoomed) return;

    final velocity = d.primaryVelocity ?? 0.0;
    final shouldDismiss = _dragDy > _dismissThreshold || velocity > 1200;

    if (shouldDismiss) {
      Navigator.of(context).maybePop();
    } else {
      setState(() {
        _dragDy = 0.0;
        _isDraggingDown = false;
      });
    }
  }

  double _backgroundOpacity() {
    final t = (_dragDy / _maxBgFadeDistance).clamp(0.0, 1.0);
    return (1.0 - (t * 0.75)).clamp(0.25, 1.0);
  }

  double _contentScaleDuringDrag() {
    final t = (_dragDy / _maxBgFadeDistance).clamp(0.0, 1.0);
    return (1.0 - (t * 0.10)).clamp(0.90, 1.0);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgOpacity = _backgroundOpacity();
    final dragScale = _contentScaleDuringDrag();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            // Background (tap to close)
            Positioned.fill(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 90),
                opacity: bgOpacity,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Container(color: Colors.black),
                ),
              ),
            ),

            // Content (double tap + swipe down)
            Center(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTapDown: (d) => _doubleTapDetails = d,
                onDoubleTap: _handleDoubleTap,
                onVerticalDragStart: _onVerticalDragStart,
                onVerticalDragUpdate: _onVerticalDragUpdate,
                onVerticalDragEnd: _onVerticalDragEnd,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 110),
                  curve: Curves.easeOut,
                  transform: Matrix4.identity()
                    ..translate(0.0, _dragDy)
                    ..scale(dragScale),
                  child: Hero(
                    tag: widget.heroTag,
                    child: Material(
                      color: Colors.transparent,
                      child: InteractiveViewer(
                        transformationController: _transform,
                        panEnabled: true,
                        minScale: 1.0,
                        maxScale: 5.0,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image(
                            image: widget.provider,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Close button
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                tooltip: 'Close',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
