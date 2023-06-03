# Require a fiber that keeps generating string
def tokenize(input)
  Fiber.new do 
    loop do
      input_str = input.resume
      input_str.scan(/~@|[\[\]{}()'`~^@]|"(?:\\.|[^\\"])*"?|;.*|[^\s\[\]{}('"`,;)]+/) do |token|
        if token[0] != ';'
          Fiber.yield(token)
        end
      end
    end
  end
end

$parenthesis = Struct.new('Parenthesis')
$bracket = Struct.new('Bracket')
$moustache = Struct.new('Moustache')

$readmacro_deref = Struct.new('Deref')
$readmacro_quote = Struct.new('Quote')
$readmacro_quasiquote = Struct.new('Quasiquote')
$readmacro_unquote = Struct.new('Unquote')
$readmacro_spliceunquote = Struct.new('Spliceunquote')


def is_marker?(stack_elem)
  [$parenthesis, $bracket, $moustache].include?(stack_elem)
end

 def is_readmacro?(stack_elem) 
  [
    $readmacro_deref, 
    $readmacro_quote, $readmacro_quasiquote, $readmacro_unquote, $readmacro_spliceunquote
  ].include?(stack_elem)
 end

def is_special?(stack_elem)
  is_marker?(stack_elem) || is_readmacro?(stack_elem)
end

# Require a fiber from tokenize
def parse(tokens)
  Fiber.new do 
    stack, unbalance, result = [], 0, nil
    loop do 
      token = tokens.resume
      case token
      # Normal tokens
      when ')', ']', '}' # Emit a container
        record, top = nil, nil
        case token 
        when ')'
          record, top = MalList, $parenthesis
        when ']'
          record, top = MalVec, $bracket
        when '}'
          record, top = MalMap, $moustache
        end

        container = []
        until stack.empty? || stack[-1] == top
          current = stack.pop()
          raise "Unexpected #{top} matching against #{current}" unless !is_marker?(current)
          container.prepend(current)
        end
        raise "too many #{top}s!" unless !stack.empty?
        stack.pop()
        if record == MalMap
          raise 'number of keys and values unmatched in map!' unless container.length % 2 == 0
          container = (container.each_slice(2).to_h)
        end
        unbalance -= 1
        result = record.new(container)
      when '('
        unbalance += 1
        result = $parenthesis
      when '['
        unbalance += 1
        result = $bracket
      when '{'
        unbalance += 1
        result = $moustache
      when 'nil'
        result = MalNil.new()
      when 'true'
        result = true
      when 'false' 
        result = false
      when '@'
        result = $readmacro_deref
      when "'"
        result = $readmacro_quote
      when '`'
        result = $readmacro_quasiquote
      when '~'
        result = $readmacro_unquote
      when '~@'
        result = $readmacro_spliceunquote
      when /^"/
        result = MalString.new(token.undump)
      when /^:/
        result = MalKeyWord.new(token[1..-1])
      else # Numerics or Symbol
        result = (Integer(token) rescue Float(token) rescue MalSym.new(token))
      end
      # Expand reader macros
      while !stack.empty? && !is_special?(result) && is_readmacro?(stack[-1])
        if stack[-1] == $readmacro_deref
          result = MalList.new([MalSym.new("deref"), result])
        elsif stack[-1] == $readmacro_quote
          result = MalList.new([MalSym.new("quote"), result])
        elsif stack[-1] == $readmacro_quasiquote
          result = MalList.new([MalSym.new("quasiquote"), result])
        elsif stack[-1] == $readmacro_unquote
          result = MalList.new([MalSym.new("unquote"), result])
        elsif stack[-1] == $readmacro_spliceunquote
          result = MalList.new([MalSym.new("splice-unquote"), result])
        else 
          raise "Unreachable"
        end
        stack.pop
      end
      if is_special?(result) || unbalance > 0
        stack.push(result)
      else 
        Fiber.yield(result)
      end
    end
  end
end

def reader(input) 
  parse(tokenize(input))
end
