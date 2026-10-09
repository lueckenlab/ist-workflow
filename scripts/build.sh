#!/bin/bash
# Build the workflow into target/. Fetches the method components from
# openproblems-bio/task_ist_preprocessing@build/main into target/dependencies/.
set -e
cd "$(git rev-parse --show-toplevel)"

viash ns build --parallel "$@"
