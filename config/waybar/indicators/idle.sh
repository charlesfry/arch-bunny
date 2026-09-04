#!/bin/bash

if ! systemctl --user is-active --quiet swayidle; then
  echo '{"text": "", "tooltip": "Enable idle lock", "class": "active"}'
else
  echo '{"text": ""}'
fi
