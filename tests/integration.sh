#!/usr/bin/env bash
set -euo pipefail

timeout 120 bash scripts/integration-test.sh
