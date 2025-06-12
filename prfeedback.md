In test/shared/csv_test.exs at line 4, the alias `Parser` is misleadingly
renamed to `CSV`, which confuses readers expecting a CSV module. To fix this,
rename the alias to `Parser` or remove the `as:` clause entirely so the alias
matches the original module name, improving clarity and reducing confusion.

In lib/wanderer_kills/killmails/zkb_client.ex at lines 472-473, the function
base_url/0 currently fetches the base_url from Config.zkb() every time it is
called, causing repeated application environment look-ups. To optimize, cache
the base_url value once by storing it in a module attribute initialized at
runtime, for example using @after_compile to set the attribute, and then have
base_url/0 return this cached attribute instead of calling Config.zkb().base_url
each time.

In lib/wanderer_kills/killmails/zkb_client.ex around lines 118 to 123, the
Logger.debug call passes a map as the second argument, but Logger.debug/2
requires a keyword list for metadata. Convert the map to a keyword list by
replacing the %{...} with [...], using key: value pairs instead of map syntax to
fix the FunctionClauseError.

In lib/wanderer_kills/killmails/pipeline/enricher.ex around lines 183 to 186,
the Logger.warning call incorrectly passes a map as metadata, but Logger expects
a keyword list. Convert the map with keys :error and :killmail_id into a keyword
list by replacing the map syntax with square brackets and using atom keys to fix
the compilation error.

In test/integration/cache_migration_test.exs around lines 191 to 195, the test
title "unified ESI DataFetcher works correctly" no longer matches the
implementation because it now uses WandererKills.ESI.Client. Rename the test
description to accurately reflect the current client being tested to improve
clarity and avoid confusion.

In test/fetcher/zkb_service_test.exs at line 34 and other specified lines, the
base URL "https://zkb.test.local" is hard-coded in multiple mock expectations.
To fix this, define a variable or module attribute at the start of the test
block or in a shared helper that retrieves the base URL from the application
config using Application.get_env(:wanderer_kills, :zkb)[:base_url] or
WandererKills.Config.zkb().base_url, then replace all hard-coded URL strings
with this variable to keep the tests DRY and maintainable.

In lib/wanderer_kills/redisq.ex at line 16, the alias has been updated from
WandererKills.ESI.DataFetcher to WandererKills.ESI.Client, but there are still
many references to the old module name across the codebase. To fix this, search
the entire project for any remaining occurrences of
WandererKills.ESI.DataFetcher and update them to WandererKills.ESI.Client. This
includes renaming modules like DataFetcherBehaviour to ClientBehaviour, updating
@behaviour annotations, modifying documentation examples, and changing imports
in test and mock files to ensure consistency with the new module name.

In lib/wanderer_kills/redisq.ex around lines 257 to 276, the legacy_kills
counters are logged but never incremented because update_stats/2 does not handle
them and process_legacy_kill/2 returns only :kill_received, :kill_older, or
:kill_skipped. To fix this, modify process_legacy_kill/2 to return a distinct
atom for legacy kills, update update_stats/2 to increment the legacy_kills
counter when this atom is received, and adjust all callers like next_schedule/2
to handle the new atom accordingly.

In test/wanderer_kills/subscriptions/webhook_notifier_test.exs around lines 68
to 70, the test for no HTTP request on blank URLs currently relies on no
expectations being set, which is implicit and weak. To fix this, explicitly stub
the HTTP mock with an expectation of zero calls to the post function, providing
a callback that fails the test if called. This ensures the test fails if an HTTP
request is accidentally made, making the test's intent clear and robust.

In test/wanderer_kills/subscriptions/webhook_notifier_test.exs around lines 1 to
10, the test uses async mode with ExUnit.Case but does not enable global Mox
mode, which can cause race conditions and unexpected call errors. Fix this by
adding `setup :set_mox_global` to the test module setup callbacks or
alternatively call `Mox.set_mox_global/0` in test_helper.exs to enable global
Mox mode for all async tests.

In docs/README.md around lines 33 to 46, the subsection headings and lists lack
blank lines before and after them, violating markdown lint rules MD022 and
MD032. Add a blank line before each heading (e.g., ### 1. REST API) and also add
blank lines before and after each list to ensure proper spacing and pass
automated markdown linters.

In docs/README.md at line 51, the file currently ends without a trailing
newline, which causes Git diff noise. Add a single newline character at the end
of the file to ensure it ends with a newline and complies with MD047.

In docs/README.md around lines 3 to 17, add the definite article "the" before
"primary documentation source" on line 7 to correct the wording. Change the
phrase to "This is the primary documentation source for WandererKills service."

In config/runtime.exs around lines 38 to 46, the log level determination uses a
case statement matching string values, but config_env() returns an atom, causing
mismatches and defaulting to :info. To fix this, ensure the case matches on
atoms instead of strings by removing the string quotes around "prod", "test",
and "dev" so they match the atom values returned by config_env(). This will
correctly set log levels in dev and test environments when MIX_ENV is unset.

In lib/wanderer_kills/subscriptions/webhook_notifier.ex around lines 159 to 162,
the validate_webhook_url/1 function currently returns :ok for any non-empty
string, which is insufficient validation. Update this function to parse the URL
using URI.parse/1, then check that the scheme is either "http" or "https" and
that a host is present. Return :ok only if these conditions are met; otherwise,
return an appropriate error tuple indicating invalid URL.

In test/killmails/store_event_streaming_test.exs around lines 329 to 336, the
assertion that the length of events equals 10 is fragile because it assumes no
prior data exists, which can cause flaky tests if previous inserts leak. To fix
this, either call KillmailStore.clear() at the start of the test to ensure a
clean state or change the assertion to check that the length of events is at
least 10 and verify that the 10 new event IDs are present, ensuring the test
remains deterministic.

In lib/wanderer_kills/killmails/pipeline/coordinator.ex around lines 477 to 485,
the rescue clause currently catches all exceptions broadly, which can mask
unexpected bugs. Modify the rescue to catch only specific, expected error types
related to killmail parsing. Remove the generic catch-all rescue to allow
unknown exceptions to crash and surface during testing, improving debugging and
error visibility.

In lib/wanderer_kills/esi/client.ex around lines 95 to 97, the get_system
function currently bypasses the cache by directly calling fetch_from_api, unlike
other entity fetches that use Helper.get_or_set/3 for caching. To fix this,
modify get_system to use Helper.get_or_set/3 with :system and system_id as keys
and fetch_from_api as the fallback function, restoring caching behavior and
reducing API load.

In example.dockerfile around lines 85 to 88, the Dockerfile copies and
references a release named 'wanderer_notifier' which does not exist; the actual
release produced by 'mix release' is 'wanderer_kills'. Update the COPY command
and any entrypoint or runtime references from 'wanderer_notifier' to
'wanderer_kills' to match the real release name and ensure the container starts
correctly.

In test/wanderer_kills/subscription_manager_test.exs around lines 169 to 171,
replace the fixed Process.sleep(100) call with a deterministic wait by using
assert_receive/3 to wait for the expected PubSub or event message, or use
Task.await/2 to wait for the async task completion. This ensures the test only
proceeds after the async work is done, making it reliable across different CI
environments.

In test/wanderer_kills/subscription_manager_test.exs around lines 10 to 32,
avoid manually starting and stopping globally registered processes like
TaskSupervisor and Phoenix.PubSub in the module setup, as this causes race
conditions with other async test suites. Instead, use start_supervised/1 within
each test to start these supervisors scoped to the test lifecycle, or start them
once globally in test_helper.exs and remove any manual Process.exit/2 calls in
on_exit callbacks to prevent flaky test failures.

In test/wanderer_kills/subscriptions/broadcaster_test.exs around lines 10 to 22,
the test subscribes to PubSub topics without ensuring the PubSub process is
running, which can cause crashes if the process is stopped by other tests. To
fix this, add a supervised start of the PubSub process in a setup_all block
before subscribing, ensuring the PubSub system is running for all tests in the
suite.

In test/wanderer_kills/subscriptions/broadcaster_test.exs around lines 218 to
235, the for-comprehension uses assert_receive with a 1000 ms timeout repeated
30 times, causing up to 30 seconds of wait on failure. To fix this, replace the
loop with a single receive block that collects all messages at once or reduce
the timeout significantly to avoid long delays. This change will help reveal
failures faster and improve test diagnostics.

In config/test.exs around lines 12 to 18, the cache TTL values are set to 1
second, which is too short and can cause flaky test failures due to cache expiry
during test execution. Increase these TTL values to a more stable duration, such
as 5 to 10 seconds, to prevent timing-dependent issues unless the test
specifically requires testing cache expiry behavior.

In lib/wanderer_kills/killmails/transformations.ex around lines 270 to 289, the
function enrich_with_ship_names/1 currently logs errors but always returns {:ok,
killmail}, which can cause downstream code to operate on incomplete data without
awareness. Modify the function to return {:error, reason} when enrichment fails,
or alternatively return {:ok, killmail, warnings} to inform callers of partial
failures, allowing them to handle these cases appropriately instead of silently
proceeding.

In lib/wanderer_kills/killmails/transformations.ex around lines 389 to 400, the
fallback_to_esi function currently maps all {:error, _reason} cases to a generic
:ship_name_not_found error, losing the original error details. Modify the
function to propagate the original error reason from the ESI client instead of
replacing it with a generic error, so that the diagnostics like rate-limit or
network errors are preserved for better observability.

In CLAUDE.md from lines 119 to 213, there are markdownlint violations due to
missing blank lines around headings and list blocks, causing MD022, MD032, and
MD031 errors. To fix this, run the command `markdownlint -f` on the file to
automatically insert the necessary blank lines around headings and lists,
ensuring proper spacing without changing the content.

In docs/API_AND_INTEGRATION_GUIDE.md at line 571, the file is missing a trailing
newline character at the end. Add a single newline character after the last line
to comply with markdown file formatting standards.

In lib/wanderer_kills/config.ex around lines 327 to 336, the get_group/1
function currently returns an empty map silently when the configuration type is
invalid. Add a debug or warning log message in the fallback clause of the case
statement to indicate that an unexpected configuration type was encountered,
including the invalid value for easier troubleshooting.

In .claude/settings.local.json around lines 30 to 38, the permission list
contains redundant and duplicate commands such as multiple specific mix test
commands that are already covered by more generic entries like
"Bash(MIX_ENV=test mix test)". Simplify the list by removing these duplicates
and replacing them with broader patterns like "Bash(MIX_ENV=test mix test*)" to
cover all test commands, ensuring the allow-list is concise and easier to
maintain.

In .claude/settings.local.json around lines 39 to 46, the current configuration
allows running interactive iex sessions and arbitrary mix run -e commands, which
poses a security risk by enabling broad code execution. Review whether these
commands are strictly necessary; if they are, restrict their usage to trusted
contributors or ephemeral CI environments only. Otherwise, remove or disable
these commands to prevent untrusted users from executing arbitrary Elixir code.