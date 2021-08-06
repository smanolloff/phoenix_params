# defmodule PhoenixParams.OpenAPI do
#   def parameters(request) do
#     typemap = Map.new(request.phoenix_params_meta.typedefs)
#     # 1. convert :auto to all types
#     for {pname, %{source: s} = pdef}, into: %{} <- request.paramdefs when s in [:path, :query] do
#       {to_string(pname), %{
#         "in" => to_string(s),
#         "name" => to_string(pname),
#         "required" => pdef.required,
#         "description" => "TODO",
#         "schema" => schema(pdef, typemap)
#       }}
#     end
#   end


#   #
#   # private
#   #

# # %{
# #   "type" => type(pdef.type),
# #   "minLength" => 1,
# #   "maxLength" => 99
# # }
#   def schema(pdef, typemap) do
#     type_part = type(req, pdef.type)
#     validation_part = validation(pdef.validator)
#     Map.merge(type_part, validation_part)
#   end

#   def type(Integer) do

#     case pdef.validator do
#       nil -> %{"type" => type(pdef.type)}

#   end
# end
