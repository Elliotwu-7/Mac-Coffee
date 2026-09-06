# Removing the Mac Coffee 1.x helper

Mac Coffee 2.0 does not install or require a privileged helper. If version 1.x was installed previously, its helper may remain on the Mac. An active 1.x session set both battery `sleep 0` and `disablesleep 1`, so both values must be considered during cleanup.

Inspect the exact legacy state first:

```sh
ls -l /Library/PrivilegedHelperTools/com.elliotwu.maccoffee.helper \
      /Library/LaunchDaemons/com.elliotwu.maccoffee.helper.plist \
      /var/run/com.elliotwu.maccoffee.helper.sock 2>/dev/null
pmset -g custom | grep -E 'sleep|disablesleep'
```

Then run the standalone cleanup script from this repository:

```sh
./scripts/uninstall-legacy-helper.sh
```

The script asks for administrator authorization, unloads only `com.elliotwu.maccoffee.helper`, and removes its helper, launch daemon, socket, and log. It changes battery power settings only when it detects the complete Mac Coffee 1.x signature described below.

If it detects the exact active 1.x signature (`sleep 0` plus `disablesleep 1`), it restores the 1.x normal battery values (`sleep 5` plus `disablesleep 0`). For every other combination, including `sleep 5` plus `disablesleep 1`, it preserves `disablesleep`. If `sleep 0` exists without the complete signature, the script warns and asks before changing only `sleep`; in a noninteractive shell it leaves that ambiguous value unchanged and prints the explicit recovery command.

Mac Coffee 2.0 never runs this script automatically and does not include it inside either application bundle.
