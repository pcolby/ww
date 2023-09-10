#!/usr/bin/env bash
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

# Fetch the logs for this workflow run. Note, we can't use `gh run view --log` here, because that
# command still has bugs dealing with unusual characters.
logArchiveFileName="$CACHE_DIR/$owner-$repo-$runId${attemptNumber:+-$attemptNumber}.zip"
[[ -s "$logArchiveFileName" ]] || {
  apiPath="repos/$owner/$repo/actions/runs/$runId${attemptNumber:+/attempts/$attemptNumber}/logs"
  echo "Fetching $apiPath to $logArchiveFileName" >&2
  gh api "$apiPath" > "$logArchiveFileName"
}

# Fetch the workflow run details, and begin a Mermaid Gantt chart.
echo 'Fetching run details...' >&2
runView=$(gh run view "$runId" --repo "$owner/$repo" --json 'workflowName,displayTitle,jobs,url')
echo "$(cat <<--
	---
	displayMode: compact
	---
	gantt
	  title $(jq -er '.displayTitle' <<< "$runView") ($(jq -er '.workflowName' <<< "$runView"), run $runId${attemptNumber:+, attempt #$attemptNumber})
	  dateFormat YYYY-MM-DD HH:MM:SS.SSS
	  %% $(jq -er '.url' <<< "$runView")
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

    ts=( $(unzip -p "$logArchiveFileName" "$stepLogFileName" | sed -En -e 's/ .*//' -e '1p;$p' || true) )
    [[ -v ts ]] || continue

    printf -v stepDuration '%09d' \
      "$(( $(date -d "${ts[1]}" '+%s%N') - $(date -d "${ts[0]}" '+%s%N') ))"

    printf '  %s :%s %s, %1.3fs\n' "${stepName//:}" \
      '' \
      "$(date -d "${ts[0]}" '+%F %T.%N')" \
      "${stepDuration::-9}.${stepDuration: -9}"
  done < <(jq -ce '.steps|sort_by(.number)[]|select(.conclusion != "skipped")' <<< "$job")
done < <(jq -ce '.jobs|sort_by([.startedAt,.completedAt])[]' <<< "$runView")
