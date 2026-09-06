#!/bin/zsh

legacy_battery_restore_arguments() {
  local battery_sleep="$1"
  local battery_disablesleep="$2"

  if [[ "$battery_sleep" == 0 && "$battery_disablesleep" == 1 ]]; then
    print -r -- "sleep 5 disablesleep 0"
  fi
}
