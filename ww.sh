#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2023 Paul Colby <git@colby.id.au>
# SPDX-License-Identifier: GPL-3.0-or-later

set -o errexit -o noclobber -o nounset -o pipefail
shopt -s inherit_errexit

: "${CACHE_DIR:=.}"

function showUsage {
  echo "$(cat <<--
	Usage: ${BASH_SOURCE[0]} <run_url> > mermaid.txt
	   or: ${BASH_SOURCE[0]} <owner> <repo> <run_id> [<attempt_number>] > mermaid.txt
	-
	)"
}

# Parse the CLI's postional arguments.
if [[ $# -eq 1 ]]; then
  read -r owner repo runId attemptNumber < <(
    sed -Ene 's|.*/([^/]*)/([^/]*)/actions/runs/([0-9]+)(/attempts/([0-9]+))?$|\1 \2 \3 \5|p' <<< "$1"
  ) || { echo "Invalid workflow run URL: $1" >&2; showUsage; exit 2; }
  [[ -n "$attemptNumber" ]] || unset attemptNumber
elif [[ $# -ge 3 && $# -le 4 ]]; then
  username=$1; repo=$2; runId=$3
  [[ $# -lt 4 ]] || attemptNumber=$4
else
  showUsage; exit 1
fi

# Fetch the run details.
runApiPath="/repos/$owner/$repo/actions/runs/$runId${attemptNumber:+/attempts/$attemptNumber}"
echo "Fetching $runApiPath" >&2
runDetails=$(gh api "$runApiPath")
runAttempt=$(jq -er '.run_attempt' <<< "$runDetails")
[[ "$runAttempt" -eq 0 ]] || {
  echo 'Note: not the first run attempt, so ignoring unmatched log files.' >&2
}

# Fetch the run jobs.
jobsApiPath=$(jq -er '.jobs_url' <<< "$runDetails")
echo "Fetching $jobsApiPath" >&2
runJobs=$(gh api "$jobsApiPath")

# Fetch the run logs.
logsArchiveFileName="$CACHE_DIR/$owner-$repo-$runId${attemptNumber:+-$attemptNumber}.zip"
[[ -s "$logsArchiveFileName" ]] || {
  logsApiPath=$(jq -er '.logs_url' <<< "$runDetails")
  echo "Fetching $logsApiPath to $logsArchiveFileName" >&2
  gh api "$logsApiPath" > "$logsArchiveFileName"
}

echo "$(cat <<--
	---
	displayMode: compact
	---
	gantt
	  title $(jq -er '[.name,(.id|tostring),.run_attempt|tostring]|join(" #")' <<< "$runDetails")
	  dateFormat YYYY-MM-DD HH:MM:SS.SSS
	  %% $(jq -er '.html_url' <<< "$runDetails")
	-
	)"

# Add sections and tasks to the Gantt chart.
while IFS= read -r job; do
  jobName=$(jq -er '.name' <<< "$job")
  printf '\n  section %s\n' "$jobName"
  while IFS= read -r step; do
    # echo "step: $step" #  {"conclusion":"success","name":"Set up job","number":1,"status":"completed"}
    stepName=$(jq -er '.name' <<< "$step")
    stepNumber=$(jq -er '.number' <<< "$step")

    # \todo add `crit` and/or `active` and/or `done` according the the step's .conclusion and/or .status.

    printf -v stepLogFileName "%s/%d_%s.txt" \
      "$(tr -d '/:|' <<< "${jobName//[/\\&}")" \
      "$stepNumber" \
      "$(tr -d '/:|' <<< "${stepName//[/\\&}")"

    ts=( $(unzip -p "$logsArchiveFileName" "$stepLogFileName" | sed -En -e 's/ .*//' -e '1p;$p' || true) )
    [[ -v ts ]] || continue

    printf -v stepDuration '%09d' \
      "$(( $(date -d "${ts[1]}" '+%s%N') - $(date -d "${ts[0]}" '+%s%N') ))"

    printf '  %s :%s %s, %1.3fs\n' "${stepName//:}" \
      '' \
      "$(date -d "${ts[0]}" '+%F %T.%N')" \
      "${stepDuration::-9}.${stepDuration: -9}"
  done < <(jq -ce '.steps|sort_by(.number)[]|select(.conclusion != "skipped")' <<< "$job")
done < <(jq -ce '.jobs|sort_by([.startedAt,.completedAt])[]' <<< "$runJobs")
