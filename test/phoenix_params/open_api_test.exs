defmodule PhoenixParams.OpenAPITest do
  use ExUnit.Case

  alias PhoenixParams.OpenAPI

  defmodule TestRequest do
    use PhoenixParams, error_view: nil

    param :name,
          type: String,
          required: true,
          source: :query,
          length: %{gte: 1, lt: 100}

    param :email,
          type: String,
          regex: ~r/[a-z_.]+@[a-z_.]+/

    param :age,
          type: Integer,
          required: true,
          numericality: %{gte: 18, lt: 100}

  end

  test "parameters/1" do
    assert OpenAPI.parameters(TestRequest) == [
      %{
        "in" => "path",
        "name" => "name",
        "required" => true,
        "description" => "TODO",
        "schema" => %{
          "type" => "string",
          "minLength" => 1,
          "maxLength" => 99
        }
      }
    ]
  end

  test "body_schema/1" do
    assert OpenAPI.body_schema(TestRequest) == %{
      "description" => "TODO",
      "example" => "TODO",
      "required" => ["age"],
      "title" => "TODO",
      "type" => "object",
      "properties" => %{
        "email" => %{
          "description" => "TODO",
          "type" => "string",
          "pattern" => "[a-z_.]+@[a-z_.]+"
        },
        "age" => %{
          "description" => "TODO",
          "type" => "integer",
          "minimum" => 18,
          "maximum" => 100,
          "exclusiveMinimum" => false,
          "exclusiveMaximum" => true
        }
      }
    }
  end

  test "response_schema/0" do
    assert OpenAPI.response_schema() == %{
      "required" => ["param", "message", "error_code"],
      "title" => "InvalidParams",
      "type" => "object",
      "description" => "Invalid params response",
      "properties" => %{
        "param" => %{
          "description" => "Param name",
          "type" => "string"
        },
        "message" => %{
          "description" => "Detailed error message",
          "type" => "string"
        },
        "error_code" => %{
          "description" => "Short error identifier",
          "enum" => ["INVALID", "MISSING"],
          "type" => "string"
        }
      }
    }
  end
end
