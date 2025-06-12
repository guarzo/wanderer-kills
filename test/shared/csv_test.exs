defmodule WandererKills.ShipTypes.ParserTest do
  use ExUnit.Case, async: true

  alias WandererKills.ShipTypes.Parser

  describe "read_file/3" do
    test "handles missing file" do
      parser = fn _row -> %{id: 1, name: "test"} end

      result = Parser.read_file("nonexistent.csv", parser)
      assert {:error, _reason} = result
    end

    test "handles empty file" do
      parser = fn _row -> %{id: 1, name: "test"} end
      file_path = "test/fixtures/empty.csv"
      File.mkdir_p!(Path.dirname(file_path))
      File.write!(file_path, "")

      result = Parser.read_file(file_path, parser)
      assert {:error, %WandererKills.Support.Error{type: :empty_file}} = result

      File.rm!(file_path)
    end

    test "handles invalid Parser" do
      parser = fn _row -> %{id: 1, name: "test"} end
      file_path = "test/fixtures/invalid.csv"
      File.mkdir_p!(Path.dirname(file_path))
      File.write!(file_path, "invalid\"csv,\"content\nunclosed\"quote")

      result = Parser.read_file(file_path, parser)
      assert {:error, %WandererKills.Support.Error{type: :parse_failure}} = result

      File.rm!(file_path)
    end

    test "parses valid Parser" do
      parser = fn row -> %{id: String.to_integer(row["id"]), name: row["name"]} end
      file_path = "test/fixtures/valid.csv"
      File.mkdir_p!(Path.dirname(file_path))
      File.write!(file_path, "id,name\n1,test1\n2,test2")

      result = Parser.read_file(file_path, parser)
      assert {:ok, {records, _metadata}} = result
      assert length(records) == 2
      assert records == [%{id: 1, name: "test1"}, %{id: 2, name: "test2"}]

      File.rm!(file_path)
    end
  end

  describe "parse_row/2" do
    test "creates map from headers and row data" do
      headers = ["id", "name", "value"]
      row = ["1", "test", "100"]

      result = Parser.parse_row(row, headers)
      assert result == %{"id" => "1", "name" => "test", "value" => "100"}
    end
  end

  describe "parse_integer/1" do
    test "parses valid integers" do
      assert {:ok, 123} = Parser.parse_integer("123")
      assert {:ok, 0} = Parser.parse_integer("0")
      assert {:ok, -45} = Parser.parse_integer("-45")
    end

    test "handles invalid integers" do
      assert {:error, %WandererKills.Support.Error{type: :invalid_integer}} =
               Parser.parse_integer("abc")

      assert {:error, %WandererKills.Support.Error{type: :invalid_integer}} =
               Parser.parse_integer("12.5")

      assert {:error, %WandererKills.Support.Error{type: :missing_value}} =
               Parser.parse_integer("")

      assert {:error, %WandererKills.Support.Error{type: :missing_value}} =
               Parser.parse_integer(nil)
    end
  end

  describe "parse_float/1" do
    test "parses valid floats" do
      assert {:ok, 123.45} = Parser.parse_float("123.45")
      assert {:ok, +0.0} = Parser.parse_float("0.0")
      assert {:ok, -12.34} = Parser.parse_float("-12.34")
    end

    test "handles invalid floats" do
      assert {:error, %WandererKills.Support.Error{type: :invalid_float}} =
               Parser.parse_float("abc")

      assert {:error, %WandererKills.Support.Error{type: :missing_value}} =
               Parser.parse_float("")

      assert {:error, %WandererKills.Support.Error{type: :missing_value}} =
               Parser.parse_float(nil)
    end
  end

  describe "parse_number_with_default/3" do
    test "parses valid floats" do
      assert 123.45 = Parser.parse_number_with_default("123.45", :float, 0.0)
      assert +0.0 = Parser.parse_number_with_default("0.0", :float, 0.0)
    end

    test "returns default for invalid floats" do
      assert +0.0 = Parser.parse_number_with_default("abc", :float, 0.0)
      assert 5.0 = Parser.parse_number_with_default("invalid", :float, 5.0)
    end
  end
end
