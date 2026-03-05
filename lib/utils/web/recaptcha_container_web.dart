// lib/utils/web/recaptcha_container_web.dart
import 'dart:async';
import 'dart:html' as html;

Timer? _reCAPTCHA_poller;
Timer? _expandDebounce;

bool _expanded = false;
bool _pendingExpanded = false;

html.IFrameElement? _findChallengeIframeInContainer(html.Element container) {
  for (final el in container.querySelectorAll('iframe')) {
    if (el is! html.IFrameElement) continue;
    final src = (el.src ?? '').toLowerCase();
    if (src.contains('recaptcha') && src.contains('bframe')) return el;
  }
  return null;
}

Future<void> ensureRecaptchaContainer({
  String parentId = '__ff-recaptcha-container',
  String childId = '__ff-recaptcha-inner',
  bool visible = true,
  bool anchorBottomRight = false,
}) async {
  // Wait for <body>
  for (var i = 0; i < 10; i++) {
    if (html.document.body != null) break;
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }

  final body = html.document.body;
  if (body == null) return;

  // Ensure host exists AND is last in <body> (above Flutter DOM)
  html.Element host = html.document.getElementById('__ff-recaptcha-host') ??
      (html.DivElement()..id = '__ff-recaptcha-host');

  // Move to end so it stays above Flutter root
  host.remove();
  body.append(host);

  // Host style
  final hs = host.style;
  hs.position = 'fixed';
  hs.left = '0';
  hs.top = '0';
  hs.right = '0';
  hs.bottom = '0';
  hs.zIndex = '2147483647';
  // ✅ Allow clicks ONLY on the container area (host itself does nothing)
  hs.pointerEvents = 'none';
  hs.background = 'transparent';

  // Ensure parent (container)
  html.Element parent =
      html.document.getElementById(parentId) ?? (html.DivElement()..id = parentId);

  if (parent.parent != host) {
    parent.remove();
    host.append(parent);
  }

  // Ensure child (actual render target)
  html.Element child =
      html.document.getElementById(childId) ?? (html.DivElement()..id = childId);

  if (child.parent != parent) {
    child.remove();
    parent.append(child);
  }

  // Container style (pinned by default)
  final p = parent.style;
  p.position = 'fixed';
  p.top = '';
  p.left = '';
  p.right = '';
  p.bottom = '16px';
  p.transform = '';

  if (anchorBottomRight) {
    p.right = '16px';
  } else {
    p.left = '16px';
  }

  p.width = 'min(92vw, 320px)';
  p.minHeight = '110px';
  p.maxHeight = '96vh';
  p.height = 'auto';
  p.overflow = 'visible';

  p.zIndex = '2147483647';

  // ✅ Never use display:none (it breaks render / causes flicker)
  p.display = 'block';
  p.visibility = visible ? 'visible' : 'hidden';
  // ✅ This is the important one for interactivity
  p.pointerEvents = visible ? 'auto' : 'none';

  final c = child.style;
  c.width = '100%';
  c.minHeight = '110px';
  c.height = 'auto';
  c.display = 'block';

  void setExpanded(bool expanded) {
    if (_expanded == expanded) return;
    _expanded = expanded;
    if (expanded) {
      body.classes.add('recaptcha-expanded');
    } else {
      body.classes.remove('recaptcha-expanded');
    }
  }

  void setExpandedDebounced(bool expanded) {
    if (_pendingExpanded == expanded) return;
    _pendingExpanded = expanded;
    _expandDebounce?.cancel();
    _expandDebounce = Timer(const Duration(milliseconds: 150), () {
      setExpanded(_pendingExpanded);
    });
  }

  // Hide / stop
  if (!visible) {
    setExpanded(false);
    _expandDebounce?.cancel();
    _expandDebounce = null;
    _reCAPTCHA_poller?.cancel();
    _reCAPTCHA_poller = null;
    return;
  }

  // Start collapsed (anchor visible)
  setExpanded(false);

  // ✅ KEY FIX:
  // Expand ONLY when bframe exists INSIDE OUR container
  final inContainerNow = _findChallengeIframeInContainer(parent) != null;
  setExpandedDebounced(inContainerNow);

  _reCAPTCHA_poller?.cancel();
  _reCAPTCHA_poller = Timer.periodic(const Duration(milliseconds: 150), (_) {
    final inContainer = _findChallengeIframeInContainer(parent) != null;
    setExpandedDebounced(inContainer);
  });
}