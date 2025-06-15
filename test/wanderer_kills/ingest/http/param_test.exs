defmodule WandererKills.Ingest.Http.ParamTest do
  use ExUnit.Case, async: true
  doctest WandererKills.Ingest.Http.Param

  alias WandererKills.Ingest.Http.Param

  describe "encode/2" do
    test "encodes basic parameters" do
      params = [page: 1, limit: 50, active: true]
      result = Param.encode(params)

      assert result == "page=1&limit=50&active=true"
    end

    test "filters nil values by default" do
      params = [page: 1, limit: nil, active: true]
      result = Param.encode(params)

      assert result == "page=1&active=true"
    end

    test "keeps nil values when filter_nils is false" do
      params = [page: 1, limit: nil]
      result = Param.encode(params, filter_nils: false)

      assert result == "page=1&limit="
    end

    test "converts boolean and integer values to strings" do
      params = [page: 1, active: true, disabled: false]
      result = Param.encode(params)

      assert result == "page=1&active=true&disabled=false"
    end

    test "skips string conversion when string_convert is false" do
      params = [page: 1, active: true]
      result = Param.encode(params, string_convert: false)

      # Note: URI.encode_query handles the conversion anyway
      assert result == "page=1&active=true"
    end

    test "transforms snake_case keys to camelCase" do
      params = [start_time: "2023-01-01", end_time: "2023-01-02", page_number: 1]
      result = Param.encode(params, key_transform: :snake_to_camel)

      assert result == "startTime=2023-01-01&endTime=2023-01-02&pageNumber=1"
    end

    test "applies custom validator" do
      params = [page: 1, limit: 250, valid: 10]
      validator = fn
        :limit, v -> v <= 200
        _, _ -> true
      end

      result = Param.encode(params, validator: validator)

      assert result == "page=1&valid=10"
    end

    test "handles empty parameters" do
      assert Param.encode([]) == ""
      assert Param.encode(%{}) == ""
    end

    test "handles map input" do
      params = %{page: 1, limit: 50}
      result = Param.encode(params)

      assert result == "page=1&limit=50"
    end
  end

  describe "process_params/2" do
    test "returns processed keyword list" do
      params = [start_time: "2023-01-01", page: 1, limit: nil]
      result = Param.process_params(params, key_transform: :snake_to_camel)

      assert result == [startTime: "2023-01-01", page: "1"]
    end
  end

  describe "encode_zkb_params/1" do
    test "adds default no_items parameter" do
      result = Param.encode_zkb_params([])

      assert result == "no_items=true"
    end

    test "validates and converts ZKB parameters" do
      params = [
        page: 1,
        limit: 50,
        start_time: "2023-01-01T00:00:00Z",
        past_seconds: 3600
      ]

      result = Param.encode_zkb_params(params)

      # Should include default and valid params with camelCase conversion
      assert String.contains?(result, "no_items=true")
      assert String.contains?(result, "page=1")
      assert String.contains?(result, "limit=50")
      assert String.contains?(result, "startTime=2023-01-01T00:00:00Z")
      assert String.contains?(result, "pastSeconds=3600")
    end

    test "rejects invalid ZKB parameters" do
      params = [
        page: 0,        # Invalid: must be > 0
        limit: 300,     # Invalid: must be <= 200
        invalid_param: "test"  # Invalid: unknown parameter
      ]

      result = Param.encode_zkb_params(params)

      # Should only contain default parameter
      assert result == "no_items=true"
    end

    test "validates page parameter" do
      # Valid page
      result = Param.encode_zkb_params([page: 5])
      assert String.contains?(result, "page=5")

      # Invalid page (zero)
      result = Param.encode_zkb_params([page: 0])
      refute String.contains?(result, "page=")

      # Invalid page (negative)
      result = Param.encode_zkb_params([page: -1])
      refute String.contains?(result, "page=")
    end

    test "validates limit parameter" do
      # Valid limit
      result = Param.encode_zkb_params([limit: 100])
      assert String.contains?(result, "limit=100")

      # Valid limit (max)
      result = Param.encode_zkb_params([limit: 200])
      assert String.contains?(result, "limit=200")

      # Invalid limit (too high)
      result = Param.encode_zkb_params([limit: 300])
      refute String.contains?(result, "limit=")

      # Invalid limit (zero)
      result = Param.encode_zkb_params([limit: 0])
      refute String.contains?(result, "limit=")
    end
  end

  describe "encode_esi_params/1" do
    test "encodes ESI parameters with standard filtering" do
      params = [character_id: 123, include_fittings: true, invalid: nil]
      result = Param.encode_esi_params(params)

      assert result == "character_id=123&include_fittings=true"
    end
  end

  describe "encode_redisq_params/1" do
    test "encodes RedisQ parameters minimally" do
      params = [queueID: "test_queue", ttw: 1]
      result = Param.encode_redisq_params(params)

      assert result == "queueID=test_queue&ttw=1"
    end
  end

  describe "snake_to_camel conversion" do
    test "converts single word" do
      params = [page: 1]
      result = Param.process_params(params, key_transform: :snake_to_camel)

      assert result == [page: "1"]
    end

    test "converts multi-word snake_case" do
      params = [start_time: "test", end_time_utc: "test"]
      result = Param.process_params(params, key_transform: :snake_to_camel)

      assert result == [startTime: "test", endTimeUtc: "test"]
    end

    test "handles string keys" do
      params = [{"start_time", "test"}, {"end_time", "test"}]
      result = Param.process_params(params, key_transform: :snake_to_camel)

      # Should convert to atoms after transformation
      assert result == [startTime: "test", endTime: "test"]
    end
  end
end