require 'pathname'
require 'fiber'

MalEnv = Struct.new('MalEnv', :map, :outer) do 
  def set(key, value)
    if key.is_a?(MalSym)
      key = key.val.to_sym
    end
    map[key] = value
  end
  def get(key)
    if key.is_a?(MalSym)
      # puts "Hell yeah #{key} inside #{map} & #{outer}?"
      key = key.val.to_sym
    end
    # puts "#{key}, #{key.class}, #{map}, #{map.has_key?(key)} "
    # map.each { |k, v| puts "key #{k} has type #{k.class}"}
    if map.has_key?(key)
      map[key]
    elsif outer != nil
      outer.get(key)
    else
      raise "Can't find symbol `#{key}`"
    end
  end
end

def new_global_env()
  env = MalEnv.new({
      :+   => MalFn.new(-> (args) { args[0] + args[1] }, 2, {name: "+"}),
      :-   => MalFn.new(-> (args) { args[0] - args[1] }, 2, {name: "-"}),
      :*   => MalFn.new(-> (args) { args[0] * args[1] }, 2, {name: "*"}),
      :/   => MalFn.new(-> (args) { args[0] / args[1] }, 2, {name: "/"}),
      :"=" => MalFn.new(-> (args) { args[0] == args[1] }, 2, {name: "="}),
      :<   => MalFn.new(-> (args) { args[0] < args[1] }, 2, {name: "<"}),
      :<=  => MalFn.new(-> (args) { args[0] <= args[1] }, 2, {name: "<="}),
      :>   => MalFn.new(-> (args) { args[0] > args[1] }, 2, {name: ">"}),
      :>=  => MalFn.new(-> (args) { args[0] >= args[1] }, 2, {name: ">="}),

      :"pr-str" => MalFn.new(-> (args) do
        args.reduce { |acc, ele| "#{acc} #{ele.inspect}" } 
      end, 0, {vararg: true, name: "pr-str"}),
      str:         MalFn.new(-> (args) { args.join(" ") }, 0, {vararg: true, name: "str"}),
      prn:         MalFn.new(-> (args) do
        puts args.reduce { |acc, ele| "#{acc} #{ele.inspect}" } 
        MalNil.new()
      end, 0, {vararg: true, name: "prn"}),
      println:     MalFn.new(-> (args) { puts args.join(" "); MalNil.new() }, 0, {vararg: true, name: "println"}),

      list:  MalFn.new(-> (args) { MalList.new(args) }, 0, {vararg: true, name: "list"}),
      list?: MalFn.new(-> (args) { args[0].is_a?(MalList)}, 1, {name: "list?"}),

      empty?: MalFn.new(-> (args) do 
        container = args[0]
        case container
        when MalList 
          container.list.empty?
        when MalVec
          container.vec.empty?
        when MalMap
          container._map.empty?
        else
          raise "Expecting a container got #{container.class}" 
        end
      end, 1, {name: "empty?"}),

      count: MalFn.new(-> (args) do
        container = args[0]
        case container
        when MalList 
          container.list.length
        when MalVec
          container.vec.length
        when MalMap
          container._map.length
        else
          raise "Expecting a container for `count` got #{container.class} of #{container}" 
        end
      end, 1, {name: "count"}),

      first: MalFn.new(-> (args) do
        container = args[0]
        case container
        when MalList 
          container.list[0] || MalNil
        when MalVec
          container.vec[0] || MalNil
        when MalMap
          container._map.to_a[0] || MalNil
        else
          raise "Expecting a container for `first` got #{container.class}" 
        end
      end, 1, {name: "first"}),

      rest: MalFn.new(-> (args) do
        container = args[0]
        case container
        when MalList 
          out = container.list[1..]
        when MalVec
          out = container.vec[1..]
        when MalMap
          out = container._map.to_a[1..]
        else
          raise "Expecting a container for `rest` got #{container.class}" 
        end
        if out == nil 
          MalList.new([])
        else 
          MalList.new(out)
        end
      end, 1, {name: "rest"}),

      nth: MalFn.new(-> (args) do
        container, pos = args
        case container
        when MalList 
          out = container.list[pos]
        when MalVec
          out = container.vec[pos]
        when MalMap
          out = container._map.to_a[pos]
        else
          raise "Expecting a container for `nth` got #{container.class}" 
        end
        out || MalNil.new()
      end, 2, {name: "nth"}),

      :"read-string" => MalFn.new(-> (args) do 
        str_fiber = Fiber.new do
          args[0].to_s
        end
        str_reader = reader(str_fiber)
        if str_reader.alive?
          begin 
            result = str_reader.resume
          rescue FiberError
            raise "Unexpecting EOF when trying to `read-string`"
          end
          begin 
            raise "Too much form to read: #{str_reader.resume}"
          rescue FiberError
            # expected
          end
          result
        end
      end, 1, {name: "read-string"}),

      slurp:  MalFn.new(-> (args) do 
        file_name = args[0]
        unless file_name.is_a?(MalString)
          raise "Expecting a string for `slurp`, got #{file_name}"
        end
        Pathname.new(file_name.to_s).read
      end, 1, {name: "slurp"}),

      atom: MalFn.new(-> (args) do 
        inner = args[0]
        MalAtom.new(inner)
      end, 1, {name: "atom"}),
      atom?: MalFn.new(-> (args) do 
        atom = args[0]
        atom.is_a?(MalAtom)
      end, 1, {name: "atom?"}),
      deref: MalFn.new(-> (args) do 
        atom = args[0]
        unless atom.is_a?(MalAtom)
          raise "Expecting an atom for `deref`, got #{atom}"
        end
        atom.inner
      end, 1, {name: "deref"}),
      reset!: MalFn.new(-> (args) do 
        atom, value = args
        unless atom.is_a?(MalAtom)
          raise "Expecting an atom for `deref`, got #{atom}"
        end
        atom.inner = value
      end, 2, {name: "reset!"}),

      cons: MalFn.new(-> (args) do 
        first, rest = args
        unless rest.is_a?(MalList) || rest.is_a?(MalVec) || rest.is_a?(MalNil)
          raise "Expecting list/vector/nil for 2nd argument in `cons`, got #{rest}"
        end
        case rest 
        when MalNil
          MalList.new([first])
        when MalVec
          rest.vec.prepend(first)
          MalList.new(rest.vec)
        when MalList
          rest.list.prepend(first)
          rest
        end
      end, 2, {name: "cons"}),

      concat: MalFn.new(-> (args) do 
        left, right = args
        unless left.is_a?(MalList) || left.is_a?(MalVec) || left.is_a?(MalNil)
          raise "Expecting list/vector/nil for 1st argument in `concat`, got #{left}"
        end
        unless right.is_a?(MalList) || right.is_a?(MalVec) || right.is_a?(MalNil)
          raise "Expecting list/vector/nil for 2nd argument in `concat`, got #{right}"
        end
        def to_list(val) 
          case val 
          when MalNil 
            []
          when MalVec
            val.vec
          when MalList
            val.list
          end
        end
        MalList.new(to_list(left) + to_list(right))
      end, 2, {name: "concat"}),

      vec: MalFn.new(-> (args) do 
        iter = args[0]
        unless iter.is_a?(MalList) || iter.is_a?(MalVec) || iter.is_a?(MalNil)
          raise "Expecting list/vector/nil for 1st argument in `vec`, got #{iter}"
        end
        case iter
        when MalNil
          MalVec.new([])
        when MalList
          MalVec.new(iter.list)
        when MalVec
          iter
        end
      end, 1, {name: "vec"}),

    }, nil)

  std_fiber = Fiber.new do  
    std = Pathname.new(__dir__) + "std.mal"
    std.read
  end
  std_reader = reader(std_fiber)
  while std_reader.alive?
    begin 
      eval(std_reader.resume, env)
    rescue FiberError
      # At any layer data is drained
      break
    end
  end

  env
end
