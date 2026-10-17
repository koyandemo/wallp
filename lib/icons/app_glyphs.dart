import 'package:flutter/material.dart';

/// Matches an app to a themed symbol: by a fragment of its package name, or
/// by its exact label (so "Clone Phone" doesn't count as "Phone").
class _Rule {
  const _Rule(this.icon, {this.packages = const [], this.labels = const []});

  final IconData icon;

  final List<String> packages;
  final List<String> labels;

  bool matches(String package, String label) =>
      packages.any(package.contains) || labels.contains(label);
}

/// First match wins, so more specific rules come first.
const _rules = <_Rule>[
  _Rule(
    Icons.forum_rounded,
    packages: ['whatsapp', 'telegram', 'viber', 'facebook.orca', 'naver.line'],
    labels: ['messenger'],
  ),
  _Rule(
    Icons.phone_rounded,
    packages: ['dialer', 'incallui'],
    labels: ['phone', 'dialer'],
  ),
  _Rule(
    Icons.chat_bubble_rounded,
    packages: ['.mms', 'messaging'],
    labels: ['messages', 'messaging', 'sms'],
  ),
  _Rule(Icons.camera_rounded, packages: ['instagram']),
  _Rule(Icons.photo_camera_rounded, packages: ['camera'], labels: ['camera']),
  _Rule(
    Icons.public_rounded,
    packages: [
      'chrome',
      'browser',
      'firefox',
      'opera',
      'microsoft.emmx',
      'brave',
    ],
    labels: ['browser', 'internet'],
  ),
  _Rule(
    Icons.photo_rounded,
    packages: ['photos', 'gallery'],
    labels: ['photos', 'gallery'],
  ),
  _Rule(Icons.map_rounded, packages: ['maps', 'waze'], labels: ['maps']),
  _Rule(
    Icons.mail_rounded,
    packages: ['android.gm', 'email', 'outlook'],
    labels: ['gmail', 'email', 'mail'],
  ),
  _Rule(
    Icons.calendar_month_rounded,
    packages: ['calendar'],
    labels: ['calendar'],
  ),
  _Rule(
    Icons.schedule_rounded,
    packages: ['deskclock', 'clock', 'alarm'],
    labels: ['clock'],
  ),
  _Rule(Icons.play_arrow_rounded, packages: ['youtube']),
  _Rule(
    Icons.videocam_rounded,
    packages: ['android.apps.tachyon', 'apps.meetings', 'zoom.videomeetings'],
    labels: ['meet', 'google meet', 'duo', 'zoom'],
  ),
  _Rule(Icons.music_video_rounded, packages: ['tiktok', 'musically']),
  _Rule(
    Icons.music_note_rounded,
    packages: ['spotify', 'music'],
    labels: ['music'],
  ),
  _Rule(Icons.shop_rounded, packages: ['vending'], labels: ['play store']),
  _Rule(
    Icons.thumb_up_rounded,
    packages: ['facebook.katana', 'facebook.lite'],
    labels: ['facebook'],
  ),
  _Rule(
    Icons.calculate_rounded,
    packages: ['calculator'],
    labels: ['calculator'],
  ),
  _Rule(Icons.contacts_rounded, packages: ['contacts'], labels: ['contacts']),
  _Rule(
    Icons.folder_rounded,
    packages: ['filemanager', 'documentsui', '.files'],
    labels: ['files', 'file manager', 'my files'],
  ),
  _Rule(Icons.cloud_rounded, packages: ['weather'], labels: ['weather']),
  _Rule(
    Icons.sticky_note_2_rounded,
    packages: ['android.keep', '.notes'],
    labels: ['notes', 'keep notes'],
  ),
  _Rule(
    Icons.mic_rounded,
    packages: ['recorder'],
    labels: ['recorder', 'sound recorder'],
  ),
  _Rule(
    Icons.account_balance_wallet_rounded,
    packages: ['wallet', 'kbzpay', 'wavemoney', 'nugpay', 'ayapay'],
    labels: [
      'wallet',
      'nugpay',
      'kbzpay',
      'wavepay',
      'wave money',
      'ayapay',
      'cb pay',
    ],
  ),
  // Device-care apps (OPPO/realme Phone Manager, Personal Safety) get the
  // settings gear.
  _Rule(
    Icons.settings_rounded,
    packages: [
      'settings',
      'phonemanager',
      'safetyhub',
      'safecenter',
      'securitycenter',
    ],
    labels: ['settings', 'phone manager', 'safety', 'personal safety'],
  ),
];

/// Returns a themed symbol for the app, or null to use its own (tinted) icon.
IconData? glyphFor(String packageName, String label) {
  final package = packageName.toLowerCase();
  final name = label.trim().toLowerCase();
  for (final rule in _rules) {
    if (rule.matches(package, name)) return rule.icon;
  }
  return null;
}
