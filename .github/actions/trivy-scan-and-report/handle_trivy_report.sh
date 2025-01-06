#!/bin/bash

# Input parameters
BLOCKING_LEVEL="$1"

# Function to extract vulnerabilities by severity
get_vulnerabilities() {
  jq -r "[.Results[] | .VULN[]? | select(.Severity == \"${1}\")]" ${{ inputs.output }}
}

# Function to get non-fixable vulnerabilities
get_non_fixable() {
  echo "$1" | jq '[.[] | select(.FixedVersion == null)]'
}

# Function to get fixable vulnerabilities
get_fixable() {
  echo "$1" | jq '[.[] | select(.FixedVersion != null)]'
}

# Function to count vulnerabilities
count() {
  echo "$1" | jq 'length'
}

# Function to print a summary of vulnerabilities
print() {
  echo "$1" | jq -r '.[] |
    if .FixedVersion == null then
      "\(.Severity) - \(.VulnerabilityID) - \(.Title)"
    else
      "\(.Severity) - \(.VulnerabilityID) - \(.Title) - Fixed Version: \(.FixedVersion)"
  end' | sort | uniq
}

# Declare associative arrays
declare -A VULN
declare -A VULN_COUNT
declare -A FIXABLE
declare -A FIXABLE_COUNT

SEVERITY_LEVELS=("CRITICAL" "HIGH" "MEDIUM" "LOW" "UNKNOWN")
for SEVERITY in "${SEVERITY_LEVELS[@]}"; do
  VULN["$SEVERITY"]=$(get_vulnerabilities "$SEVERITY")
  VULN_COUNT["$SEVERITY"]=$(count "${VULN["$SEVERITY"]}")
  FIXABLE["$SEVERITY"]=$(get_fixable "${VULN["$SEVERITY"]}")
  FIXABLE_COUNT["$SEVERITY"]=$(count "${FIXABLE["$SEVERITY"]}")
done

# Variable to store all blocking vulnerabilities
BLOCK_VULN=""
BLOCK_VULN_COUNT=0

case "$BLOCKING_LEVEL" in
  1)
    BLOCK_VULN="${FIXABLE["CRITICAL"]}"
    BLOCK_VULN_COUNT=${FIXABLE_COUNT["CRITICAL"]}
    ;;
  2)
    BLOCK_VULN="${VULN["CRITICAL"]} ${FIXABLE["HIGH"]}"
    BLOCK_VULN_COUNT=$((${VULN_COUNT["CRITICAL"]} + ${FIXABLE_COUNT["HIGH"]}))
    ;;
  3)
    BLOCK_VULN="${VULN["CRITICAL"]} ${VULN["HIGH"]} ${FIXABLE["MEDIUM"]}"
    BLOCK_VULN_COUNT=$((${VULN_COUNT["CRITICAL"]} + ${VULN_COUNT["HIGH"]} + ${FIXABLE_COUNT["MEDIUM"]}))
    ;;
  4)
    BLOCK_VULN="${VULN["CRITICAL"]} ${VULN["HIGH"]} ${VULN["MEDIUM"]} ${FIXABLE["LOW"]}"
    BLOCK_VULN_COUNT=$((${VULN_COUNT["CRITICAL"]} + ${VULN_COUNT["HIGH"]} + ${VULN_COUNT["MEDIUM"]} + ${FIXABLE_COUNT["LOW"]}))
    ;;
  5)
    BLOCK_VULN="${VULN["CRITICAL"]} ${VULN["HIGH"]} ${VULN["MEDIUM"]} ${VULN["LOW"]} ${VULN["UNKNOWN"]}"
    BLOCK_VULN_COUNT=$((${VULN_COUNT["CRITICAL"]} + ${VULN_COUNT["HIGH"]} + ${VULN_COUNT["MEDIUM"]} + ${VULN_COUNT["LOW"]} + ${VULN_COUNT["UNKNOWN"]}))
    ;;
esac

if [ $BLOCK_VULN_COUNT -gt 0 ]; then
  echo
  echo "$BLOCK_VULN_COUNT blocking vulnerabilities: image won't be pushed"
  echo
  echo "Aggregated vulnerability list"
  echo "==============================================================================================================================================="
  print "$BLOCK_VULN"
  echo "==============================================================================================================================================="
  exit 1
fi

echo "Congrats! The image does not have any blocking vulnerabilities"
echo
echo "Non-blocking vulnerabilities"
echo "==============================================================================================================================================="
if [ $BLOCKING_LEVEL -le 0 ]; then echo "Critical: ${COUNT['CRITICAL']}"; fi
if [ $BLOCKING_LEVEL -le 1 ]; then echo "High:     ${COUNT['HIGH']}"; fi
if [ $BLOCKING_LEVEL -le 2 ]; then echo "Medium:   ${COUNT['MEDIUM']}"; fi
if [ $BLOCKING_LEVEL -le 3 ]; then echo "Low:      ${COUNT['LOW']}"; fi
if [ $BLOCKING_LEVEL -le 4 ]; then echo "Unknown:  ${COUNT['UNKNOWN']}"; fi
echo 
echo "Aggregated vulnerability list"
echo "==============================================================================================================================================="
if [ $BLOCKING_LEVEL -le 0 ]; then print "${VULN['CRITICAL']}"; fi
if [ $BLOCKING_LEVEL -le 1 ]; then print "${VULN['HIGH']}"; fi
if [ $BLOCKING_LEVEL -le 2 ]; then print "${VULN['MEDIUM']}"; fi
if [ $BLOCKING_LEVEL -le 3 ]; then print "${VULN['LOW']}"; fi
if [ $BLOCKING_LEVEL -le 4 ]; then print "${VULN['UNKNOWN']}"; fi
echo "==============================================================================================================================================="