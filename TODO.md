# TODO: Remaining Refactoring Tasks

This document outlines the remaining refactoring tasks from the PR feedback, organized by priority and complexity. All Quick Wins and Medium Effort items have been completed.

## Completed Summary

✅ **High Priority (Completed)**
- Domain structs (#6) - Struct-based architecture with type safety
- WebSocket architecture (#9) - DynamicSupervisor + Registry pattern
- Configuration management (#10) - Standard Application.compile_env/3
- Web separation (#11) - Conditional web components with headless support

✅ **Medium Priority (Completed)**
- Benchmark organization (#12, #26) - Moved to /bench directory
- Test helper organization (#13) - Centralized Mox & helper modules
- Type specifications (#14) - 80% @spec coverage
- Placeholder test cleanup (#18) - All meaningful tests
- Performance test organization (#22) - Tagged and excluded by default

✅ **Quick Wins (Completed)**
- CI/CD improvements (#15, #16, #17) - Dialyzer, coverage, JSON safety

## Remaining Tasks

### 🔧 Low Priority Maintenance

#### 1. Fix Mox Dependencies Issue (#17)
**Status**: Pending (Low Priority)
**Effort**: 1-2 hours
**Issue**: Mox dependency handling in test helper needs cleanup

**Implementation Plan**:
```bash
# Current issue in test_helper.exs line 5
Code.ensure_loaded?(Mox) || raise "Mox module not available..."
```

**Steps**:
1. Update test_helper.exs to handle missing Mox gracefully
2. Add conditional Mox loading for headless environments
3. Update test configuration to be more resilient
4. Test with and without Mox dependency

**Code Changes**:
```elixir
# test/test_helper.exs
if Code.ensure_loaded?(Mox) do
  # Define mocks only if Mox is available
  Mox.defmock(...)
else
  # Provide alternative or skip mock-dependent tests
  IO.puts("Warning: Mox not available, some tests may be skipped")
end
```

---

### 🏗️ Large Refactors (High Impact)

#### 2. Test Infrastructure Overhaul (#19, #20, #21)
**Status**: Not Started
**Effort**: 1-2 weeks
**Impact**: Major improvement to test reliability and speed

**Sub-tasks**:

##### 2a. Parallel Test Execution (#19)
**Current**: `ExUnit.configure(parallel: false)` in test_helper.exs
**Goal**: Enable parallel test execution for faster CI

**Implementation Plan**:
1. **Phase 1: ETS Table Isolation**
   ```elixir
   # Give ETS tables per-test unique names
   def create_test_table(base_name) do
     unique_name = :"#{base_name}_#{System.unique_integer([:positive])}"
     :ets.new(unique_name, [:set, :public, :named_table])
     unique_name
   end
   ```

2. **Phase 2: Mox Local Mode**
   ```elixir
   # test/test_helper.exs
   ExUnit.configure(
     parallel: true,
     max_cases: System.schedulers_online() * 2
   )
   
   # In test modules
   setup :verify_on_exit!
   setup do
     Mox.set_mox_private()
     :ok
   end
   ```

3. **Phase 3: Process Isolation**
   - Start GenServers with unique names per test
   - Use test-specific PubSub topics
   - Clean up processes in on_exit callbacks

**Files to modify**:
- `test/test_helper.exs` - Enable parallel execution
- `test/support/shared_contexts.ex` - Add unique naming utilities
- All test files - Update to use unique process names

##### 2b. Global Mock Strategy Replacement (#20)
**Current**: Global Mox stubs in test_helper.exs
**Goal**: Explicit expect/4 calls for better test isolation

**Implementation Plan**:
1. **Remove Global Stubs**
   ```elixir
   # Remove from test_helper.exs
   # Mox.stub_with(HttpClientMock, ActualClient)
   ```

2. **Add Explicit Expectations**
   ```elixir
   # In each test
   setup do
     HttpClientMock
     |> expect(:get, fn _url, _opts -> 
       {:ok, %{status: 200, body: %{}}} 
     end)
     
     :ok
   end
   ```

3. **Create Test Factories**
   ```elixir
   defmodule WandererKills.TestFactory do
     def mock_http_success(client_mock, response \\ %{}) do
       client_mock
       |> expect(:get, fn _url, _opts -> {:ok, response} end)
     end
   end
   ```

##### 2c. Unified Test Case (#21)
**Goal**: Consistent test setup across all test files

**Implementation Plan**:
1. **Enhanced DataCase**
   ```elixir
   defmodule WandererKills.DataCase do
     use ExUnit.CaseTemplate
     
     using do
       quote do
         import WandererKills.TestHelpers
         import WandererKills.TestFactory
         import Mox
         
         setup :verify_on_exit!
         setup :setup_unique_environment
       end
     end
     
     def setup_unique_environment(_context) do
       unique_id = System.unique_integer([:positive])
       %{test_id: unique_id}
     end
   end
   ```

2. **Process Management**
   ```elixir
   def start_supervised_unique(module, args \\ []) do
     unique_name = :"#{module}_#{System.unique_integer([:positive])}"
     start_supervised({module, Keyword.put(args, :name, unique_name)})
   end
   ```

**Estimated Timeline**: 
- Phase 1: 3-4 days
- Phase 2: 2-3 days  
- Phase 3: 3-4 days
- Testing & refinement: 2-3 days

---

#### 3. Property-Based Testing (#23)
**Status**: Not Started
**Effort**: 1 week
**Impact**: Better edge case coverage

**Implementation Plan**:

##### Phase 1: Setup StreamData
```bash
# Add to mix.exs
{:stream_data, "~> 0.6", only: [:test, :dev]}
```

##### Phase 2: Killmail Property Tests
```elixir
defmodule WandererKills.Domain.KillmailPropertyTest do
  use ExUnit.Case
  use ExUnitProperties
  
  property "killmail parsing is consistent" do
    check all killmail_data <- killmail_generator() do
      case WandererKills.Domain.Killmail.new(killmail_data) do
        {:ok, killmail} ->
          # Verify round-trip conversion
          map_data = WandererKills.Domain.Killmail.to_map(killmail)
          assert {:ok, _} = WandererKills.Domain.Killmail.new(map_data)
          
        {:error, _} ->
          # Verify error is consistent
          assert {:error, _} = WandererKills.Domain.Killmail.new(killmail_data)
      end
    end
  end
  
  defp killmail_generator do
    gen all killmail_id <- positive_integer(),
            system_id <- integer(30_000_000..31_000_000),
            kill_time <- datetime_string(),
            victim <- victim_generator(),
            attackers <- list_of(attacker_generator(), min_length: 1) do
      %{
        "killmail_id" => killmail_id,
        "solar_system_id" => system_id,
        "killmail_time" => kill_time,
        "victim" => victim,
        "attackers" => attackers
      }
    end
  end
end
```

##### Phase 3: Cache Property Tests
```elixir
property "cache operations maintain consistency" do
  check all operations <- list_of(cache_operation_generator()) do
    # Apply operations and verify cache consistency
    Enum.reduce(operations, %{}, fn op, acc ->
      apply_cache_operation(op, acc)
    end)
  end
end
```

**Files to create**:
- `test/property/killmail_property_test.exs`
- `test/property/cache_property_test.exs`
- `test/support/generators.ex`

---

### 🚀 Optional Enhancements

#### 4. Coverage Goals (#25)
**Goal**: Raise minimum coverage to 85%
**Current**: Coverage tracking without enforcement

**Implementation Plan**:
1. **Analyze Current Coverage**
   ```bash
   mix test.coverage
   # Review coverage.html output
   ```

2. **Add Coverage Enforcement**
   ```elixir
   # mix.exs
   def project do
     [
       test_coverage: [
         tool: ExCoveralls,
         minimum_coverage: 85,
         refuse_uncovered_code: true
       ]
     ]
   end
   ```

3. **Focus Areas** (likely low coverage):
   - Error handling paths
   - Edge cases in data processing
   - WebSocket disconnection scenarios
   - Rate limiting edge cases

#### 5. Log Assertion Testing (#27)
**Goal**: Verify error logging in failure scenarios

**Implementation Plan**:
```elixir
test "logs error on failure" do
  assert capture_log(fn ->
    # Operation that should log an error
    WandererKills.SomeModule.failing_operation()
  end) =~ "Expected error message"
end
```

---

## Implementation Priority

### Phase 1: Infrastructure (Weeks 1-2)
1. ✅ Fix Mox dependencies issue (#17) - Quick win
2. 🏗️ Test infrastructure overhaul (#19, #20, #21) - Foundation

### Phase 2: Quality (Week 3)
3. 🧪 Property-based testing (#23) - Enhanced coverage

### Phase 3: Polish (Week 4)
4. 📊 Coverage goals (#25) - Metrics
5. 🔍 Log assertion testing (#27) - Observability

## Success Criteria

### Test Infrastructure Overhaul
- [ ] Tests run in parallel without conflicts
- [ ] CI test execution time reduced by 50%+
- [ ] No global mock state dependencies
- [ ] All tests use explicit expectations
- [ ] Unified test case provides consistent environment

### Property-Based Testing
- [ ] Killmail parsing property tests passing
- [ ] Cache operation property tests implemented
- [ ] At least 5 core modules have property tests
- [ ] Property tests catch edge cases not covered by example-based tests

### Coverage & Quality
- [ ] Test coverage >= 85%
- [ ] All error paths have log assertion tests
- [ ] Dialyzer passes with zero warnings
- [ ] All tests are deterministic and reliable

## Notes

- The test infrastructure overhaul is the most complex task requiring careful coordination
- Property-based testing will likely reveal bugs in edge cases - budget time for fixes
- Some tasks may uncover additional issues requiring follow-up work
- Consider tackling these in order to build on previous improvements

---

*Last updated: 2024-06-14*
*All completed items marked with ✅ represent substantial architectural improvements*