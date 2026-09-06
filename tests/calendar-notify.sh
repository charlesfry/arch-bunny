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
q3=$(date -d "$(date -d "@$now" +%Y-%m-01) -3 months" +%Y-%m-01)
q2=$(date -d "$(date -d "@$now" +%Y-%m-01) -2 months" +%Y-%m-01)
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

echo "== 13. MONTHLY positional BYDAY: right ordinal only =="
# Derive the ordinals by counting, not with the script's own (dom-1)/7+1
# formula: sharing the expression would hide an off-by-one in both.
dom=$(date -d "@$now" +%-d)
ym=$(date -d "@$now" +%Y-%m)
dim=$(date -d "$ym-01 +1 month -1 day" +%-d)
wd_of() { local w; w=$(date -d "$ym-$1" +%a); w=${w^^}; echo "${w:0:2}"; }
nth=0; for ((d = 1; d <= dom; d++)); do [[ $(wd_of "$d") == "$tdy" ]] && nth=$((nth + 1)); done
from_end=0; for ((d = dom; d <= dim; d++)); do [[ $(wd_of "$d") == "$tdy" ]] && from_end=$((from_end + 1)); done
wrong=$((nth % 5 + 1))
start2mo="DTSTART;TZID=America/New_York:$(date -d "$ym-01 -2 months" +%Y%m%d)T$hhmm"
run <<EOF
$(ev mpos "Positional Hit" "$start2mo" "RRULE:FREQ=MONTHLY;BYDAY=$nth$tdy"; end)
$(ev mplus "Positional Plus" "$start2mo" "RRULE:FREQ=MONTHLY;BYDAY=+$nth$tdy"; end)
$(ev mneg "Positional Miss" "$start2mo" "RRULE:FREQ=MONTHLY;BYDAY=$wrong$tdy"; end)
$(ev mlast "Positional FromEnd" "$start2mo" "RRULE:FREQ=MONTHLY;BYDAY=-$from_end$tdy"; end)
$(ev mlastx "Positional FromEnd Miss" "$start2mo" "RRULE:FREQ=MONTHLY;BYDAY=-$((from_end + 1))$tdy"; end)
$(ev mbare "Positional Bare" "$start2mo" "RRULE:FREQ=MONTHLY;BYDAY=$tdy"; end)
$(ev mmulti "Positional Multi" "$start2mo" "RRULE:FREQ=MONTHLY;BYDAY=$nth$tdy,4WE,-2MO"; end)
$(ev mmultix "Positional Multi Miss" "$start2mo" "RRULE:FREQ=MONTHLY;BYDAY=$wrong$tdy,4WE,-2MO"; end)
EOF
check "BYDAY=$nth$tdy fires on the ${nth}th $tdy" 1 'NOTIFY: Positional Hit'
check "BYDAY=+$nth$tdy (explicit +) fires too" 1 'NOTIFY: Positional Plus'
check "BYDAY=$wrong$tdy does not fire" 0 'NOTIFY: Positional Miss'
check "BYDAY=-$from_end$tdy counts back from month end" 1 'NOTIFY: Positional FromEnd'
check "BYDAY=-$((from_end + 1))$tdy is one too far back" 0 'NOTIFY: Positional FromEnd Miss'
check "BYDAY=$tdy (no ordinal) fires on any $tdy" 1 'NOTIFY: Positional Bare'
check "multi-weekday BYDAY matches on its $tdy term" 1 'NOTIFY: Positional Multi'
check "multi-weekday BYDAY with no matching term is silent" 0 'NOTIFY: Positional Multi Miss'

# Two cases today's date cannot distinguish on its own.
# (a) (d-1)/7+1 and d/7+1 agree unless d is a multiple of 7, so reach the next
#     such day with a long VALARM lead (+1h so the alarm is already due).
target=$(((dom / 7 + 1) * 7))
if ((target > dim)); then
	target=7; lead_d=$((dim - dom + 7)); tdate=$(date -d "$ym-01 +1 month +6 days" +%Y-%m-%d)
else
	lead_d=$((target - dom)); tdate="$ym-$(printf %02d "$target")"
fi
twd=$(date -d "$tdate" +%a); twd=${twd^^}; twd=${twd:0:2}
tnth=$(((target - 1) / 7 + 1))
# (b) a term whose ordinal matches today but whose weekday does not, paired with
#     a today-weekday term so it still clears the coarse weekday filter.
otherwd=MO; [[ "$tdy" == MO ]] && otherwd=TU
run <<EOF
$(ev mmul7 "Ordinal Mult7" "$start2mo" "RRULE:FREQ=MONTHLY;BYDAY=$tnth$twd"; alarm "-P${lead_d}DT1H"; printf 'END:VEVENT\r\n')
$(ev mmul7x "Ordinal Mult7 Off" "$start2mo" "RRULE:FREQ=MONTHLY;BYDAY=$((tnth + 1))$twd"; alarm "-P${lead_d}DT1H"; printf 'END:VEVENT\r\n')
$(ev mcross "Ordinal Crosstalk" "$start2mo" "RRULE:FREQ=MONTHLY;BYDAY=$nth$otherwd,$wrong$tdy"; end)
EOF
check "day $target is the ${tnth}th $twd, not the $((tnth + 1))th" 1 'NOTIFY: Ordinal Mult7'
check "day $target does not match ordinal $((tnth + 1))" 0 'NOTIFY: Ordinal Mult7 Off'
check "an ordinal match on the wrong weekday does not fire" 0 'NOTIFY: Ordinal Crosstalk'

echo "== 14. YEARLY on DTSTART's month and day =="
# Every DTSTART is 4 years back so a Feb 29 "today" still lands on a leap year.
md=$(date -d "@$now" +%m%d)
y4=$(($(date -d "@$now" +%Y) - 4))
mm=$(date -d "@$now" +%-m)
for k in 6 5 7 4 8; do
	om=$(((mm - 1 + k) % 12 + 1))
	date -d "$y4-$om-$dom" >/dev/null 2>&1 && break
done
# Same day-of-month, different month: a YEARLY branch that compared only the day
# would fire on this, and today is inside the candidate window so it is reachable.
other=$(printf '%02d%02d' "$om" "$dom")
run <<EOF
$(ev yr "Yearly Hit" "DTSTART;TZID=America/New_York:$y4${md}T$hhmm" "RRULE:FREQ=YEARLY"; end)
$(ev yrx "Yearly Month Miss" "DTSTART;TZID=America/New_York:$y4${other}T$hhmm" "RRULE:FREQ=YEARLY"; end)
$(ev yri "Yearly Interval Hit" "DTSTART;TZID=America/New_York:$y4${md}T$hhmm" "RRULE:FREQ=YEARLY;INTERVAL=2"; end)
$(ev yrix "Yearly Interval Miss" "DTSTART;TZID=America/New_York:$y4${md}T$hhmm" "RRULE:FREQ=YEARLY;INTERVAL=3"; end)
$(ev yrbd "Yearly Byday" "DTSTART;TZID=America/New_York:$y4${md}T$hhmm" "RRULE:FREQ=YEARLY;BYDAY=1TH"; end)
EOF
check "FREQ=YEARLY fires on the anniversary" 1 'NOTIFY: Yearly Hit'
check "FREQ=YEARLY checks the month, not just the day" 0 'NOTIFY: Yearly Month Miss'
check "FREQ=YEARLY;INTERVAL=2 fires 4 years on" 1 'NOTIFY: Yearly Interval Hit'
check "FREQ=YEARLY;INTERVAL=3 silent 4 years on" 0 'NOTIFY: Yearly Interval Miss'
check "FREQ=YEARLY;BYDAY=... degrades to the anniversary, not silence" 1 'NOTIFY: Yearly Byday'

echo "== 15. BYDAY as a limit, not an expansion =="
# Both regressions the positional-BYDAY change introduced: BYSETPOS selects one
# member of the expanded set, and BYDAY+BYMONTHDAY intersect.
# Anchored to today so both directions of the intersection are exercised on any
# date, rather than depending on when the next literal Friday the 13th falls.
otherdom=$((dom % 28 + 1))
run <<EOF
$(ev sp "Setpos Weekday" "DTSTART;TZID=America/New_York:20260831T170000" "RRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1"; alarm "-P7D"; printf 'END:VEVENT\r\n')
$(ev both "Both Match" "$start2mo" "RRULE:FREQ=MONTHLY;BYDAY=$tdy;BYMONTHDAY=$dom"; end)
$(ev onlyday "Only Weekday Matches" "$start2mo" "RRULE:FREQ=MONTHLY;BYDAY=$tdy;BYMONTHDAY=$otherdom"; end)
$(ev bmd "Plain Monthday" "$start2mo" "RRULE:FREQ=MONTHLY;BYMONTHDAY=$dom"; end)
EOF
check "BYSETPOS rule is skipped, not fired on every weekday" 0 'NOTIFY: Setpos Weekday'
check "BYDAY+BYMONTHDAY both matching fires" 1 'NOTIFY: Both Match'
check "BYDAY matching but BYMONTHDAY not is silent" 0 'NOTIFY: Only Weekday Matches'
check "BYMONTHDAY alone still expands" 1 'NOTIFY: Plain Monthday'

echo "== 16. malformed INTERVAL=0 must not divide by zero =="
run <<EOF
$(ev iv0 "Interval Zero" "DTSTART;TZID=America/New_York:$(date -d "$ym-01 -2 months" +%Y%m%d)T$hhmm" "RRULE:FREQ=DAILY;INTERVAL=0"; end)
EOF
check "INTERVAL=0 treated as 1, event still fires" 1 'NOTIFY: Interval Zero'
if grep -q 'division by 0' "$here/err"; then
	fail=$((fail + 1)); printf '  FAIL INTERVAL=0 wrote a division-by-zero diagnostic to stderr\n'
else
	pass=$((pass + 1)); printf '  ok   INTERVAL=0 leaves stderr clean\n'
fi

echo
echo "passed=$pass failed=$fail"
[[ -s "$here/err" ]] && { echo "--- stderr from last run ---"; cat "$here/err"; }
exit $((fail > 0))
