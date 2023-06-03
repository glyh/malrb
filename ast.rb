MalNil = Struct.new('MalNil') do
  def to_s() inspect end
  def inspect()
    'nil'
  end
end

MalString = Struct.new('MalString', :val) do
  def to_s()
    val
  end
  def inspect()
    val.dump
  end
end

MalSym = Struct.new('MalSym', :val) do 
  def to_s() inspect end
  def inspect() 
    val
  end
end

MalKeyWord = Struct.new('MalKeyWord', :val) do
  def to_s() inspect end
  def inspect()
    ":#{val}"
  end
end

MalList = Struct.new('MalList', :list) do 
  def to_s() inspect end
  def inspect()
    result = list
      .map { |e| e.inspect }
      .join(" ")
    "(#{result})"
  end
end

MalVec = Struct.new('MalVec', :vec) do 
  def to_s() inspect end
  def inspect()
    result = vec
      .map { |e| e.inspect }
      .join(" ")
    "[#{result}]"
  end
end

MalMap = Struct.new('MalMap', :_map) do 
  def to_s() inspect end
  def inspect()
    result = _map
      .map { |k, v| "#{k.inspect} #{v.inspect}" }
      .join(" ")
    "{#{result}}"
  end
end

MalLambda = Struct.new('MalLambda', :bindings, :exp, :outer, :is_macro)

class MalFn
  attr_reader :fn, :arity, :vararg, :name
  def initialize(fn, arity, options)
    @fn = fn 
    @arity = arity
    @vararg = options.fetch(:vararg, false)
    @name = options.fetch(:name, nil)
  end
  def to_s() inspect() end
  def inspect()
    if @name != nil
      @name
    elsif @fn.class == Proc 
      "#<builtin>"
    else
      if @fn.is_macro
       "#<macro>"
      else
       "#<lambda>"
      end
    end
  end
end

MalAtom = Struct.new('MalAtom', :inner)
