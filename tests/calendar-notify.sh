#!/bin/bash
# End-to-end checks for bunny-calendar-notify against synthetic calendars.
# Not a bats test (see install.bats etc.) -- this drives the real script
# end-to-end against synthetic ICS bodies and a stubbed bunny-notify, which a
# bats mock couldn't do as directly. Run directly: ./tests/calendar-notify.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../local/bin/bunny-calendar-notify"
export TZ=America/New_York
export XDG_CONFIG_HOME="$here/cfg" XDG_STATE_HOME="$here/state"
export PATH="$here/bin:$PATH"
mkdir -p "$here/cfg/bunny" "$here/bin" "$here/state"
cat >"$here/bin/bunny-notify" <<'EOF'
#!/bin/bash
args=(); while [[ $# -gt 0 ]]; do case "$1" in -i|-a) shift 2;; *) args+=("$1"); shift;; esac; done
printf 'NOTIFY: %s | %s\n' "${args[0]}" "${args[1]:-}"
EOF
chmod +x "$here/bin/bunny-notify"

now=$(date +%s)
u() { date -u -d "@$1" +%Y%m%dT%H%M%SZ; }   # UTC form
l() { date -d "@$1" +%Y%m%dT%H%M%S; }       # local (TZID) form
d() { date -d "@$1" +%Y%m%d; }

pass=0 fail=0
state="$here/state/bunny-calendar-notify/notified"
check_start() { # name expected_epoch  -- assert an occurrence with this start was notified
	local name="$1" want="$2"
	if cut -f1 "$state" 2>/dev/null | cut -d'|' -f2 | grep -qx "$want"; then pass=$((pass+1)); printf '  ok   %s\n' "$name"
	else fail=$((fail+1)); printf '  FAIL %s (no notification for start=%s [%s]; got: %s)\n' "$name" "$want" "$(date -d @$want +%F\ %T)" "$(cut -f1 "$state" 2>/dev/null | tr '\n' ' ')"; fi
}
check_nostart() {
	local name="$1" want="$2"
	if cut -f1 "$state" 2>/dev/null | cut -d'|' -f2 | grep -qx "$want"; then fail=$((fail+1)); printf '  FAIL %s (unwanted notification for start=%s [%s])\n' "$name" "$want" "$(date -d @$want +%F\ %T)"
	else pass=$((pass+1)); printf '  ok   %s\n' "$name"; fi
}
check() { # name expected_regex_count regex
	local name="$1" want="$2" re="$3" got
	got=$(grep -cE "$re" "$here/out" || true)
	if [[ "$got" == "$want" ]]; then pass=$((pass+1)); printf '  ok   %s\n' "$name"
	else fail=$((fail+1)); printf '  FAIL %s (want %s matches of /%s/, got %s)\n' "$name" "$want" "$re" "$got"; fi
}

run() { # ics-body...
	rm -rf "$here/state"; mkdir -p "$here/state"
	{ printf 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\n'; cat; printf 'END:VCALENDAR\r\n'; } >"$here/cal.ics"
	printf 'file://%s\nfile://%s\n' "$here/cal.ics" "$here/cal.ics" >"$here/cfg/bunny/calendar-ics-url"
	"$script" >"$here/out" 2>"$here/err"
	echo "exit=$?" >>"$here/err"
}

ev() { # uid summary dtstart-line [extra lines...]
	printf 'BEGIN:VEVENT\r\nUID:%s\r\nSUMMARY:%s\r\n%s\r\nSTATUS:CONFIRMED\r\n' "$1" "$2" "$3"
	shift 3
	for x in "$@"; do printf '%s\r\n' "$x"; done
}
end() { printf 'END:VEVENT\r\n'; }
alarm() { printf 'BEGIN:VALARM\r\nACTION:DISPLAY\r\nDESCRIPTION:x\r\nTRIGGER:%s\r\nEND:VALARM\r\n' "$1"; }

echo "== 1. multi-VALARM: both configured reminders fire =="
run <<EOF
$(ev multi "Multi Alarm" "DTSTART:$(u $((now+3600)))" ; alarm "-P0DT1H0M0S"; alarm "-P1D"; printf 'END:VEVENT\r\n')
EOF
cat "$here/out"
check "two notifications for two VALARMs" 2 'NOTIFY: Multi Alarm'
awk -F'[|\t]' '{print "  start="strftime("%F %T %Z",$2)"  lead="$3"s"}' "$here/state/bunny-calendar-notify/notified"

echo "== 2. P#W trigger =="
run <<EOF
$(ev week "Week Lead" "DTSTART:$(u $((now+3600)))"; alarm "-P1W"; printf 'END:VEVENT\r\n')
EOF
check "-P1W lead is 604800s, alarm already due" 1 'NOTIFY: Week Lead'
awk -F"[|\\t]" "{print \"  start=\"strftime(\"%F %T %Z\",\$2)\"  lead=\"\$3\"s\"}" "$here/state/bunny-calendar-notify/notified"

echo "== 3. MONTHLY BYMONTHDAY + INTERVAL =="
q3=$(date -d "@$now" +%Y)-$(printf %02d $(( $(date -d "@$now" +%-m) - 3 )))-$(date -d "@$now" +%d)
q2=$(date -d "@$now" +%Y)-$(printf %02d $(( $(date -d "@$now" +%-m) - 2 )))-$(date -d "@$now" +%d)
hhmm=$(date -d "@$((now+300))" +%H%M%S)
run <<EOF
$(ev q3 "Quarterly Hit" "DTSTART;TZID=America/New_York:$(date -d "$q3" +%Y%m%d)T$hhmm" "RRULE:FREQ=MONTHLY;WKST=SU;INTERVAL=3;BYMONTHDAY=$(date -d "@$now" +%d)"; end)
$(ev q2 "Quarterly Miss" "DTSTART;TZID=America/New_York:$(date -d "$q2" +%Y%m%d)T$hhmm" "RRULE:FREQ=MONTHLY;WKST=SU;INTERVAL=3;BYMONTHDAY=$(date -d "@$now" +%d)"; end)
EOF
check "quarterly on-cycle month fires" 1 'NOTIFY: Quarterly Hit'
check "quarterly off-cycle month silent" 0 'NOTIFY: Quarterly Miss'

echo "== 4. MONTHLY BYMONTHDAY=-1 (last day of month) via a 30-day lead =="
run <<EOF
$(ev lastday "Last Day" "DTSTART;TZID=America/New_York:20260430T163000" "RRULE:FREQ=MONTHLY;WKST=SU;INTERVAL=1;BYMONTHDAY=-1"; alarm "-P30D"; printf 'END:VEVENT\r\n')
EOF
check "last-day-of-month occurrence found" 1 'NOTIFY: Last Day'
awk -F'[|\t]' '{print "  occurrence: "strftime("%F %T %Z",$2)"  lead="$3"s"}' "$here/state/bunny-calendar-notify/notified" 2>/dev/null || cat "$here/state/bunny-calendar-notify/notified"

echo "== 5. WEEKLY INTERVAL=2 anchored to WKST, not DTSTART's weekday =="
# today is $(date -d "@$now" +%a). DTSTART on a Sunday, BYDAY includes today.
sun_wk0=$(date -d "last sunday - 7 days" +%Y%m%d)   # 2 week-starts back
sun_wk1=$(date -d "last sunday" +%Y%m%d)
tdy=$(date -d "@$now" +%a); tdy=${tdy^^}; tdy=${tdy:0:2}
run <<EOF
$(ev wk_even "Weekly Even" "DTSTART;TZID=America/New_York:${sun_wk0}T$hhmm" "RRULE:FREQ=WEEKLY;WKST=MO;INTERVAL=2;BYDAY=SU,$tdy"; end)
$(ev wk_odd "Weekly Odd" "DTSTART;TZID=America/New_York:${sun_wk1}T$hhmm" "RRULE:FREQ=WEEKLY;WKST=MO;INTERVAL=2;BYDAY=SU,$tdy"; end)
EOF
echo "  DTSTART even-week=$sun_wk0 odd-week=$sun_wk1 today=$(date -d @$now +%F\ %a)"
check "biweekly, today in an on-cycle week, fires" 1 'NOTIFY: Weekly Even'
check "biweekly, today in an off-cycle week, silent" 0 'NOTIFY: Weekly Odd'

echo "== 6. EXDATE in UTC form on a TZID event (crosses the date line) =="
# 21:00 local today = next calendar day in UTC; lead -P2D so today+tomorrow both due
t21=$(date -d "today 21:00" +%s); t21n=$((t21+86400))
run <<EOF
$(ev exd "Exdated" "DTSTART;TZID=America/New_York:$(l $t21)" "RRULE:FREQ=DAILY" "EXDATE:$(u $t21)"; alarm "-P2D"; printf 'END:VEVENT\r\n')
EOF
check "UTC-form EXDATE suppresses the right day" 1 'NOTIFY: Exdated'
check_nostart "excluded occurrence (today 21:00) not notified" "$t21"
check_start   "following occurrence (tomorrow 21:00) notified" "$t21n"
awk -F'[|\t]' '{print "  notified occurrence: "strftime("%F %T %Z",$2)"   (excluded: '"$(date -d @$t21 +%F\ %T)"')"}' "$here/state/bunny-calendar-notify/notified"

echo "== 7. RECURRENCE-ID override (moved) and STATUS:CANCELLED override =="
run <<EOF
$(ev ovr "Base Series" "DTSTART;TZID=America/New_York:$(l $t21)" "RRULE:FREQ=DAILY"; alarm "-P2D"; printf 'END:VEVENT\r\n')
$(ev ovr "Moved Instance" "DTSTART;TZID=America/New_York:$(l $((t21+3600)))" "RECURRENCE-ID:$(u $t21)"; alarm "-P2D"; printf 'END:VEVENT\r\n')
EOF
check "moved instance notified" 1 'NOTIFY: Moved Instance'
check "base occurrence it replaced is suppressed" 1 'NOTIFY: Base Series'
check_nostart "overridden base occurrence not notified" "$t21"
check_start   "un-overridden next occurrence notified" "$t21n"
run <<EOF
$(ev can "Base Series" "DTSTART;TZID=America/New_York:$(l $t21)" "RRULE:FREQ=DAILY"; alarm "-P2D"; printf 'END:VEVENT\r\n')
BEGIN:VEVENT
UID:can
SUMMARY:Cancelled Instance
DTSTART;TZID=America/New_York:$(l $t21)
RECURRENCE-ID:$(u $t21)
STATUS:CANCELLED
END:VEVENT
EOF
check "cancelled instance not notified" 0 'NOTIFY: Cancelled Instance'
check "only tomorrow's occurrence remains" 1 'NOTIFY: Base Series'
check_nostart "cancelled occurrence not notified" "$t21"
check_start   "next occurrence still notified" "$t21n"

echo "== 8. VALARM SUMMARY must not clobber a parameterized event SUMMARY =="
run <<EOF
BEGIN:VEVENT
UID:sumleak
SUMMARY;LANGUAGE=en-US:Real Title
DTSTART:$(u $((now+300)))
STATUS:CONFIRMED
BEGIN:VALARM
ACTION:EMAIL
TRIGGER:-PT10M
SUMMARY:Alarm Subject
DESCRIPTION:x
END:VALARM
END:VEVENT
EOF
check "parameterized SUMMARY used" 1 'NOTIFY: Real Title'
check "VALARM SUMMARY not used" 0 'NOTIFY: Alarm Subject'

echo "== 9. UNTIL: date-only inclusive, date-time exact =="
run <<EOF
$(ev untl "Until Today" "DTSTART;TZID=America/New_York:$(date -d '30 days ago' +%Y%m%d)T$hhmm" "RRULE:FREQ=DAILY;UNTIL=$(d $now)"; end)
$(ev untx "Until Noon" "DTSTART;TZID=America/New_York:$(date -d '30 days ago' +%Y%m%d)T$(date -d 'today 21:00' +%H%M%S)" "RRULE:FREQ=DAILY;UNTIL=$(d $now)T120000Z"; alarm "-P0DT12H0M0S"; printf 'END:VEVENT\r\n')
EOF
check "date-only UNTIL includes that whole day" 1 'NOTIFY: Until Today'
check "date-time UNTIL excludes a later same-day occurrence" 0 'NOTIFY: Until Noon'

echo "== 10. malformed event must not abort the run =="
run <<EOF
BEGIN:VEVENT
UID:broken
SUMMARY:Broken
DTSTART:2026XX99TZZZZZZ
END:VEVENT
$(ev after "Survivor" "DTSTART:$(u $((now+300)))"; end)
EOF
check "later events still processed after a bad DTSTART" 1 'NOTIFY: Survivor'

echo "== 11. WEEKLY without BYDAY only fires on DTSTART's weekday =="
# DTSTART 3 days ago (a different weekday); today must NOT match
run <<EOF
$(ev nobyday "No Byday" "DTSTART;TZID=America/New_York:$(date -d '3 days ago' +%Y%m%d)T$hhmm" "RRULE:FREQ=WEEKLY"; end)
$(ev nobyday2 "No Byday Same Dow" "DTSTART;TZID=America/New_York:$(date -d '7 days ago' +%Y%m%d)T$hhmm" "RRULE:FREQ=WEEKLY"; end)
EOF
check "weekly, no BYDAY, wrong weekday -> silent" 0 'NOTIFY: No Byday \|'
check "weekly, no BYDAY, same weekday -> fires" 1 'NOTIFY: No Byday Same Dow'

echo "== 12. BYDAY restricts DAILY (every-weekday rules) =="
run <<EOF
$(ev dwd "Daily Weekdays" "DTSTART;TZID=America/New_York:$(date -d '10 days ago' +%Y%m%d)T$hhmm" "RRULE:FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR"; end)
$(ev dall "Daily All" "DTSTART;TZID=America/New_York:$(date -d '10 days ago' +%Y%m%d)T$hhmm" "RRULE:FREQ=DAILY"; end)
EOF
if [[ "$tdy" == SA || "$tdy" == SU ]]; then want=0; else want=1; fi
check "FREQ=DAILY;BYDAY=MO-FR on a $tdy" "$want" 'NOTIFY: Daily Weekdays'
check "FREQ=DAILY unrestricted fires" 1 'NOTIFY: Daily All'

echo "== 13. MONTHLY with positional BYDAY is skipped, not mis-fired =="
run <<EOF
$(ev mpos "Monthly Positional" "DTSTART;TZID=America/New_York:$(date -d '2 months ago' +%Y%m%d)T$hhmm" "RRULE:FREQ=MONTHLY;BYDAY=1$tdy"; end)
EOF
check "MONTHLY;BYDAY=1$tdy does not fire on every $tdy" 0 'NOTIFY: Monthly Positional'

echo
echo "passed=$pass failed=$fail"
[[ -s "$here/err" ]] && { echo "--- stderr from last run ---"; cat "$here/err"; }
exit $((fail > 0))
