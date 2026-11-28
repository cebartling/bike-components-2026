# Build and test commands (ADR-0012). Run `just` to list them.

# ADR-0012: identifiers reach xcodebuild as "$1", never through {{…}},
# which would hand a raw identifier's backticks to the shell.
set positional-arguments

simulator := "platform=iOS Simulator,name=iPhone 18 Pro,OS=27.2"
derived_data := justfile_directory() / ".build/DerivedData"
result_bundle := justfile_directory() / ".build/TestResults.xcresult"

default:
    @just --list

# Build the app for the iOS Simulator.
build:
    xcodebuild build -project BikeComponents.xcodeproj -scheme BikeComponents -destination "{{simulator}}" -derivedDataPath "{{derived_data}}" -quiet

# Run every test in BikeComponentsKit on the iOS Simulator.
test:
    @just _run-tests

# Run one test, suite or target, e.g. just test-only 'BikeComponentsCoreTests/`Source errors`'
test-only identifier:
    @just _run-tests "-only-testing:$1"

[private]
_run-tests *filter:
    #!/usr/bin/env bash
    set -euo pipefail
    cd BikeComponentsKit
    rm -rf "{{result_bundle}}"
    rm -f "{{derived_data}}"/Build/Products/*.xctestrun
    xcodebuild build-for-testing -scheme BikeComponentsKit -destination "{{simulator}}" -derivedDataPath "{{derived_data}}" -quiet
    xctestrun=$(ls "{{derived_data}}"/Build/Products/*.xctestrun)
    # ADR-0007: Core Data's concurrency assertions are on in every test process.
    targets=$(plutil -extract TestConfigurations.0.TestTargets raw "$xctestrun")
    for ((i = 0; i < targets; i++)); do
        arguments=":TestConfigurations:0:TestTargets:$i:CommandLineArguments"
        /usr/libexec/PlistBuddy -c "Add $arguments: string -com.apple.CoreData.ConcurrencyDebug" -c "Add $arguments: string 1" "$xctestrun"
    done
    xcodebuild test-without-building -xctestrun "$xctestrun" -destination "{{simulator}}" -resultBundlePath "{{result_bundle}}" -quiet "$@"
    # ADR-0012: a filter that matches nothing passes in xcodebuild, so fail on zero tests.
    count=$(xcrun xcresulttool get test-results summary --path "{{result_bundle}}" | plutil -extract totalTestCount raw -)
    if [ "$count" -eq 0 ]; then
        echo "error: no tests ran${1:+ for $1}" >&2
        exit 1
    fi
    echo "$count tests ran"
