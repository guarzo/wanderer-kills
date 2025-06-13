defmodule IndexTestPatterns do
  @moduledoc """
  Parameterized test patterns for subscription indexes.
  
  Provides reusable test patterns that can be applied to any subscription
  index implementation, eliminating duplication between character and system
  index tests while ensuring comprehensive coverage.
  
  ## Usage
  
      defmodule MyEntityIndexTest do
        use ExUnit.Case, async: false
        use IndexTestPatterns, 
          index_module: MyEntityIndex,
          health_module: MyEntityHealth,
          test_entities: [123, 456, 789]
      end
  
  This will automatically generate all standard test cases for the specified
  index and health modules using the provided test entities.
  """
  
  defmacro __using__(opts) do
    index_module = Keyword.fetch!(opts, :index_module)
    health_module = Keyword.fetch!(opts, :health_module) 
    test_entities = Keyword.get(opts, :test_entities, [123, 456, 789])
    
    quote do
      import IndexTestHelpers
      
      setup do
        setup_index(unquote(index_module), unquote(test_entities))
      end
      
      describe "basic operations" do
        test "add subscription and find entities", %{index_module: index_module, test_entities: test_entities} do
          test_basic_operations(index_module, test_entities)
        end
        
        test "handles edge cases properly", %{index_module: index_module, test_entities: test_entities} do
          test_edge_cases(index_module, test_entities)
        end
      end
      
      describe "statistics and metrics" do
        test "tracks statistics accurately", %{index_module: index_module, test_entities: test_entities} do
          test_statistics(index_module, test_entities)
        end
      end
      
      describe "performance characteristics" do
        test "performs lookups efficiently", %{index_module: index_module, test_entities: test_entities} do
          test_performance(index_module, test_entities)
        end
        
        test "handles concurrent access", %{index_module: index_module, test_entities: test_entities} do
          test_concurrency(index_module, test_entities)
        end
      end
      
      describe "health check integration" do
        test "integrates with health monitoring", %{index_module: index_module, test_entities: test_entities} do
          test_health_integration(unquote(health_module), index_module, test_entities)
        end
      end
      
      describe "comprehensive test suite" do
        test "passes all test patterns", %{index_module: index_module, test_entities: test_entities} do
          run_comprehensive_tests(index_module, unquote(health_module), test_entities)
        end
      end
    end
  end
end