#!/bin/bash
# Lorem Ipsum (Lopsem Pilore) Text Generator
# Generates placeholder text paragraphs

set -e

PARAGRAPHS=${1:-3}

SENTENCES=(
  "Lorem ipsum dolor sit amet, consectetur adipiscing elit."
  "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."
  "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris."
  "Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore."
  "Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia."
  "Nulla pariatur excepteur sint occaecat cupidatat non proident."
  "Curabitur pretium tincidunt lacus nulla gravida orci."
  "Fusce dapibus, tellus ac cursus commodo, tortor mauris condimentum nibh."
  "Donec sodales sagittis magna sed consequat leo urna molestie at."
  "Maecenas sed diam eget risus varius blandit sit amet non magna."
  "Praesent commodo cursus magna vel scelerisque nisl consectetur et."
  "Vivamus sagittis lacus vel augue laoreet rutrum faucibus dolor auctor."
)

NUM_SENTENCES=${#SENTENCES[@]}

generate_paragraph() {
  local count=$((RANDOM % 4 + 3))
  local paragraph=""
  for ((i = 0; i < count; i++)); do
    local idx=$((RANDOM % NUM_SENTENCES))
    paragraph+="${SENTENCES[$idx]} "
  done
  echo "$paragraph"
}

echo "=== Lopsem Pilore Generator ==="
echo "Generating $PARAGRAPHS paragraph(s)..."
echo ""

for ((p = 1; p <= PARAGRAPHS; p++)); do
  generate_paragraph
  echo ""
done
