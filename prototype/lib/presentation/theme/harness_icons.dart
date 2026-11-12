import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The interface icon set.
///
/// Icons come from Lucide (24px grid, 2px stroke, round caps and joins) as
/// required by `docs/Harness/branding.md`. This indirection keeps the glyph
/// choice in one place: a screen asks for an intent such as [send] or
/// [workspace], never for a vendor constant.
abstract final class HarnessIcons {
  // Navigation and chrome.
  static const arrowLeft = LucideIcons.arrowLeft;
  static const chevronDown = LucideIcons.chevronDown;
  static const chevronRight = LucideIcons.chevronRight;
  static const ellipsisVertical = LucideIcons.ellipsisVertical;
  static const x = LucideIcons.x;
  static const search = LucideIcons.search;
  static const settings = LucideIcons.settings;
  static const refresh = LucideIcons.refreshCw;
  static const more = LucideIcons.ellipsisVertical;

  // Sessions and chat.
  static const sessions = LucideIcons.messagesSquare;
  static const newSession = LucideIcons.messageSquarePlus;
  static const send = LucideIcons.arrowUp;
  static const stop = LucideIcons.circleStop;
  static const copy = LucideIcons.copy;
  static const pencil = LucideIcons.pencil;
  static const trash = LucideIcons.trash2;

  // Workspace and storage.
  static const workspace = LucideIcons.folder;
  static const folder = LucideIcons.folder;
  static const folderOpen = LucideIcons.folderOpen;
  static const storageVolumes = LucideIcons.hardDrive;
  static const file = LucideIcons.file;
  static const fileText = LucideIcons.fileText;
  static const fileCode = LucideIcons.fileCode;
  static const fileJson = LucideIcons.braces;
  static const image = LucideIcons.image;
  static const importSkill = LucideIcons.folderPlus;
  static const skill = LucideIcons.puzzle;
  static const restore = LucideIcons.rotateCcw;
  static const lock = LucideIcons.lock;
  static const publicHost = LucideIcons.globe;

  // Providers and settings.
  static const provider = LucideIcons.workflow;
  static const model = LucideIcons.cpu;
  static const memory = LucideIcons.memoryStick;
  static const key = LucideIcons.key;
  static const keyMissing = LucideIcons.keyRound;
  static const keyVisible = LucideIcons.eye;
  static const keyHidden = LucideIcons.eyeOff;
  static const link = LucideIcons.link;
  static const runner = LucideIcons.server;
  static const searchProvider = LucideIcons.globe;
  static const sliders = LucideIcons.slidersHorizontal;
  static const tokens = LucideIcons.hash;
  static const save = LucideIcons.save;
  static const download = LucideIcons.download;
  static const pause = LucideIcons.pause;
  static const resume = LucideIcons.play;
  static const deleteModel = LucideIcons.trash2;
  static const downloaded = LucideIcons.circleCheck;
  static const radioSelected = LucideIcons.circleDot;
  static const radioUnselected = LucideIcons.circle;
  static const switchModel = LucideIcons.arrowLeftRight;

  // Status and feedback.
  static const check = LucideIcons.check;
  static const success = LucideIcons.circleCheck;
  static const error = LucideIcons.circleAlert;
  static const warning = LucideIcons.triangleAlert;
  static const info = LucideIcons.info;
  static const running = LucideIcons.loaderCircle;
  static const add = LucideIcons.plus;
  static const dismiss = LucideIcons.x;

  // Timers and tools.
  static const timer = LucideIcons.timer;
  static const terminal = LucideIcons.terminal;
  static const attachment = LucideIcons.paperclip;
  static const compaction = LucideIcons.minimize2;
  static const construction = LucideIcons.construction;
  static const arrowUpRight = LucideIcons.arrowUpRight;
}
