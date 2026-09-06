#!/bin/zsh
set -euo pipefail

script_directory=${0:A:h}
source "$script_directory/legacy-power-policy.zsh"

legacy_helper='/Library/PrivilegedHelperTools/com.elliotwu.maccoffee.helper'
legacy_plist='/Library/LaunchDaemons/com.elliotwu.maccoffee.helper.plist'
legacy_socket='/var/run/com.elliotwu.maccoffee.helper.sock'
legacy_log='/var/log/com.elliotwu.maccoffee.helper.log'

for target in "$legacy_helper" "$legacy_plist" "$legacy_socket" "$legacy_log"; do
  case "$target" in
    /Library/PrivilegedHelperTools/com.elliotwu.maccoffee.helper|\
    /Library/LaunchDaemons/com.elliotwu.maccoffee.helper.plist|\
    /var/run/com.elliotwu.maccoffee.helper.sock|\
    /var/log/com.elliotwu.maccoffee.helper.log) ;;
    *)
      print -u2 "Refusing unexpected cleanup target: $target"
      exit 65
      ;;
  esac
done

power_settings=$(/usr/bin/pmset -g custom)
battery_sleep=$(print -r -- "$power_settings" | /usr/bin/awk '
  /Battery Power:/ { in_battery = 1; next }
  /AC Power:/ { in_battery = 0 }
  in_battery && $1 == "sleep" { print $2; exit }
')
battery_disablesleep=$(print -r -- "$power_settings" | /usr/bin/awk '
  /Battery Power:/ { in_battery = 1; next }
  /AC Power:/ { in_battery = 0 }
  in_battery && $1 == "disablesleep" { print $2; exit }
')

print "Detected battery sleep=${battery_sleep:-unknown}, disablesleep=${battery_disablesleep:-unknown}."
print "This removes only the Mac Coffee 1.x helper, socket, launch daemon, and log."
/usr/bin/sudo -v
/usr/bin/sudo /bin/launchctl bootout system/com.elliotwu.maccoffee.helper >/dev/null 2>&1 || true
/usr/bin/sudo /bin/rm -f "$legacy_helper" "$legacy_plist" "$legacy_socket" "$legacy_log"

restore_arguments=$(legacy_battery_restore_arguments "$battery_sleep" "$battery_disablesleep")
if [[ "$restore_arguments" == "sleep 5 disablesleep 0" ]]; then
  print "The exact Mac Coffee 1.x keep-awake signature is active; restoring its normal battery values."
  /usr/bin/sudo /usr/bin/pmset -b sleep 5 disablesleep 0
else
  print "The battery settings do not match the complete Mac Coffee 1.x signature; preserving them."
  if [[ "$battery_sleep" == 0 ]]; then
    print -u2 "Battery sleep is still 0, but the complete 1.x signature was not detected."
    print -u2 "That value may be intentional, so it will not be changed without confirmation."
    if [[ -t 0 ]]; then
      read "reply?Restore the Mac Coffee 1.x normal battery sleep value of 5 minutes? [y/N] "
      if [[ "$reply" == [yY] || "$reply" == [yY][eE][sS] ]]; then
        /usr/bin/sudo /usr/bin/pmset -b sleep 5
      fi
    else
      print -u2 "If 1.x set this value, restore it explicitly with: sudo pmset -b sleep 5"
    fi
  fi
fi

print "Legacy Mac Coffee helper artifacts removed."
