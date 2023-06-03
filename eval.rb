def wrap_inspect(ast)
  case ast
  when MalList
    "'#{ast.inspect}"
  else
    ast.inspect
  end
end

def quasiquote(ast, env)
  case ast 
  when MalList
    l = ast.list
    if l[0] == MalSym.new("unquote")
      raise "Wrong number of args for `unquote`!" unless l.length == 2
      return eval(l[1], env)
    else 
      output = l.reduce([]) do |acc, exp| 
        if exp.is_a?(MalList) && exp.list[0] == MalSym.new("splice-unquote")
          raise "Wrong number of args for `splice-unquote`!" unless exp.list.length == 2
          list_to_splice = eval(exp.list[1], env)
          raise "splicing a non-list #{list_to_splice} in `splice-unquote`!" unless list_to_splice.is_a?(MalList)
          acc += list_to_splice.list
        else
          acc.push(quasiquote(exp, env))
        end
      end
      return MalList.new(output)
    end
  when MalVec
    v = ast.vec
    MalVec.new(v.map { |e| quasiquote(e, env) })
  when MalMap
    m = ast._map
    MalMap.new(m.map { |k, v| [k, quasiquote(v, env)] }.to_h)
  else 
    ast
  end
end

def eval(ast, env)
  loop do 
    case ast
    when MalList
      case ast.list
      in op, *rest 
        case op
        when MalSym.new("def!")
          raise "Wrong number of args for `def!`!" unless rest.length == 2
          name, val = rest
          raise "First param of `def!` must be a symbol!" unless name.class == MalSym
          val = eval(val, env)
          env.set(name, val)
          return val
        when MalSym.new("defmacro!")
          raise "Wrong number of args for `defmacro!`!" unless rest.length >= 3
          name, bindings, *exp = rest
          raise "First param of `defmacro!` must be a symbol!" unless name.class == MalSym
          lambda_src = MalList.new([MalSym.new("fn"), bindings] + exp)

          fn = eval(lambda_src, env)
          fn.fn.is_macro = true
          env.set(name, fn)

          return fn
        when MalSym.new("let")
          raise "Wrong number of args for `let`" unless rest.length == 2
          bindings, exp = rest
          raise "First param of `let` must be a vector!" unless bindings.class == MalVec
          raise 'number of keys and values unmatched in let binding!' unless bindings.vec.length % 2 == 0
          bindings = bindings.vec.each_slice(2)
          unless bindings.all? { |k, v| k.is_a?(MalSym) }
            raise "Binding names have to be symbols!"
          end
          # unless bindings.class == MalVec

          bindings = (bindings.map { |k, v| [k.val.to_sym, eval(v, env)] }.to_h)
          ast, env = exp, MalEnv.new(bindings, env)
          next
        when MalSym.new("do")
          raise "Wrong number of args for `do`" unless rest.length >= 1
          rest[..-2].reduce(nil) { |acc, exp| eval(exp, env) }
          ast = rest[-1] # env is already updated
          next
        when MalSym.new("if")
          raise "Wrong number of args for `if`" unless rest.length == 3
          test, then_clause, else_clause = rest
          test = eval(test, env)
          if test != false && test != MalNil.new() 
            ast = then_clause
          else 
            ast = else_clause
          end
          next
        when MalSym.new("fn")
          raise "Wrong number of args for `fn`" unless rest.length >= 2
          bindings, *exp = rest
          if bindings.class != MalVec ||
             bindings.vec.any? { |bind| bind.class != MalSym }
            raise "First argument of `fn` has to be a proper binding list"
          end
          exp = MalList.new(exp.prepend(MalSym.new("do")))
          bindings = bindings.vec
          vararg = false
          if bindings.length >= 2 && bindings[-2] == MalSym.new("&")
            vararg = true
            bindings.delete_at(-2)
          end
          bindings = bindings.map { |s| s.val.to_sym }
          ret = 
            MalFn.new(
              MalLambda.new(bindings, exp, env, false), 
              bindings.length, { vararg: vararg })
          return ret
        when MalSym.new("eval")
          raise "Wrong number of args for `eval`" unless rest.length == 1
          ast = eval(rest[0], env)
          next
        when MalSym.new("quote")
          raise "Wrong number of args for `quote`" unless rest.length == 1
          return rest[0]
        when MalSym.new("quasiquote")
          raise "Wrong number of args for `quasiquote`" unless rest.length == 1
          return quasiquote(rest[0], env)
        when MalSym.new("macroexpand")
          raise "Wrong number of args for `macroexpand`" unless rest.length == 1

          to_expand = eval(rest[0], env)
          unless to_expand.is_a?(MalList) && to_expand.list[0].is_a?(MalSym)
            raise "argument for macroexpand must be a macro call" 
          end
          op, rest = to_expand.list[0], to_expand.list[1..]
          fn = eval(op, env).fn
          unless fn.is_a?(MalLambda) && fn.is_macro
            raise "expecting macro got #{fn}" 
          end

          # ast = expand_macro(fn.exp, MalEnv.new(fn.bindings.zip(rest).to_h, fn.outer))
          ast, env = fn.exp, MalEnv.new(fn.bindings.zip(rest).to_h, fn.outer)
          next
          # For the sake of TCO I reimplement macroexpand here.
        else
          op = eval(op, env)
          fn = op.fn
          vararg = op.vararg
          if fn.class == MalLambda
            args = rest
            if !fn.is_macro
              args = args.map { |child| eval(child, env) }
            end
            if vararg 
              if args.length == fn.bindings.length - 1
                args.append(MalList.new([]))
              else
                args_rest, vararg = args.take(fn.bindings.length - 1), args.drop(fn.bindings.length - 1)
                args = args_rest.append(MalList.new(vararg))
              end
            end
            if fn.is_macro
              ast = eval(fn.exp, MalEnv.new(fn.bindings.zip(args).to_h, fn.outer))
            else 
              ast, env = fn.exp, MalEnv.new(fn.bindings.zip(args).to_h, fn.outer)
            end
            next
          else
            args = rest.map { |child| eval(child, env) }
            raise "#{fn} is not callable" unless fn.respond_to? :call
            return fn.call(args)
          end
        end
      else # Empty List
        return ast
      end
    when MalVec
      return MalVec.new(ast.vec.map { |child| eval(child, env) })
    when MalMap
      return MalMap.new(ast._map.map { |k, v| [k, eval(v, env)] }.to_h)
    when MalSym
      return env.get(ast) # This will throw an error if not found
    else #Atom
      return ast
    end
  end
end
