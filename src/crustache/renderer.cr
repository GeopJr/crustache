require "html"
require "./parser"
require "./syntax"
require "./filesystem"

module Crustache
  # :nodoc:
  class Renderer
    def initialize(@open_tag, @close_tag, @context, @fs, @out_io)
      @open_tag_default = @open_tag
      @close_tag_default = @close_tag
    end

    def template(t)
      t.content.each &.visit(self)
    end

    def section(s)
      if value = @context.lookup s.value
        case
        when value.is_a?(Enumerable)
          value.each do |ctx|
            scope ctx do
              s.content.each &.visit(self)
            end
          end

        when value.is_a?(String -> String)
          io = StringIO.new
          t = Syntax::Template.new s.content
          t.visit Stringify.new @open_tag, @close_tag, io
          io = StringIO.new value.call io.to_s
          t = Parser.new(@open_tag, @close_tag, io, value.to_s).parse
          io.clear
          t.visit(Renderer.new @open_tag, @close_tag, @context, @fs, io)
          @out_io << io.to_s

        else
          scope value do
            s.content.each &.visit(self)
          end
        end
      end
    end

    def invert(i)
      if value = @context.lookup i.value
        if value.is_a?(Enumerable)
          i.content.each(&.visit(self)) if value.empty?
        end
      else
        i.content.each &.visit(self)
      end
    end

    def output(o)
      (@out_io as IndentIO).indent_flag_off if @out_io.is_a?(IndentIO)
      if value = @context.lookup o.value
        if value.is_a?(-> String)
          io = StringIO.new value.call
          t = Parser.new(@open_tag_default, @close_tag_default, io, value.to_s).parse
          io.clear
          t.visit(Renderer.new @open_tag_default, @close_tag_default, @context, @fs, io)
          @out_io << HTML.escape io.to_s
        else
          @out_io << HTML.escape value.to_s
        end
      end
      (@out_io as IndentIO).indent_flag_on if @out_io.is_a?(IndentIO)
    end

    def raw(r)
      (@out_io as IndentIO).indent_flag_off if @out_io.is_a?(IndentIO)
      if value = @context.lookup r.value
        if value.is_a?(-> String)
          io = StringIO.new value.call
          t = Parser.new(@open_tag_default, @close_tag_default, io, value.to_s).parse
          io.clear
          t.visit(Renderer.new @open_tag_default, @close_tag_default, @context, @fs, io)
          @out_io << io.to_s
        else
          @out_io << value.to_s
        end
      end
      (@out_io as IndentIO).indent_flag_on if @out_io.is_a?(IndentIO)
    end

    def partial(p)
      if part = @fs.load p.value
        part.visit(Renderer.new @open_tag_default, @close_tag_default, @context, @fs, IndentIO.new(p.indent, @out_io))
      end
    end

    def comment(c); end

    def text(t)
      @out_io << t.value
    end

    def delim(d)
      @open_tag = d.open_tag
      @close_tag = d.close_tag
    end

    private def scope(ctx)
      @context = Context.new(ctx, @context)
      yield
      @context = @context.parent as Context
      nil
    end
  end

  # :nodoc:
  class Context
    getter parent

    def initialize(@context, @parent = nil); end

    def lookup(value)
      if value == "."
        return @context
      end

      ctx = @context

      vals = value.split(".")
      len = vals.length

      i = 0
      while i < len
        val = vals[i]
        case
        when ctx.responds_to?(:has_key?) && ctx.responds_to?(:[])
          if ctx.has_key?(val)
            ctx = ctx[val]
          else
            break
          end

        else
          break
        end
        i += 1
      end

      if i == len
        return ctx
      end

      if p = @parent
        p.lookup value
      else
        nil
      end
    end
  end

  # :nodoc:
  class IndentIO
    include IO

    def initialize(@indent, @io)
      @indent_flag = 0
      @eol_flag = true
    end

    def indent_flag_on
      @indent_flag -= 1
    end

    def indent_flag_off
      @indent_flag += 1
    end

    def write(s, len)
      start = 0
      i = 0
      while i < len
        if @eol_flag
          @io.write (s + start), (i - start)
          @io << @indent
          @eol_flag = false
          start = i
        end

        if s[i] == Parser::NEWLINE_N && @indent_flag == 0
          @eol_flag = true
        end

        i += 1
      end

      @io.write (s + start), (i - start)
    end
  end
end
