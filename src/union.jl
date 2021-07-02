#=
Implementation of tagged unions for MetaModelica.jl
They can be used in that way with match.jl
=#

#= Example:
#@Uniontype number begin
#    @Record real begin
#    r::Real
#    end
#    @Record img begin
#    r::Real
#    i::Real
#    end
#end
# Or for short:
#@Uniontype number begin
#    @Record real r::Real
#    @Record img r::Real i::Real
#end
# This is syntactic sugar for:
#  abstract type number end
#  struct real <: number
#   r
#  end
#  struct img <: number
#   r
#   i
#  end
=#

#=
TODO: Sometimes when people use type aliasing @Uniontype will not know about the specific type during compilation time
=#
module UniontypeDef

include("metaModelicaTypes.jl")
import .MetaModelicaTypes
using MacroTools

function makeRecord(recordExpr::Expr)
  local arr = []
  local sourceInfo = nothing
  for i in recordExpr.args
    if typeof(i) == Expr
      push!(arr, (i, sourceInfo))
    elseif typeof(i) <: LineNumberNode
      sourceInfo = i
    end
  end
  return [(el[1].args[3], el[1].args[4], el[2]) for el in arr]
end

function makeTuple(name, fields)
  return quote
    ($name, $fields)
  end
end

function isLineNumberNode(a, lines::LineNumberNode)
  if typeof(a) <: LineNumberNode
    a.file == Symbol(@__FILE__)
  else
    false
  end
end

function replaceLineNum(a::Expr, lines::LineNumberNode)
  replace!(arg -> isLineNumberNode(arg, lines) ? lines : arg, a.args)
  for n in a.args
    replaceLineNum(n, lines)
  end
end

function replaceLineNum(a::Any, lines::LineNumberNode) end

function makeUniontypes(name, records, lineNode::LineNumberNode)
  recordsArray1 = Array.(records)
  recordsArray2 = recordsArray1[1]
  constructedRecords = []
  for r in recordsArray2
    local block = r[2] #= Get the block. That is r[2]=#
    blckExprs = block.args
    varToDecl = Dict()
    local i::Int = 0
    local exprCounter::Int = 1
    for expr in blckExprs
      if typeof(expr) === LineNumberNode #= Ignore comment lines =#
        continue
      end
      #= Check if we have a uniontype type declaration. =#
      if (@capture(expr, T_::TYPE_))
        parametricType::Symbol = Symbol("T", i)
        varToDecl[T] = [parametricType, TYPE]
        i += 1
        newExpr = expr
        newExpr.args[2] = parametricType
      end
      exprCounter += 1
    end
    local structName = r[1]
    parametricTypes::Vector{Expr} = [ :($(varToDecl[i][1]) <: $(varToDecl[i][2])) for i in keys(varToDecl)]
    recordNode = quote
      struct $(structName){$(parametricTypes...)} <: $name
        $(r[2])
      end
    end
    replaceLineNum(recordNode, isa(r[3], Nothing) ? lineNode : r[3])
    push!(constructedRecords, recordNode)
  end
  #= Construct the Union =#
  res = quote
    abstract type $name end
    $(constructedRecords...)
  end
  # Make debugging and profiling easier by pretending the record was
  # allocated in the source file where the macro was invoked
  replaceLineNum(res, lineNode)
  return res
end

#= Creates a uniontype consisting of 0...N records =#
macro Uniontype(name, records...)
  recordCollection = [makeRecord(r) for r in records]
  esc(makeUniontypes(name, recordCollection, __source__))
end

#= Creates a record belonging to a Uniontype =#
macro Record(name, fields...)
  makeTuple(name, fields)
end

#= It is "possible" to manipulate the Julia ast during compilation time so that all declaration of a uniontype creates a module-top-level abstract type definition. I leave that as a exercise to the reader of this comment :D =#
macro UniontypeDecl(uDecl)
  esc(quote
        abstract type $uDecl end
      end)
end

export @Uniontype, @Record, @UniontypeDecl

end
