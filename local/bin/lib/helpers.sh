#!/bin/bash

signal_waybar() {
  if [[ -n "$1" ]]; then
    pkill "-RTMIN+$1" waybar
  fi
}
