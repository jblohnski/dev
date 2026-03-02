#!/usr/bin/env bash
# @desc: Harden macOS security defaults (remote access, firewall, privacy)
# @tags: sec system macos
# @run: sudo
# @alias: harden
# @owner: firstparty

set -euo pipefail

if [[ "${OSTYPE:-}" != darwin* ]]; then
  echo "This script is intended for macOS (darwin)." >&2
  exit 1
fi

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Run with sudo: sudo $0" >&2
  exit 1
fi

echo ">> Hardening macOS (mostly reversible defaults)"

# Disable remote services
/usr/sbin/systemsetup -setremotelogin off >/dev/null || true
/bin/launchctl disable system/com.apple.screensharing 2>/dev/null || true

# Firewall on + stealth
/usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on >/dev/null
/usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on >/dev/null

# Disable guest login
/usr/bin/defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false

# Require password immediately after sleep / screensaver (per-user)
# NOTE: runs as root, so we target the active console user if available.
console_user="$(/usr/sbin/scutil <<< 'show State:/Users/ConsoleUser' | awk '/Name :/ {print $3}' | head -n1)"
if [[ -n "$console_user" && "$console_user" != "loginwindow" ]]; then
  /usr/bin/sudo -u "$console_user" /usr/bin/defaults write com.apple.screensaver askForPassword -int 1
  /usr/bin/sudo -u "$console_user" /usr/bin/defaults write com.apple.screensaver askForPasswordDelay -int 0
else
  /usr/bin/defaults write com.apple.screensaver askForPassword -int 1
  /usr/bin/defaults write com.apple.screensaver askForPasswordDelay -int 0
fi

# Disable captive portal auto-popup
/usr/bin/defaults write /Library/Preferences/SystemConfiguration/com.apple.captive.control Active -bool false

# Disable Bonjour multicast advertisements
/usr/bin/defaults write /Library/Preferences/com.apple.mDNSResponder.plist NoMulticastAdvertisements -bool true

# Disable AirDrop (per-user)
if [[ -n "$console_user" && "$console_user" != "loginwindow" ]]; then
  /usr/bin/sudo -u "$console_user" /usr/bin/defaults write com.apple.NetworkBrowser DisableAirDrop -bool true
else
  /usr/bin/defaults write com.apple.NetworkBrowser DisableAirDrop -bool true
fi

# Disable diagnostic submissions (system)
/usr/bin/defaults write "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist" AutoSubmit -bool false
/usr/bin/defaults write "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist" ThirdPartyDataSubmit -bool false

echo ">> Done. Reboot recommended for full effect."
