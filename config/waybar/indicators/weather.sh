#!/usr/bin/env bash

# Usage: weather [--help]
set -Eeuo pipefail

case "${1-}" in
-h | --help)
	sed -n '2,/^set -/p' "$0" | sed 's|^# \?||;$d'
	exit
	;;
esac

# printf '<lat>,<lon>\n' > ~/.config/bunny/weather-location

loc_file=${XDG_CONFIG_HOME:-$HOME/.config}/bunny/weather-location
loc=
if [[ -r $loc_file ]]; then
	read -r loc <"$loc_file" || true
fi

out=
for attempt in 1 2 3 4 5 6; do
	if ((attempt > 1)); then sleep 5; fi
	if out=$(curl -fsS --max-time 5 "https://wttr.in/${loc}?format=%t+%C" 2>/dev/null); then
		break
	fi
	out=
done

if [[ -z $out ]]; then
	printf 'weather n/a\n'
	exit 0
fi

if [[ ! $out =~ ^[[:space:]]*[+-]?[0-9]+° ]]; then
	printf 'weather n/a\n'
	exit 0
fi

# `+77°F` reads as an instruction rather than a temperature, and wttr.in pads its
# reply with a trailing space the stylesheet's own padding then doubles.
out=${out#"${out%%[![:space:]]*}"}
out=${out%"${out##*[![:space:]]}"}
printf '%s\n' "${out#+}"
