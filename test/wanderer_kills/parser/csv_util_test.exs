defmodule WandererKills.Parser.CsvUtilTest do
  use ExUnit.Case, async: true

  alias WandererKills.Parser.CsvUtil

  describe "read_rows/2" do
    test "handles missing file" do
      parser = fn _row -> %{id: 1, name: "test"} end

      result = CsvUtil.read_rows("nonexistent.csv", parser)
      assert {:error, _reason} = result
    end

    test "handles empty file" do
      parser = fn _row -> %{id: 1, name: "test"} end
      file_path = "test/fixtures/empty.csv"
      File.write!(file_path, "")

      result = CsvUtil.read_rows(file_path, parser)
      assert {:error, :empty_file} = result

      File.rm!(file_path)
    end

    test "handles invalid CSV" do
      parser = fn _row -> %{id: 1, name: "test"} end
      file_path = "test/fixtures/invalid.csv"
      File.write!(file_path, "invalid\"csv,\"content\nunclosed\"quote")

      result = CsvUtil.read_rows(file_path, parser)
      assert {:error, :parse_error} = result

      File.rm!(file_path)
    end

    test "parses valid CSV" do
      parser = fn row -> %{id: String.to_integer(row["id"]), name: row["name"]} end
      file_path = "test/fixtures/valid.csv"
      File.write!(file_path, "id,name\n1,test1\n2,test2")

      result = CsvUtil.read_rows(file_path, parser)
      assert {:ok, records} = result
      assert length(records) == 2
      assert records == [%{id: 1, name: "test1"}, %{id: 2, name: "test2"}]

      File.rm!(file_path)
    end
  end

  describe "parse_row/2" do
    test "creates map from headers and row data" do
      headers = ["id", "name", "value"]
      row = ["1", "test", "100"]

      result = CsvUtil.parse_row(row, headers)
      assert result == %{"id" => "1", "name" => "test", "value" => "100"}
    end
  end

  describe "parse_integer/1" do
    test "parses valid integers" do
      assert {:ok, 123} = CsvUtil.parse_integer("123")
      assert {:ok, 0} = CsvUtil.parse_integer("0")
      assert {:ok, -45} = CsvUtil.parse_integer("-45")
    end

    test "handles invalid integers" do
      assert {:error, :invalid_integer} = CsvUtil.parse_integer("abc")
      assert {:error, :invalid_integer} = CsvUtil.parse_integer("12.5")
      assert {:error, :invalid_integer} = CsvUtil.parse_integer("")
      assert {:error, :invalid_integer} = CsvUtil.parse_integer(nil)
    end
  end

  describe "parse_float/1" do
    test "parses valid floats" do
      assert {:ok, 123.45} = CsvUtil.parse_float("123.45")
      assert {:ok, +0.0} = CsvUtil.parse_float("0.0")
      assert {:ok, -12.34} = CsvUtil.parse_float("-12.34")
    end

    test "handles invalid floats" do
      assert {:error, :invalid_float} = CsvUtil.parse_float("abc")
      assert {:error, :invalid_float} = CsvUtil.parse_float("")
      assert {:error, :invalid_float} = CsvUtil.parse_float(nil)
    end
  end

  describe "parse_float_with_default/2" do
    test "parses valid floats" do
      assert 123.45 = CsvUtil.parse_float_with_default("123.45")
      assert +0.0 = CsvUtil.parse_float_with_default("0.0")
    end

    test "returns default for invalid floats" do
      assert +0.0 = CsvUtil.parse_float_with_default("abc")
      assert 5.0 = CsvUtil.parse_float_with_default("invalid", 5.0)
    end
  end
end
